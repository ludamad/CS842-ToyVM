ast = require "ast"
ffi = require "ffi"
runtime = require "runtime"
librun = require 'libruntime'
gc = require "ggggc"

lj = require "libjit"

col = require "system.AnsiColors"

import INT_SIZE, VAL_SIZE, TYPE_TAG_BOOL, TYPE_TAG_INT
    from require "cmp_constants"

--------------------------------------------------------------------------------
-- The exported module
--------------------------------------------------------------------------------
M = {}
--------------------------------------------------------------------------------
-- Various symbol types for the compiler.
--------------------------------------------------------------------------------

cFaintW = (s) -> col.WHITE(s, col.FAINT)
-- Offset is 0 or 1:
StackRef = newtype {
    init: (@index = false) =>
    resolve: (f) =>
        if not @index
            @index = f\pushStackLoc()
    -- If we load to a 'value', we can save always storing if in a safe point
    store: (f, val) => f\stackStore @index, val
    load: (f) => f\stackLoad @index
    __tostring: () =>
        if @index
            return cFaintW("@") .. col.GREEN(@index)
        s = string.format("%p", @)
        s = s\sub(#s-1,#s)
        return cFaintW("@")..col.RED(s..'?')
}

M.Variable = newtype {
    parent: StackRef
    init: (@name) =>
        StackRef.init(@)
    link: (astNode) =>
        astNode.dest or= StackRef()
        stackRef = astNode.dest
        assert(stackRef.index == false)
        stackRef.index = @index
    __tostring: () => col.WHITE("$#{@name}", col.FAINT) .. StackRef.__tostring(@)
}

M.Constant = newtype {
    init: (@name, @value) =>
    store: (f) =>
        error "Cannot store to constant '#{@name or @value}'!"
    load: (f) =>
        if getmetatable(@value) == lj.NativeFunction
            return f\longConst @value.func
        if type(@value) == 'function'
            return @.value(f)
        return @value
    __tostring: () => col.GREEN("$#{@name}", col.FAINT)
}

--------------------------------------------------------------------------------
-- The scope object, arranged in a stack.
--------------------------------------------------------------------------------
M.Scope = newtype {
    init: (@parentScope = false) =>
        @variables = {}
        @varList = {}
    declare: (var) =>
        @variables[var.name] = var
        append @varList, var
    get: (name) =>
        scope = @
        while scope ~= false
            if scope.variables[name] ~= nil
                return scope.variables[name], scope
            scope = scope.parentScope
        return nil, scope
--    ensureAddressable: (block, name) => 
--        var, scope = @get(name)
}

--------------------------------------------------------------------------------
-- First pass of compilation:
--  - Resolve symbols
--------------------------------------------------------------------------------
ast.installOperation {
    methodName: "symbolResolve"
    recurseName: "_symbolRecurse"
    Statement: (S) =>
        @_symbolRecurse(S)
    Expr: (S) =>
        @_symbolRecurse(S)
    -- Recursively descend into child functions:
    Function: (S) =>
        for param in *@paramNames
            S\declare(M.Variable param)
        @body\_symbolRecurse(S)
    Block: (S) =>
        -- 'Push' a new scope:
        @scope = M.Scope(S)
        @_symbolRecurse(S)
    Operator: (S) =>
        @_symbolRecurse(S)
        @dest = StackRef()
    BoxStore: (S) =>
        @_symbolRecurse(S)
    FuncCall: (S) =>
        @func\symbolResolve(S)
        for arg in *@args
            arg\symbolResolve(S)
            -- Ensure that each is allocated to a subsequent index:
            arg.dest or= StackRef()
        if @isExpression
            @dest or= StackRef() -- Our return value requires one, as well.
    -- Assignables:
    RefStore: (S) =>
        print "Storing #{@name}"
        sym = S\get(@name)
        if sym == nil
            sym = M.Variable(@name)
            S\declare(sym)
        @symbol = sym
    -- Expressions:
    RefLoad: (S) =>
        sym = S\get(@name)
        if sym == nil
            error("No such symbol '#{@name}'.")
        @symbol = sym
    While: (S) =>
        @_symbolRecurse(S)
        @condition.dest = false
    If: (S) =>
        @_symbolRecurse(S)
        @condition.dest = false
    -- Statements:
    Assign: (S) =>
        for i=1,#@vars
            if @op ~= '='
                @values[i] = ast.Operator(@vars[i]\toExpr(), @op, @values[i])
        @_symbolRecurse(S)
        for i=1,#@vars
            var, val = @vars[i], @values[i]
            var\setUpForStore(val)
        @op = '=' -- For good measure, since operation was handled.
}

return M

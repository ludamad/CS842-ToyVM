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
    init: (f, @name) =>
        StackRef.init(@)
        -- Resolve variables immediately.
        -- We will reclaim their stack space if their scope is popped.
        @resolve(f)
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
    declare: (var) =>
        @variables[var.name] = var
    get: (name) =>
        scope = @
        while scope ~= false
            if scope.variables[name] ~= nil
                return scope.variables[name]
            scope = scope.parentScope
        return nil
}

--------------------------------------------------------------------------------
-- First pass of compilation:
--  - Resolve symbols
--------------------------------------------------------------------------------
ast.installOperation {
    methodName: "symbolResolve"
    recurseName: "_symbolRecurse"
    Statement: (f) =>
        @_symbolRecurse(f)
    Expr: (f) =>
        @_symbolRecurse(f)
    Function: () =>
        -- Do nothing
    Operator: (f) =>
        @_symbolRecurse(f)
        @dest = StackRef()
    BoxStore: (f) =>
        @_symbolRecurse(f)
    FuncCall: (f) =>
        @func\symbolResolve(f)
        for arg in *@args
            arg\symbolResolve(f)
            -- Ensure that each is allocated to a subsequent index:
            arg.dest or= StackRef()
        if @isExpression
            @dest or= StackRef() -- Our return value requires one, as well.
    -- Assignables:
    RefStore: (f) =>
        sym = f.scope\get(@name)
        if sym == nil
            sym = M.Variable(f, @name)
            f.scope\declare(sym)
        @symbol = sym
    -- Expressions:
    RefLoad: (f) =>
        sym = f.scope\get(@name)
        if sym == nil
            error("No such symbol '#{@name}'.")
        @symbol = sym
    While: (f) =>
        @_symbolRecurse(f)
        @condition.dest = false
    If: (f) =>
        @_symbolRecurse(f)
        @condition.dest = false
    -- Statements:
    Assign: (f) =>
        for i=1,#@vars
            if @op ~= '='
                @values[i] = ast.Operator(@vars[i]\toExpr(), @op, @values[i])
        @_symbolRecurse(f)
        for i=1,#@vars
            var, val = @vars[i], @values[i]
            var\setUpForStore(val)
        @op = '=' -- For good measure, since operation was handled.
}

return M

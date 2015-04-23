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
        @varLink = false
    resolve: (f) =>
        if not @index
            if @varLink
                @index = assert(@varLink.index, "link should have index!!")
            else
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
    init: (@name, @boxed = false) =>
        assert(type @name == "string")
        pretty @name
        StackRef.init(@)
    link: (astNode) =>
        astNode.dest or= StackRef()
        stackRef = astNode.dest
        assert not stackRef.varLink
        stackRef.varLink = @
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
    -- If the 'get' in the parent scope crosses a function barrier, we may need
    -- to generate a capture.
    -- @funcRoot == false implies global (provisionally, constant) scope.
    init: (@parentScope = false, @funcRoot = false) =>
        if @parentScope
            @funcRoot = @parentScope.funcRoot
        @variables = {}
        @varList = {}
    declare: (var) =>
        @variables[var.name] = var
        append @varList, var
    get: (name) =>
        assert @funcRoot, "Should not do get's on bare global scope."
        scope = @
        while scope ~= false
            if scope.variables[name] ~= nil
                isGlobalScope = not scope.funcRoot
                crossedFunc = (isGlobalScope or scope.funcRoot == @funcRoot)
                return scope.variables[name], crossedFunc, scope
            scope = scope.parentScope
        return nil, false, scope
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
    -- We not recursively descend into child functions:
    FuncBody: (S) => 
        if @functionBuilder
            @block\_symbolRecurse(S)
    Block: (S) =>
        -- 'Push' a new scope:
        @scope = M.Scope(S)
        @_symbolRecurse(@scope)
    Operator: (S) =>
        @_symbolRecurse(S)
        @dest = StackRef()
    BoxStore: (S) =>
        @_symbolRecurse(S)
    ObjStore: (S) =>
        @_symbolRecurse(S)
    FuncCall: (S) =>
        @func\symbolResolve(S)
        for arg in *@args
            arg\symbolResolve(S)
            -- Ensure that each is allocated to a subsequent index:
            arg.dest or= StackRef()
        @dest or= StackRef() -- Our return value requires one, as well.
    -- Assignables:
    RefStore: (S) =>
        sym, crossedFunc = S\get(@name)
        -- If something crosses a function, we must declare it locally
        -- later, and add it as a boxed parameter.
        --if crossedFunc
            -- append(S.funcRoot.captureVars, sym)
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
        --@condition.dest = false
    If: (S) =>
        @_symbolRecurse(S)
        --@condition.dest = false
    Object: (S) =>
        @dest = StackRef() -- Our object must be stored in its own value.
        @tempDest or= StackRef() -- Our object must be stored in a value.
        for {k, v} in *@value
            v.dest or= @tempDest
            v\symbolResolve()
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

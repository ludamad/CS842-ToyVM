ast = require "ast"
ffi = require "ffi"
runtime = require "runtime"
librun = require 'libruntime'
gc = require "ggggc"

lj = require "libjit"


Scope = newtype {
    init: (@parentScope = false) =>
        @variables = {}
    -- By default, a = 1 will declare in current context if not in above contexts
    declareIfNotPresent: (name) =>
        val = @get(name) 
        if val then return val
        return @declare(name)
    declare: (var) =>
        if type(var) == "table"
            @variables[var.name] = var
        else
            @variables[name] = var
        return var
    get: (name) =>
        scope = @
        while scope ~= false
            if scope.variables[name] ~= nil
                return scope.variables[name]
            scope = scope.parentScope
        return nil
}

Constant = newtype {
    init: (@value, @name = false) =>
    store: (f) =>
        error "Cannot store to constant '#{@name or @value}'!"
    load: (f) => @value
}

StackVar = newtype {
    init: (@index, @name = false) =>
    -- If we load to a 'value', we can save always storing if in a safe point
    store: (f, val) =>
        f\storeRelative(@value, f\getParam(@,))
    load: (f) =>
        f\loadRelative(f.stackFrame, 8*@index, lj.ulong)
    __tostring: () => "LocalVal(#{@index}, #{@name})"
}

--------------------------------------------------------------------------------
-- First function builder pass:
--  - Assign a stack location to every expression!
--------------------------------------------------------------------------------
ast.installOperation {
    methodName: "stackAlloc"
    -- Expressions:
    RefLoad: (f) =>
        -- Do not allow variable creation in value contexts.
        @srcVar = f\getStackVar(@name, false)
        @stackVar = f\getStackVar(@name, false)
        return @stackVar
    Operator: (f) =>
    -- Assignables:
    RefStore: (f) =>
        -- Allow variable creation in assignment contexts.
        var = f\getStackVar(@name, true)
    -- Statements:
    Assign: (f) =>
        for i=1,
}

-- Note: lj.Function to start has many members, some commonly named. We will be extending it twice, we must
-- take caution not to confuse any of the members.
FBStackAllocPass = newtype {
    parent: lj.Function
    init: (@ljContext, @paramNames, @builtins) =>
        initContext(@ljContext)
        -- Take how many args, return how many return values on object stack.
        lj.Function.init(@, @ljContext, lj.uint, {lj.uint})
        @stackVars = {}
        @nameToStackVar = {}
        @maxStackVars = 0
        for name in *@paramNames
            @pushStackVar(name)
    getStackVar: (name, create = false) =>
        var = @nameToStackVar[name]
        created = false
        if var == nil and not create
            error("!")
        if var == nil
            var = @pushStackVar(name)
            @nameToStackVar[name] = var
            created = true
        return var, created
    pushStackVar: (name) =>
        var = StackVar(#@stackVars, name)
        append @stackVars, var
        if name
            @nameToStackVar[name] = var
        @maxStackVars = math.max(#@stackVars, @maxStackVars)
        return var
    popStackVars: (n) =>
        for i=1,n
            endV = @stackVars[#@stackVars]
            if endV == nil then error('!')
            -- Pop:
            @stackVars[#@stackVars] = nil
}


FBJitCompilePass = newtype {
    parent: FBStackAllocPass
    init: (...) =>
        FBStackAllocPass.init(...)
        @constantPtrs = {}
        @compilePrelude()

    emitPrelude: () =>
        {:pstackTop, :pstack} = @ljContext.globals[0]
        argsV = @getParam(0)
        for i=1,#@params
            {:var} = @params[i]
            var.value = @loadRelative(argsV, 8*(i-1), lj.ulong)
            @scope\declareIfNotPresent(var)
        -- Reference the bottom of our stack frame, where arguments are held:
        val = @createLongConstant(lj.ptr, pstackTop)
        @pstackBot = @sub(@loadRelative(@pstackTopPtr, 0, lj.ptr), @getParam(0))
    -- Wraps a pointer value directly:
    createPtrRaw: (ptr) =>
        return @createLongConstant(lj.ptr, ffi.cast("unsigned long", ptr))
    -- Creates a managed pointer:
    createPtr: (val) =>
        logV "createPtr", val
        ptr = librun.langCreatePointer()
        ptr[0] = val
        append @constantPtrs, ptr
        return ptr, @createPtrRaw(ptr)
    pushScope: () =>
        @scope = M.Scope(@scope)
    frame: (args) =>
        ptr = @alloca(@createLongConstant(lj.ulong, #args * 8))
        for i=1,#args
            @storeRelative(ptr, 8*(i-1), args[i]) 
        return {ptr, @createLongConstant(lj.ulong, #args)} 
}

OpLoad = ast.methodInstall "load", {
    default: (n) => nil
    Param: (f) =>
        f\getParam(n.index)
    Operator: (f) => 
        l = n.left\load(f)
        r = n.right\load(f)
        switch n.op
            when '+'
                f\add(l, r)
            when '-'
                f\sub(l, r)
}

Pass1 = {}

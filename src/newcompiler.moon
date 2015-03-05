ast = require "ast"
ffi = require "ffi"
runtime = require "runtime"
librun = require 'libruntime'
gc = require "ggggc"

lj = require "libjit"

col = require "system.AnsiColors"

M = {} -- Module

--------------------------------------------------------------------------------
-- First function builder pass:
--  - Resolve symbols
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

cFaintW = (s) -> col.WHITE(s, col.FAINT)
StackRef = newtype {
    init: (@index = false) =>
    resolve: (f) =>
        if not @index
            @index = f\pushStackLoc()
    -- If we load to a 'value', we can save always storing if in a safe point
    store: (f, val) =>
        f\storeRelative(f.stackFrameVal, 8*@index, val)
    load: (f) =>
        f\loadRelative(f.stackFrameVal, 8*@index, lj.ulong)
    __tostring: () => 
        if @index
            return cFaintW("@") .. col.GREEN(@index)
        s = string.format("%p", @)
        s = s\sub(#s-1,#s)
        return cFaintW("@")..col.GREEN(s..'?')
}

M.Variable = newtype {
    parent: StackRef
    init: (f, @name) =>
        StackRef.init(@)
        -- Resolve variables immediately.
        -- We will reclaim their stack space if their scope is popped.
        @resolve(f)
    link: (stackRef) =>
        assert(stackRef.index == false)
        stackRef.index = @index
    __tostring: () => col.WHITE("$#{@name}", col.FAINT) .. StackRef.__tostring(@)
}

M.Constant = newtype {
    init: (@name, @value) =>
    store: (f) =>
        error "Cannot store to constant '#{@name or @value}'!"
    load: (f) => @value
    __tostring: () => col.RED("$#{@name}", col.FAINT)
}


ast.installOperation {
    methodName: "symbolResolve"
    recurseName: "_symbolRecurse"
    default: (f) =>
        @_symbolRecurse(f)
        @dest = StackRef()
    -- Assignables:
    RefStore: (f) =>
        sym = f.scope\get(@name)
        if sym == nil
            sym = M.Variable(@name)
            f.scope\declare(@name)
        @symbol = sym
    -- Expressions:
    RefLoad: (f) =>
        sym = f.scope\get(@name)
        if sym == nil
            error("No such symbol '#{@name}'.")
        @symbol = sym
        @dest = StackRef()
    -- Statements:
    Assign: (f) =>
        @_symbolRecurse(f)
        for i=1,#@vars
            var, val = @vars[i], @values[i]
            var.symbol\link(val.dest)
}

ast.installOperation {
    methodName: "stackResolve"
    recurseName: "_stackRecurse"
    default: (f) =>
        f\saveStackLoc()
        @_stackRecurse(f)
        f\loadStackLoc()
        @dest\resolve(f)
}

-- Note: lj.Function to start has many members, some commonly named. We will be extending it twice, we must
-- take caution not to confuse any of the members.
FBStackResolver = newtype {
    parent: lj.Function
        -- Take how many args, return how many return values on object stack.
    init: (@paramNames) =>
        @stackLocHistory = {}
        @stackLoc = 0
        @maxStackLoc = @stackLoc
        for i=1,#@paramNames
            var = M.Variable(@, @paramNames[i])
            @scope\declare(var)
    saveStackLoc: () =>
        append @stackLocHistory, @stackLoc
    loadStackLoc: () =>
        top = @stackLocHistory[#@stackLocHistory]
        @stackLocHistory[#@stackLocHistory] = nil
        @stackLoc = top
    loadAndPushStackLoc: () => 
        @loadStackLoc()
        return @pushStackLoc()
    pushStackLoc: () => 
        @stackLoc += 1
        @maxStackLoc = math.max(@stackLoc, @maxStackLoc)
        return @stackLoc - 1
    popStackVars: (n) =>
        for i=1,n
            endV = @stackVars[#@stackVars]
            if endV == nil then error('!')
            -- Pop:
            @stackVars[#@stackVars] = nil
}


FBJitCompiler = newtype {
    parent: FBStackResolver
    init: (@ljContext, paramNames, globalScope) =>
        lj.Function.init(@, @ljContext, lj.uint, {lj.uint})
        @scope = M.Scope(globalScope)
        FBStackResolver.init(@, paramNames)
        @constantPtrs = {}
        --@compilePrelude()

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
    frame: (args) =>
        ptr = @alloca(@createLongConstant(lj.ulong, #args * 8))
        for i=1,#args
            @storeRelative(ptr, 8*(i-1), args[i]) 
        return {ptr, @createLongConstant(lj.ulong, #args)} 
}

M.FunctionBuilder = FBJitCompiler

return M

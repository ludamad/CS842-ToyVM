ast = require "ast"
ffi = require "ffi"
runtime = require "runtime"
librun = require 'libruntime'
gc = require "ggggc"

lj = require "libjit"

col = require "system.AnsiColors"

--------------------------------------------------------------------------------
-- The exported module
--------------------------------------------------------------------------------
M = {} -- Module
INT_SIZE = 4
VAL_SIZE = 8

TYPE_TAG_INT = 1

-- Utility methods:

longConst = (f, v) ->
    return f\createLongConstant(lj.ulong, ffi.cast("uint64_t", v))
intConst = (f, v) ->
    return f\createNintConstant(lj.uint, ffi.cast("unsigned int", v))
-- Make a constant in our tagged format:
taggedIntVal = (f, num) ->
    val = ffi.new("uint64_t[1]")
    int_view = ffi.cast("int*", val)
    int_view[0] = num 
    int_view[1] = TYPE_TAG_INT
    return f\createLongConstant(lj.ulong, val[0])

unboxInt = (f, val) ->
    return f\shr(val, intConst(f, 32)) 
boxInt = (f, val) ->
    return f\add(longConst(f, 1), f\shr(val, intConst(f, 32))) 
--------------------------------------------------------------------------------
-- Various symbol types for the compiler.
--------------------------------------------------------------------------------
cFaintW = (s) -> col.WHITE(s, col.FAINT)
stackStore = (f, index, val) ->
    f\storeRelative(f.stackFrameVal, VAL_SIZE*index, val)
stackStoreHalf = (f, index, offset, val) ->
    f\storeRelative(f.stackFrameVal, VAL_SIZE*index + offset * INT_SIZE, val)
stackLoad = (f, index) ->
    f\loadRelative(f.stackFrameVal, VAL_SIZE*index, lj.ulong)
-- Offset is 0 or 1:
stackLoadHalf = (f, index, offset) ->
    f\loadRelative(f.stackFrameVal, VAL_SIZE*index + offset * INT_SIZE, lj.uint)

StackRef = newtype {
    init: (@index = false) =>
    resolve: (f) =>
        if not @index
            @index = f\pushStackLoc()
    -- If we load to a 'value', we can save always storing if in a safe point
    store: (f, val) => stackStore f, @index, val
    load: (f) => stackLoad f, @index
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
    Operator: (f) =>
        @_symbolRecurse(f)
        @dest = StackRef()
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
    -- Statements:
    Assign: (f) =>
        @_symbolRecurse(f)
        for i=1,#@vars
            var, val = @vars[i], @values[i]
            if not val.dest
                val.dest = StackRef()
            var.symbol\link(val.dest)
}
--------------------------------------------------------------------------------
-- Second pass of compilation:
--  - Resolve stack locations
--------------------------------------------------------------------------------
ast.installOperation {
    methodName: "stackResolve"
    recurseName: "_stackRecurse"
    default: (f) =>
        f\saveStackLoc()
        @_stackRecurse(f)
        f\loadStackLoc()
    Expr: (f) =>
        f\saveStackLoc()
        @_stackRecurse(f)
        f\loadStackLoc()
        if @dest
            @dest\resolve(f)
}
--------------------------------------------------------------------------------
-- Third pass of compilation:
--  - Output code
--------------------------------------------------------------------------------

loadE = (f,e) -> 
    if e.dest 
        return e.dest\load(f)
    else
        return e.compiledVal
 
--------------------------------------------------------------------------------
--  Stack set up, nil'ing and returning.
--------------------------------------------------------------------------------
-- Sets up our stack frame properly:
compileFuncPrelude = (f) ->
    {:pstackTop, :defaultValue} = f.ljContext.globals[0]

    -- The stack has a special guarantee 'everything outside is zero initialized'.
    -- We thus hack GGGGC to allow for zero pointers and achieve convenience.
    -- The only remaining thing is to clear up stack space on any return site by nil'ing it
    -- to retain this invariant.
    f.stackTopPtr = longConst(f, pstackTop)
    stackTopVal = f\loadRelative(f.stackTopPtr, 0, lj.ptr)
    f.argsNVal = f\getParam(0)
    f.stackFrameVal = f\sub(stackTopVal, f\mul(f.argsNVal, longConst(f, VAL_SIZE)))

    -- How much total varSpace we want:
    varSpace = longConst(f, f.stackPtrsUsed * VAL_SIZE)
    f\storeRelative(f.stackTopPtr, 0, f\add(f.stackFrameVal, varSpace))

-- Compiles the necessary cleanup for returning:
compileFuncReturn = (f, values) ->
    numRet = #values
    numRetVal = longConst(f, numRet)
    retSpace = longConst(f, numRet * VAL_SIZE)

    nullVal = longConst(f, 0)
    f\storeRelative(f.stackTopPtr, 0, f\add(f.stackFrameVal, retSpace))
    for i=numRet,f.stackPtrsUsed-1
        stackStore(f, i, nullVal)
    f\_return(numRetVal)

compileNumCheck = (f, val) -> 
    -- TODO
--------------------------------------------------------------------------------
--  Expression compilation:
--------------------------------------------------------------------------------
ast.installOperation {
    methodName: "compileVal"
    recurseName: "_compileValRecurse"
    -- AST node handlers:
    RefLoad: (f) => 
        return @symbol\load(f)
    IntLit: (f) =>
        return taggedIntVal(f, tonumber @value)
    StringLit: (f) =>
        if not stringPtrs[@value]
            stringPtrs[@value] = librun.langNewString(@value, #@value)
        ptr, jitVal = f\createPtr(stringPtrs[@.value])
        return f\loadRelative(jitVal, 0, lj.ulong)
    Operator: (f) =>
        @_compileRecurse(f)
        op = switch @op
            when '-' then f.sub
            when '+' then f.add
            when '*' then f.mul
            when '/' then f.div
            when '%' then f.rem
        val1 = loadE(f, @left)
        compileNumCheck(val1)
        val2 = loadE(f, @right)
        compileNumCheck(val2)
        ret = op(f, unboxInt(f, val1), unboxInt(f, val2))
        return boxInt(f, ret)
    FuncCall: (@) =>
        {func, args} = @value
        value = @compileNode(func)
        logV "Calling"
        @call(value, "", @frame [@compileNode arg for arg in *args])
}
   
ast.installOperation {
    methodName: "compile"
    recurseName: "_compileRecurse"
    FuncBody: (f) =>
        compileFuncPrelude(f)
        @_compileRecurse(f)
        compileFuncReturn(f, {})
    Expr: (f) =>
        @compiledVal = @compileVal(f)
        if @dest
            @dest\store(f, @compiledVal)
    RefStore: (f) =>
    Assign: (f) =>
        @_compileRecurse(f)
}

initContext = (C) -> 
    if not rawget C, 'initialized'
        log "initContext is running! mmap funkiness ahead."
        PSTACKSIZE = VAL_SIZE*1024^2
        C.globals = ffi.new("struct LangGlobals[1]")
        C.initialized = true
        librun.langGlobalsInit(C.globals, PSTACKSIZE)
        log "initContext has ran."

--------------------------------------------------------------------------------
-- Function builder, thin interface to LibJIT's function_t type.
-- Note: lj.Function to start has many members, some commonly named. We will be extending it a lot, we must
-- take caution not to confuse any of the members.
-------------------------------------------------------------------------------
M.FunctionBuilder = newtype {
    parent: lj.Function
    init: (@ljContext, paramNames, globalScope) =>
        lj.Function.init(@, @ljContext, lj.uint, {lj.uint})
        initContext(@ljContext)
        level = @getMaxOptimizationLevel()
        print 'level' , level
        @setOptimizationLevel(level)
        @scope = M.Scope(globalScope)
        @stackSymInit(@, paramNames)
        @constantPtrs = {}
    ------------------------------------------------------------------------------
    -- Stack and symbol resolving:
    ------------------------------------------------------------------------------
    stackSymInit: (@paramNames) =>
        @stackLocHistory = {}
        @stackLoc = 0
        @stackPtrsUsed = @stackLoc
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
        @stackPtrsUsed = math.max(@stackLoc, @stackPtrsUsed)
        return @stackLoc - 1
    popStackVars: (n) =>
        for i=1,n
            endV = @stackVars[#@stackVars]
            if endV == nil then error('!')
            -- Pop:
            @stackVars[#@stackVars] = nil
    ------------------------------------------------------------------------------
    -- LibJIT emission:
    ------------------------------------------------------------------------------
    emitPrelude: () =>
        {:pstackTop, :pstack} = @ljContext.globals[0]
        argsV = @getParam(0)
        for i=1,#@params
            {:var} = @params[i]
            var.value = @loadRelative(argsV, VAL_SIZE*(i-1), lj.ulong)
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
        ptr = @alloca(@createLongConstant(lj.ulong, #args * VAL_SIZE))
        for i=1,#args
            @storeRelative(ptr, VAL_SIZE*(i-1), args[i]) 
        return {ptr, @createLongConstant(lj.ulong, #args)} 
    toCFunction: () =>
        return ffi.cast("LangFunc", lj.Function.toCFunction(@))
}

return M

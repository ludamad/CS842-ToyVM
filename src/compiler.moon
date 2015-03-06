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
    return f\createLongConstant(lj.ulong, ffi.cast("int64_t",v))
intConst = (f, v) ->
    return f\createNintConstant(lj.uint, ffi.cast("unsigned int", v))
-- Make a constant in our tagged format:
taggedIntVal = (f, num) ->
    val = ffi.new("uint64_t[1]")
    int_view = ffi.cast("int*", val)
    int_view[0] = TYPE_TAG_INT
    int_view[1] = num 
    return f\createLongConstant(lj.ulong, val[0])

unboxInt = (f, val) ->
    return f\shr(val, intConst(f, 32)) 
boxInt = (f, val) ->
    return f\add(longConst(f, 1), f\shl(val, intConst(f, 32))) 
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
            return longConst(f, @value.func)
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
    Operator: (f) =>
        @_symbolRecurse(f)
        @dest = StackRef()
    FuncCall: (f) =>
        @func\symbolResolve(f)
        for arg in *@args
            arg\symbolResolve(f)
            -- Ensure that each is allocated to a subsequent index:
            arg.dest or= StackRef()
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
        for i=1,#@vars
            if @op ~= '='
                @values[i] = ast.Operator(@vars[i]\toExpr(), @op, @values[i])
        @_symbolRecurse(f)
        for i=1,#@vars
            var, val = @vars[i], @values[i]
            var.symbol\link(val)
        @op = '=' -- For good measure, since operation was handled.
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
    {:pstackTop} = f.ljContext.globals[0]

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
    f.stackTopVal = f\add(f.stackFrameVal, varSpace)
    f\storeRelative(f.stackTopPtr, 0, f.stackTopVal)

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
stringPtrs = {} -- Cache of string constants. TODO find time to free this.
-- Creates a managed pointer to a string constant:
getStringPtr = (str) -> 
    if stringPtrs[str] 
        return stringPtrs[str]
    lStr = librun.langStringCopy(str, #str)
    ptr = librun.langCreatePointer()
    ptr[0] = lStr
    stringPtrs[str] = ptr
    return ptr

ast.installOperation {
    methodName: "compileVal"
    recurseName: "_compileValRecurse"
    -- AST node handlers:
    RefLoad: (f) => 
        return @symbol\load(f)
    IntLit: (f) =>
        return taggedIntVal(f, tonumber @value)
    StringLit: (f) =>
        ptr = getStringPtr(@value)
        return f\loadRelative(longConst(f, ptr), 0, lj.ulong)
    Operator: (f) =>
        @_compileRecurse(f)
        val1 = loadE(f, @left)
        val2 = loadE(f, @right)
        if @op == '..'
            func = runtime.stringConcat
            return f\call(func, 'stringConcat', {val1, val2})
        op = switch @op
            when '-' then f.sub
            when '+' then f.add
            when '*' then f.mul
            when '/' then f.div
            when '%' then f.rem
        compileNumCheck(val1)
        compileNumCheck(val2)
        ret = op(f, unboxInt(f, val1), unboxInt(f, val2))
        return boxInt(f, ret)
    FuncCall: (f) =>
        @_compileRecurse(f)
        fVal = loadE(f, @func)
        logV "Calling #{f}"
        stackLoc = @args[#@args].dest.index
        callSpace = longConst(f, VAL_SIZE * (stackLoc+1))
        skipFiddle = (stackLoc + 1 == f.stackPtrsUsed)
        if not skipFiddle
            f\storeRelative(f.stackTopPtr, 0, f\add(f.stackFrameVal, callSpace))
        val = f\callIndirect(fVal, {intConst(f, #@args)}, lj.uint, {lj.uint})
        if not skipFiddle
            f\storeRelative(f.stackTopPtr, 0, f.stackTopVal)
        return val 
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
    createPtrRaw: (ptr) =>
        return @createLongConstant(lj.ptr, ffi.cast("unsigned long", ptr))
    toCFunction: () =>
        return ffi.cast("LangFunc", lj.Function.toCFunction(@))
    smartDump: () =>
        {:pstackTop} = @ljContext.globals[0]
        f = ffi.cast("unsigned long", pstackTop)
        stackStr = tostring(f) 
        stackStr = stackStr\sub(1, #stackStr-3)
        d = @dump()\split('\n')
        nameCache = {}
        names = {"foo", "bar", "baz", "cindy", "alpha", "bravo", "wilfrid", "tusk", "sam", "valz", "sin"}
        cntr = 0
        nameBetter = (digits) ->
            if nameCache[digits] 
                return nameCache[digits]
            nameCache[digits] = names[cntr%#names+1]
            if cntr >= #names
                nameCache[digits] ..= math.floor(cntr/#names)
            cntr += 1
            return nameCache[digits]
        for i=#d,1,-1
            if d[i]\find('outgoing') or d[i]\find('return_reg') or d[i]\find('ends')
                for j=i+1, #d
                    d[j-1] = d[j]
                d[#d] = nil

        cnt = 1
        for i=1,#d
            replace = (s, m) ->
                d[i] = d[i]\gsub s, m
            replaceConstant = (name, func) ->
                f = ffi.cast("unsigned long", func)
                str1 = tostring(f) 
                str1 = str1\sub(1, #str1-3)
                str2 = ("0x%x")\format(tonumber f)
                replace(str1, col.GREEN("$#{name}",col.BOLD))
                replace(str2, col.GREEN("$#{name}",col.BOLD))
            for k, v in pairs runtime
                if getmetatable(v) == lj.NativeFunction 
                    replaceConstant(k, v.func)
            for k, v in pairs @scope.parentScope.variables
                replaceConstant(v.name, v.value.func)
            replace '.L:%s*', () ->
                s = col.WHITE("--- Section #{cnt} ---", col.FAINT)
                cnt += 1
                return s
            replace(stackStr, col.YELLOW('$stack',col.BOLD))
            replace 'load_relative_long%((.*), (.*)%)', (a,b) ->
                return "#{a}[#{b}]" 
            replace 'call.*%((.*)%)', (a) -> "call #{a}"
            replace 'store_relative_long%((.*), (.*), (.*)%)', (a,b,c) ->
                c = tonumber(c)/8
                return "#{a}[#{c}] = #{b}" 
            replace 'l(%d+)', (digits) ->
                color = col.pickCol(tonumber digits)
                return color(nameBetter digits)
            replace '(%d+)%[0%]', (digits) ->
                asLong = ffi.cast("unsigned long", tonumber digits)
                asPtr = ffi.cast("LangString**", asLong)[0]
                arr = asPtr[0].array[0]
                newStr = ffi.string(arr.a__data, arr.length - 1)
                return col.MAGENTA("\"#{newStr}\"", col.BOLD)

        print table.concat(d,'\n')
}

return M

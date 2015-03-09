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
M.VAL_SIZE = VAL_SIZE

-- Anything that successfully AND's with
-- almost all 0s into 0 is true
M.TYPE_TAG_BOOL = 1
M.TYPE_TAG_INT = 3
M.TYPE_TAG_FLOAT = 5

-- Utility methods:

longConst = (f, v) ->
    return f\createLongConstant(lj.ulong, ffi.cast("int64_t",v))
intConst = (f, v) ->
    return f\createNintConstant(lj.uint, ffi.cast("unsigned int", v))
-- Make a constant in our tagged format:
taggedIntVal = (f, num) ->
    numPacked = ffi.new("uint64_t[1]")
    val = ffi.cast("LangValue*", numPacked)[0]
    val.tag = M.TYPE_TAG_INT
    val.val = num 
    return f\createLongConstant(lj.ulong, numPacked[0])

unboxInt = (f, val) ->
    return f\shr(val, longConst(f, 32)) 
boxInt = (f, val) ->
    shift = f\shl(val, longConst(f, 32))
    return f\add(longConst(f, M.TYPE_TAG_INT), shift) 
boxBool = (f, val) ->
    return f\add(longConst(f, M.TYPE_TAG_BOOL), f\shl(val, longConst(f, 32))) 

truthCheck = (f, val) ->
    -- AND against a string of almost all 1
    -- since 000..0 and 000..1 are the only false values.
    TRUTH_CHECKER = longConst(f, -2)
    return f\_and(val, TRUTH_CHECKER), longConst(f, 0)
--------------------------------------------------------------------------------
-- Various symbol types for the compiler.
--------------------------------------------------------------------------------

cFaintW = (s) -> col.WHITE(s, col.FAINT)
stackStore = (f, index, val) ->
    f\storeRelative(f.stackFrameVal, VAL_SIZE*index, val)
stackLoad = (f, index) ->
    val = f\loadRelative(f.stackFrameVal, VAL_SIZE*index, lj.ulong)
    return val
-- Offset is 0 or 1:
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
    Function: (f) => 
        -- Do nothing with the AST (belongs to different context)
        if @dest
            @dest\resolve(f)
    FuncCall: (f) =>
        @lastStackLoc = f.stackLoc
        f\saveStackLoc()
        @_stackRecurse(f)
        f\loadStackLoc()
        if @dest
            @dest\resolve(f)
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
    Function: (f) =>
        @compiledFunc = M.compileFunc f.ljContext, @paramNames, @body, f.scope
        return longConst(f, @compiledFunc\toCFunction())
    Operator: (f) =>
        @_compileRecurse(f)
        val1 = loadE(f, @left)
        val2 = loadE(f, @right)
        if @op == '..'
            func = runtime.stringConcat
            return f\call(func, 'stringConcat', {val1, val2})
        op, boxer = switch @op
            when '-' then f.sub, boxInt
            when '+' then f.add, boxInt
            when '*' then f.mul, boxInt
            when '/' then f.div, boxInt
            when '%' then f.rem, boxInt
            when '<' then f.lt, boxBool
            when '>' then f.gt, boxBool
            when '>=' then f.gte, boxBool
            when '<=' then f.lte, boxBool
            when '==' then f.eq, boxBool
        if op != '=='
            compileNumCheck(val1)
            compileNumCheck(val2)
        i1 = unboxInt(f, val1)
        i2 = unboxInt(f,val2)
        ret = op(f,i1, i2) 
        return boxer(f, ret)
    BoxNew: (f) => 
        @_compileRecurse(f)
        -- Not much else to do but ask the runtime kindly for a box.
        box = f\boxNew()
        expr = @expr.compiledVal
        f\boxStore(box, expr)
        return box
    BoxLoad: (f) => 
        @_compileRecurse(f)
        -- Not much else to do but ask the runtime kindly for a box.
        return f\boxLoad(@ptr.compiledVal)
}

ast.installOperation {
    methodName: "compile"
    recurseName: "_compileRecurse"
    FuncBody: (f) =>
        print("Funcbody")
        compileFuncPrelude(f)
        @_compileRecurse(f)
        compileFuncReturn(f, {})
    If: (f) =>
        isTrue = truthCheck(f, @condition\compileVal(f))
        @labelEnd = lj.Label()
        f\branchIfNot(isTrue, @labelEnd)
        @block\compile(f)
        f\label(@labelEnd)
    While: (f) =>
        @labelCheck = lj.Label()
        @labelLoopStart = lj.Label()
        f\branch(@labelCheck)
        -- Resolve block label:
        f\label(@labelLoopStart)
        @block\compile(f)
        -- Resolve check label:
        f\label(@labelCheck)
        isTrue = truthCheck(f, @condition\compileVal(f))
        f\branchIf(isTrue, @labelLoopStart)
    Block: (f) =>
        @_compileRecurse(f)
    FuncCall: (f) =>
        @_compileRecurse(f)
        fVal = loadE(f, @func)
        -- @lastStackLoc is the next stack index after the current variables
        callSpace = longConst(f, VAL_SIZE * (@lastStackLoc + #@args))
        if (@lastStackLoc + #@args ~= f.stackPtrsUsed)
            f\storeRelative(f.stackTopPtr, 0, f\add(f.stackFrameVal, callSpace))
        val = f\callIndirect(fVal, {intConst(f, #@args)}, lj.uint, {lj.uint})
        -- Must restore after return value changes in top pointer:
        f\storeRelative(f.stackTopPtr, 0, f.stackTopVal)
        if @isExpression
            @compiledVal = @dest\load(f)
    Expr: (f) =>
        @compiledVal = @compileVal(f)
        if @dest
            @dest\store(f, @compiledVal)
    Assignable: (f) => @_compileRecurse(f)
    Assign: (f) =>
        for i=1,#@vars
            var, val = @vars[i], @values[i]
            val\compile(f)
            var\compile(f)
            var\generateStore(f, val)
}

refLoad = (f, v, offset = 0) ->
    return f\loadRelative(v, offset, lj.ulong)

refStore = (f, v, data, offset = 0) ->
    return f\storeRelative(v, offset, data)

--------------------------------------------------------------------------------
-- Function builder, thin interface to LibJIT's function_t type.
-- Note: lj.Function to start has many members, some commonly named. We will be extending it a lot, we must
-- take caution not to confuse any of the members.
-------------------------------------------------------------------------------
M.FunctionBuilder = newtype {
    parent: lj.Function
    init: (@ljContext, paramNames, globalScope) =>
        lj.Function.init(@, @ljContext, lj.uint, {lj.uint})
        level = @getMaxOptimizationLevel()
        @setOptimizationLevel(level)
        @scope = M.Scope(globalScope)
        @stackSymInit(paramNames)
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
    boxNew: () =>
        {:types} = @ljContext.globals[0]
        {:boxType}  = types
        boxPtrVal = longConst(@, boxType)
        val = @call(runtime.gcMalloc, 'NewBox', {refLoad(@, boxPtrVal)})
        return val
    boxLoad: (box) =>
        return refLoad(@, box, VAL_SIZE) 
    boxStore: (box, val) =>
        return refStore(@, box, val, VAL_SIZE) 
        
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
}

M.compileFunc = (ljContext, paramNames, ast, scope) ->
    fb = M.FunctionBuilder(ljContext, paramNames, scope)
    ast\symbolResolve(fb)
    ast\stackResolve(fb)
    ast\compile(fb)
    print fb\smartDump()
    fb\compile()
    return fb

--------------------------------------------------------------------------------
-- Colorful LibJIT IR dumper:
--------------------------------------------------------------------------------
M.FunctionBuilder.smartDump = () =>
    {:pstackTop, :types} = @ljContext.globals[0]
    f = ffi.cast("unsigned long", pstackTop)
    stackStr = tostring(f) 
    stackStr = stackStr\sub(1, #stackStr-3)
    d = @dump()\split('\n')
    nameCache = {}
    names = {"foo", "bar", "baz", "cindy", "alpha", "bravo", "wilfrid", "tusk", "sam", "valz", "sin", 'pindet', 'sukki', 'oPtr', 'ranDat'}
    cntr = 0
    nameBetter = (digits) ->
        if nameCache[digits] 
            return nameCache[digits]
        nameCache[digits] = names[cntr%#names+1]
        if cntr >= #names
            nameCache[digits] ..= math.floor(cntr/#names)
        cntr += 1
        return nameCache[digits]
   -- for i=#d,1,-1
   --     if d[i]\find('outgoing') or d[i]\find('return_reg') or d[i]\find('ends')
   --         for j=i+1, #d
   --             d[j-1] = d[j]
   --         d[#d] = nil

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
        scope = @scope
        while scope
            for k, v in pairs scope.variables
                if rawget(v, 'value') and type(v.value) == 'table'
                    replaceConstant(v.name, v.value.func)
            scope = scope.parentScope
        replace '.L:%s*', () ->
            s = col.WHITE("--- Section #{cnt} ---", col.FAINT)
            cnt += 1
            return s
        replace(stackStr, col.YELLOW('$stack',col.BOLD))
        replace 'load_relative_long%((.*), (.*)%)', (a,b) ->
            return "#{a}[#{b/8}]" 
        replace 'call.*%((.*)%)', (a) -> "call #{a}"
        replace 'store_relative_long%((.*), (.*), (.*)%)', (a,b,c) ->
            c = tonumber(c)/8
            return "#{a}[#{c}] = #{b}" 
        replace 'l(%d+)', (digits) ->
            color = col.pickCol(tonumber digits)
            return color(nameBetter digits)
        replace '(%d+)%[0%]', (digits) ->
            -- This should be a constant GC object.
            -- (Otherwise, we may very well segfault :-)
            asLong = ffi.cast("unsigned long", tonumber digits)
            asS = ffi.cast("LangString**", asLong)[0]
            if asS[0].gcHeader.descriptor__ptr == types.stringType[0]
                arr = asS[0].array[0]
                newStr = ffi.string(arr.a__data, arr.length - 1)
                return col.MAGENTA("\"#{newStr}\"", col.BOLD)
            if asS[0].gcHeader.descriptor__ptr == types.stringType[0][0].header.descriptor__ptr
                return col.WHITE("<BoxType>", col.BOLD)
            return "*(GC** #{digits})"
        replace '(%d+)', (digits) ->
            if tonumber(digits) < 4294967296
                return digits
            endChr = ffi.new('char*[1]')
            num = ffi.C.strtoull(digits, endChr, 10)
            numPtr = ffi.new('uint64_t[1]', num)
            val = ffi.cast('LangValue*', numPtr)[0]
            return col.GREEN("#{val.val}" , col.BOLD).. col.WHITE("!#{val.tag}", col.FAINT)

    return table.concat(d,'\n')

return M

--------------------------------------------------------------------------------
-- Imports
--------------------------------------------------------------------------------

ast = require "ast"
ffi = require "ffi"
runtime = require "runtime"
librun = require 'libruntime'
gc = require "ggggc"

lj = require "libjit"

col = require "system.AnsiColors"

import Scope, Variable, Constant
    from require "cmp_sym_resolve"

import INT_SIZE, VAL_SIZE, TYPE_TAG_BOOL, TYPE_TAG_INT
    from require "cmp_constants"

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------

fcast = ffi.cast
fnew = ffi.new

-- Exported
-- Union of FFI pointer types:
LangValue = newtype {
    init: (tag = 0, val = 0) =>
        @lptr = fnew("uint64_t[1]")
        @ptr = ffi.cast("LangValue*", @lptr)
        @setTag tag
        @setVal val
    longPtr: () => @lptr
    long: () => @lptr[0]
    setLong: (l) => @lptr[0] = l
    tag: () => @ptr[0].tag
    setTag: (t) => @ptr[0].tag = t
    val: () => @ptr[0].val
    setVal: (v) => @ptr[0].val = v
}

--------------------------------------------------------------------------------
-- Exported
-- Function builder, thin interface to LibJIT's function_t type.
-- Note: lj.Function to start has many members, some commonly named. We will be extending it, we
-- take caution not to confuse any of the members.
-------------------------------------------------------------------------------

FunctionBuilder = newtype {
    parent: lj.Function
    init: (@ljContext, @bodyAst, @scope, @paramNames = {}) =>
        assert @bodyAst, "Function builder requires AST as parameter"
        lj.Function.init(@, @ljContext, lj.uint, {lj.uint})
        level = @getMaxOptimizationLevel()

        @setOptimizationLevel(level)

        @constantPtrs = {}

        @stackLocHistory = {}
        @stackLoc = 0
        @stackPtrsUsed = @stackLoc
        @stackSymInit(@paramNames, @scope)

    ------------------------------------------------------------------------------
    -- Stack and symbol resolving:
    ------------------------------------------------------------------------------
    stackSymInit: (@paramNames, @scope) =>
        for name in *@paramNames
            var = Variable(name)
            @scope\declare(var)
        @stackPtrsUsed = @stackLoc

    popStackVars: (n) =>
        for i=1,n
            endV = @stackVars[#@stackVars]
            if endV == nil then error('!')
            -- Pop:
            @stackVars[#@stackVars] = nil

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

    ------------------------------------------------------------------------------
    ---- LibJIT emission:
    ------------------------------------------------------------------------------
    longConst: (val) =>
        return @createLongConstant(lj.ptr, fcast("unsigned long", val))
    intConst: (val) =>
        return @createNintConstant(lj.uint, fcast("unsigned int", val))
    taggedIntConst: (val) =>
        lVal = LangValue(TYPE_TAG_INT, val)
        print val, lVal\long()
        return @createLongConstant(lj.ulong, lVal\long())

    boxTypeConst: () =>
        return @refLoad @longConst(@ljContext.boxTypeDesc)

    stringTypeConst: () =>
        return @refLoad @longConst(@ljContext.stringTypeDesc)

    ------------------------------------------------------------------------------
    -- Low level dereferencing:
    ------------------------------------------------------------------------------

    refLoad: (v, offset = 0) =>
        return @loadRelative(v, offset, lj.ulong)

    refStore: (v, data, offset = 0) =>
        return @storeRelative(v, offset, data)

    ------------------------------------------------------------------------------
    -- Stack dereferencing:
    ------------------------------------------------------------------------------

    stackLoad: (index) =>
        val = @loadRelative(@stackFrameVal, VAL_SIZE*index, lj.ulong)
        return val
    stackStore: (index, val) =>
        @storeRelative(@stackFrameVal, VAL_SIZE*index, val)

    ------------------------------------------------------------------------------
    -- Boxes, for high-level references:
    ------------------------------------------------------------------------------

    boxNew: () =>
        val = @call(runtime.gcMalloc, 'NewBox', {@boxTypeConst()})
        return val
    boxLoad: (box) =>
        return @refLoad(box, 2*VAL_SIZE)
    boxStore: (box, val) =>
        return @refStore(box, val, 2*VAL_SIZE)

    ------------------------------------------------------------------------------
    -- Language value manipulation:
    ------------------------------------------------------------------------------

    getLVal: (val) =>
        return @shr val, @longConst(32)
    makeLVal: (val, tag) =>
        shift = @shl val, @longConst(32)
        return @add @longConst(tag), shift
    makeLValInt: (val) => @makeLVal(val, TYPE_TAG_INT)
    makeLValBool: (val) => @makeLVal(val, TYPE_TAG_BOOL)

    ------------------------------------------------------------------------------
    -- Branching and truth checking convenience functions:
    ------------------------------------------------------------------------------
    truthCheck: (val) =>
        -- AND against a string of almost all 1
        -- since 000..0 and 000..1 are the only false values.
        TRUTH_CHECKER = @longConst(-2)
        return @_and(val, TRUTH_CHECKER), @longConst(0)

    ------------------------------------------------------------------------------
    -- Lua-callable emission:
    ------------------------------------------------------------------------------
    toCFunction: () =>
        return fcast("LangFunc", lj.Function.toCFunction(@))
 
    --------------------------------------------------------------------------------
    --  Stack set up, nil'ing and returning.
    --------------------------------------------------------------------------------
    -- Sets up our stack frame properly:
    compileFuncPrelude: () =>
        {:stackTop} = @ljContext

        -- The stack has a special guarantee 'everything outside is zero initialized'.
        -- We thus hack GGGGC to allow for zero pointers and achieve convenience.
        -- The only remaining thing is to clear up stack space on any return site by nil'ing it
        -- to retain this invariant.
        @stackTopPtr = @longConst(stackTop)
        stackTopVal = @loadRelative(@stackTopPtr, 0, lj.ptr)
        @argsNVal = @getParam(0)
        @stackFrameVal = @sub stackTopVal, @mul(@argsNVal, @longConst VAL_SIZE)

        -- How much total varSpace we want:
        varSpace = @longConst(@stackPtrsUsed * VAL_SIZE)
        @stackTopVal = @add(@stackFrameVal, varSpace)
        @storeRelative(@stackTopPtr, 0, @stackTopVal)

    -- Compiles the necessary cleanup for returning:
    compileFuncReturn: (values) =>
        numRet = #values
        numRetVal = @longConst numRet
        retSpace = @longConst numRet * VAL_SIZE

        nullVal = @longConst(0)
        @storeRelative(@stackTopPtr, 0, @add(@stackFrameVal, retSpace))
        for i=numRet,@stackPtrsUsed-1
            @stackStore(i, nullVal)
        @_return(numRetVal)
}

--------------------------------------------------------------------------------
-- The exported module
--------------------------------------------------------------------------------

return {:FunctionBuilder, :LangValue}

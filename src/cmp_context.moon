--------------------------------------------------------------------------------
-- Imports
--------------------------------------------------------------------------------
lj = require "libjit"

librun = require "libruntime"
ffi = require "ffi"

fcast = ffi.cast
fnew = ffi.new

import VAL_SIZE 
    from require "cmp_constants"

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

PSTACKSIZE = VAL_SIZE*1024^2

makeContext = () ->
    con = lj.Context()
    con.initialized = true
    log "makeContext(): makeContext has ran."
    return con

--------------------------------------------------------------------------------
-- Wraps LibJIT Context
--------------------------------------------------------------------------------

LangContext = newtype {
    parent: lj.Context
    init: () =>
        lj.Context.init(@)
        @globals = fnew("struct LangGlobals[1]")
        librun.langGlobalsInit(@globals, PSTACKSIZE)
        {:types, :pstackTop, :pstack} = @globals[0]
        {:boxType, :stringType} = types
        @boxTypeDesc = boxType
        @stringTypeDesc = stringType
        @stack = pstack
        @stackTop = pstackTop
        @stringPtrs = {} -- Cache of string constants. TODO find time to free this.

    -- Creates a managed pointer to a string constant:
    getStringPtr: (str) =>
        lStr = @stringPtrs[str] 
        if lStr then return lStr
        lStr = librun.langStringCopy(str, #str)
        ptr = librun.langCreatePointer()
        ptr[0] = lStr
        @stringPtrs[str] = ptr
        return ptr

    -- Creates a new inline cache object:
    getNewInlineCache: () =>
        ptr = librun.langCreatePointer()
        ptr[0] = librun.langInlineCacheNew()
        return ptr
}

return {:LangContext}

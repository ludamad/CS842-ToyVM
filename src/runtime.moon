ffi = require "ffi"
lj = require "libjit"
librun = require "libruntime"
gc = require "ggggc"

ffi.cdef [[
    typedef struct {
        int tag, val;
    } LangValue;
    typedef unsigned int (*LangFunc)(unsigned int n);
]]

lcast = (v) -> ffi.cast 'uint64_t', v
local C 
makeGlobalScope = (ljContext) ->
    C or= require "compiler"
    scope = C.Scope()

    -- Runtime functions.
    -- LuaJIT 'converts' these to C pointers callable by libjit, what a dear ...
    funcs = {
        print: (n) ->
           {:pstack, :pstackTop} = ljContext.globals[0]
           args = ffi.cast("LangValue*",pstackTop[0]) - n
           for i=0,tonumber(n)-1
              if i >= 1 
                  io.write '\t'
              if args[i].tag == 1
                  -- Assumg integer!
                  io.write(args[i].val)
              else -- Assume string!
                  asString = ffi.cast("void**", args + i)[0]
                  librun.langStringPrint(asString)
           io.write('\n')
           return ffi.new("uint64_t", 0)
    }

    -- Wrap as runtime funcs:
    for k,v in pairs(funcs)
        funcs[k] = lj.NativeFunction(ffi.cast("LangFunc", v), lj.ulong, {lj.ptr, lj.uint})

    for k,v in pairs(funcs)
        scope\declare(C.Constant(k, v))
    return scope

gcMalloc = lj.NativeFunction(gc.ggggc_malloc, lj.ptr, {lj.ptr})
gcMallocPointerArray = lj.NativeFunction(gc.ggggc_mallocPointerArray, lj.ptr, {})
gcMallocDataArray = lj.NativeFunction(gc.ggggc_mallocDataArray, lj.ptr, {})

stringConcat = lj.NativeFunction(librun.langStringConcat, lj.ptr, {lj.ptr, lj.ptr})
return {:makeGlobalScope, :gcMalloc, :gcMallocPointerArray, :gcMallocDataArray, :stringConcat}


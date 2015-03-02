ffi = require "ffi"
lj = require "libjit"
librun = require "libruntime"
gc = require "ggggc"

ffi.cdef [[
    typedef struct {
        int val, tag;
    } LangValue;
    typedef uint64_t (*LangFunc)(LangValue* args, unsigned int n);
]]

-- Runtime functions.
-- LuaJIT 'converts' these to C pointers callable by libjit, what a dear ...
funcs = {
    print: (args, n) ->
       for i=0,tonumber(n)-1
          if i >= 1 
              io.write '\t'
          assert(args[i].tag == 1)
          io.write(args[i].val)
       io.write('\n')
       return ffi.new("uint64_t", 0)
}

-- Wrap as runtime funcs:
for k,v in pairs(funcs)
    funcs[k] = lj.NativeFunction(ffi.cast("LangFunc", v), lj.ulong, {lj.ptr, lj.uint})
    --funcs[k] = lj.NativeFunction(librun.RUNTIME_print, lj.ulong, {lj.ptr, lj.uint})

local C 
makeGlobalScope = () ->
    C or= require "compiler"
    scope = C.Scope()
    for k,v in pairs(funcs)
        scope\declare with C.Variable(k)
            \makeConstant(v)
    return scope

gcMalloc = lj.NativeFunction(gc.ggggc_malloc, lj.ptr, {lj.ptr})

return {:makeGlobalScope, :gcMalloc}


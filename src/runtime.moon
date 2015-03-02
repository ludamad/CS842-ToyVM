ffi = require "ffi"
lj = require "libjit"
C = require "compiler"
librun = require "libruntime"
gc = require "ggggc"

-- Runtime functions.
-- LuaJIT 'converts' these to C pointers callable by libjit, what a dear ...
funcs = {
    print: (args, n) ->
       for i=0,tonumber(n)-1
          if i >= 1 
              io.write '\t'
          assert(args[i].tag == 1)
          io.write(args[i].val)
       return ffi.new("uint64_t", 0)
}

-- Wrap as runtime funcs:
for k,v in pairs(funcs)
    funcs[k] = lj.NativeFunction(ffi.cast("LangRuntimeFunc", v), lj.ulong, {lj.ptr, lj.uint})
    --funcs[k] = lj.NativeFunction(librun.RUNTIME_print, lj.ulong, {lj.ptr, lj.uint})

makeGlobalScope = () ->
    scope = C.Scope()
    for k,v in pairs(funcs)
        scope\declare with C.Variable(k)
            \makeConstant(v)
    return scope

allocateDescriptor = lj.NativeFunction(gc.ggggc_allocateDescriptor, lj.ptr, {lj.ptr})
malloc = lj.NativeFunction(gc.ggggc_malloc, lj.ptr, {lj.ptr})

return {:makeGlobalScope, :malloc, :allocateDescriptor}


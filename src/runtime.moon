ffi = require "ffi"
lj = require "libjit"
C = require "compiler"

-- Runtime functions.
-- LuaJIT 'converts' these to C pointers callable by libjit, what a dear ...
funcs = {
    print: (args, n) ->
        for i=1,n
            io.write(args[i-1], ' ')
}
for k,v in pairs(funcs)
    funcs[k] = lj.NativeFunction(ffi.cast("LangRuntimeFunc", v), lj.ulong, {lj.ptr, lj.ulong})

makeGlobalScope = () ->
    scope = C.Scope()
    for k,v in pairs(funcs)
        scope\declare with C.Variable(k)
            \makeConstant(v)
    return scope

return {:makeGlobalScope}


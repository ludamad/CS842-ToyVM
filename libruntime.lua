local ffi = require "ffi"
local runtime = ffi.load("./libruntime.so")

ffi.cdef [[
    uint64_t RUNTIME_print(uint64_t* args, unsigned int n);  
]]

return runtime

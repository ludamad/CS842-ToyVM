-- compiler.moon describes a partial class. 
-- This provides an interface for the necessary fiddly bits for garbage collection.

ffi = require "ffi"
runtime = require "runtime"
gc = require "ggggc"
Cggggc = require "compiler_ggggc"

lj = require "libjit"

M = {} -- Module

VAL_SIZE = 8 -- TODO add some constants file


M.setupContext = (c) ->
    -- Malloc enough for the root pointer:
    c.gcRoot = gc.ggggc_mallocPointerArray(8)
    



-- Works with the rest of FunctionBuilder's methods in compiler.moon
M.functionBuilderGGGCMethods = {
    -- Allocates a gc-managed pointer to pure data
    __rawAllocData: (n, membSize) =>
        return @call(runtime.gcMallocDataArray, 'mallocDA', {n, membSize})
    -- Allocates a gc-managed pointer to an array of pointers
    __rawAllocPtrs: (n) =>
        return @call(runtime.gcMallocPointerArray, 'mallocPA', {n * VAL_SIZE})
    allocData: (n, membsize) =>
}

return M

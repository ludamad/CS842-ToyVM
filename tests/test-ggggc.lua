local ffi = require "ffi"
local gc = require "ggggc"

-- Let's make a list, with a data element and 2 pointer elements
local SIZEOF_PTR = 8
local SIZEOF_INT = 4
local desc = gc.ggggc_allocateDescriptor(SIZEOF_PTR * 2 + SIZEOF_INT, 2)
desc.pointers[0] = 0
desc.pointers[1] = SIZEOF_PTR
local data_chunk = gc.ggggc_malloc(desc)
local int_view = ffi.cast("int*", data_chunk) + (2 * SIZEOF_PTR) / SIZEOF_INT
local ptr_view = ffi.cast("void**", data_chunk)
int_view[0] = 42
ptr_view[0] = data_chunk
ptr_view[1] = data_chunk


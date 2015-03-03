
ffi = require "ffi"

ffi.cdef "
    struct Value {
        int bot, top;
    };
"

-- The AST gets associated with a type info object:

TYPE_UNKNOWN = 0
TYPE_POLY = 1
TYPE_INT = 2
TYPE_DBL = 3
TYPE_STRING = 4
TYPE_SHAPE = 5 -- Shape given

makeTypeInfo = () ->
    return {type: TYPE_UNKNOWN, shape: false}

values.ArithmeticOp = (op, val1, val2) ->
    return {"(", val1, op, val2, ")"}

statements = {}

return {:values, :statements, :TYPE_UNKNOWN, :TYPE_POLY, :TYPE_INT, :TYPE_DBL, :TYPE_STRING, :TYPE_SHAPE}

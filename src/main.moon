require "util"

lj = require "libjit"
ffi = require "ffi"
C = require "compiler"
import parse, astToString from require "parser"

ljContext = lj.Context()

ast = parse "
    print(3)
"

print(astToString ast)
scope = C.Scope()

-- Runtime functions.
-- LuaJIT 'converts' these to C pointers callable by libjit, what a dear ...
runtimePrintValue = ffi.cast "LangRuntimeFunc1", (val) -> 
    print(val.parts[0], val.parts[1])
    return ffi.new("LangValue")


scope\declare with C.Variable("print")
    \makeConstant lj.NativeFunction(runtimePrintValue, lj.ulong, {lj.ulong})

funcContext = C.FunctionBuilder(ljContext, {C.Param "a", C.Param "b"}, scope)
funcContext\compileAst(ast)

funcContext\callFromLua {
        ffi.new("uint64_t[1]", 42), ffi.new("uint64_t[1]")
    },
    ffi.new("uint64_t")

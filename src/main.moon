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
scope = require("runtime").makeGlobalScope()

funcContext = C.FunctionBuilder(ljContext, {C.Param "a", C.Param "b"}, scope)
funcContext\compileAst(ast)
funcContext\callFromLua {ffi.new("uint64_t[1]", 42), ffi.new("uint64_t[1]")}, ffi.new("uint64_t[1]")
funcContext\free()

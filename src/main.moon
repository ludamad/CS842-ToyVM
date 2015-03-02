require "util"

lj = require "libjit"
ffi = require "ffi"
C = require "compiler"
import parse, astToString from require "parser"

ljContext = lj.Context()

globalScope = require("runtime").makeGlobalScope()
compile = (str, dump = false) ->
    ast = parse(str)
    funcContext = C.FunctionBuilder(ljContext, {C.Param "a", C.Param "b"}, globalScope)
    funcContext\compileIR(ast)
    if dump
        print('-AST--------------------------------------------------')
        print(astToString ast)
        print('-LibJIT IR--------------------------------------------')
        print(funcContext\dump())
    funcContext\compileAsm()
    return funcContext

f = compile "print(3)"
f()


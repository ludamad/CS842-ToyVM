if tonumber(os.getenv('V') or '0') >= 3
    req = require
    _G.require = (...) ->
        print('require', ...)
        req ...
require "util"

lj = require "libjit"
ffi = require "ffi"
C = require "compiler"
import parse, astToString from require "parser"

log "Creating context: "
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

log "Compiling function: "
f = compile "print('Hello World!')", true
f()


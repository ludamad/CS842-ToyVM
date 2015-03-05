if tonumber(os.getenv('V') or '0') >= 3
    req = require
    _G.require = (...) ->
        print('require', ...)
        req ...
require "util"

lj = require "libjit"
ffi = require "ffi"
C = require "compiler"
import Param from require "compiler_syms"
import parse, astToString from require "parser"

log "Creating context: "
ljContext = lj.Context()

globalScope = require("runtime").makeGlobalScope()
compile = (str, dump = false) ->
    ast = parse(str)
    pretty(ast)
    os.exit()
    print('-AST--------------------------------------------------')
    for astN in *ast
        print(astToString astN)
    funcContext = C.FunctionBuilder(ljContext, {Param "a", Param "b"}, globalScope)
    funcContext\compileIR(ast)
    print('-LibJIT IR--------------------------------------------')
    print(funcContext\dump())
    funcContext\compileAsm()
    return funcContext

log "Compiling function: "

program = "print('The answer is ', 42)"
f = compile(program, true)
f()


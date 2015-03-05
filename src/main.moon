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
    for i=1,#ast
        pretty(ast[i])
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

program = "
i = 10
while i > 0
    print('The answer is ', i)
    i -= 1
i = 0
"
f = compile(program, true)
f()


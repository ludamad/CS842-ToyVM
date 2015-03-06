--------------------------------------------------------------------------------
-- Verbose require
--------------------------------------------------------------------------------
if tonumber(os.getenv('V') or '0') >= 3
    req = require
    _G.require = (...) ->
        print('require', ...)
        req ...
--------------------------------------------------------------------------------
-- Imports
--------------------------------------------------------------------------------
require "util"

lj = require "libjit"
ffi = require "ffi"
C = require "compiler"
NC = require "newcompiler"

import Param from require "compiler_syms"
import parse, astToString from require "parser"
--------------------------------------------------------------------------------
-- Runtime initialization
--------------------------------------------------------------------------------
log "Creating context: "
ljContext = lj.Context()

globalScope = require("runtime").makeGlobalScope()

--compile = (str, dump = false) ->
--    ast = parse(str)
--    for i=1,#ast
--        pretty(ast[i])
--    os.exit()
--    print('-AST--------------------------------------------------')
--    for astN in *ast
--        print(astToString astN)
--    funcContext = C.FunctionBuilder(ljContext, {Param "a", Param "b"}, globalScope)
--    funcContext\compileIR(ast)
--    print('-LibJIT IR--------------------------------------------')
--    print(funcContext\dump())
--    funcContext\compileAsm()
--    return funcContext

log "Compiling function: "

compile = (str) ->
    ast = parse(str)
    fb = NC.FunctionBuilder(ljContext, {}, globalScope)
    print 'FRESH'
    print ast
    ast\symbolResolve(fb)
    print 'SYMBOLIZED'
    print ast
    ast\stackResolve(fb)
    print 'STACK ALLOC\'ED'
    print ast
    ast\compile(fb)
    
    -----
    print 'IR Compiled--------------------------------------------------------------------------------'
    fb\dump()
    print 'ASM Compiled--------------------------------------------------------------------------------'
    fb\compile()
    fb\dump()

program = "
a = 1
b = a / 2
"
compile(program, true)



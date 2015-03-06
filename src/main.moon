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

import parse, astToString from require "parser"
--------------------------------------------------------------------------------
-- Runtime initialization
--------------------------------------------------------------------------------
log "Creating context: "
ljContext = lj.Context()

globalScope = require("runtime").makeGlobalScope()

log "Compiling function: "

compile = (str) ->
    ast = parse(str)
    fb = C.FunctionBuilder(ljContext, {}, globalScope)
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
    --print 'ASM Compiled--------------------------------------------------------------------------------'
    fb\compile()
    --fb\dump()
    f = fb\toCFunction()
    print "CALLINGFUNC:", f(0)

program = "
a = 1
"
compile(program, true)



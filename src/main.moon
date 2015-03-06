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

globalScope = require("runtime").makeGlobalScope(ljContext)

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
    fb\smartDump()
    --print 'ASM Compiled--------------------------------------------------------------------------------'
    fb\compile()
    --print fb\dump()
    f = fb\toCFunction()
    f(0)
--   print "CALLINGFUNC:", f(0)


program = "
i = 1
s = ''
while i < 10
    print(i)
    s ..= 'test'
    i += 1
    while i < 10
        print(2)
print(s)
"
compile(program, true)



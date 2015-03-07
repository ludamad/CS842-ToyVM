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
librun = require "libruntime"
C = require "compiler"

import parse, astToString from require "parser"
--------------------------------------------------------------------------------
-- Runtime initialization
--------------------------------------------------------------------------------
log "Creating context: "

makeContext = () ->
    con = lj.Context()
    log "mmap funkiness ahead."
    PSTACKSIZE = C.VAL_SIZE*1024^2
    con.globals = ffi.new("struct LangGlobals[1]")
    con.initialized = true
    librun.langGlobalsInit(con.globals, PSTACKSIZE)
    log "makeContext has ran."
    return con

ljContext = makeContext()
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

test = () ->
    

i = 0
while i < 10
    print('i = ' .. tostring(i))
    i += 1
"
compile(program, true)



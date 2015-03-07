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
    col = require "system.AnsiColors"
    out = (s) -> print col.WHITE(s,col.FAINT)
    out '-- Parse Tree --------------------------------------------------------------------------------'
    print ast
    ast\symbolResolve(fb)
    out '-- Symbolized Tree ---------------------------------------------------------------------------'
    print ast
    ast\stackResolve(fb)
    out '-- Stack Allocated Tree ----------------------------------------------------------------------'
    print ast
    out '----------------------------------------------------------------------------------------------'
    ast\compile(fb)
    -----
    out '-- IR Compiled -------------------------------------------------------------------------------'
    fb\smartDump()
    --print 'ASM Compiled--------------------------------------------------------------------------------'
    fb\compile()
    --print fb\dump()
    f = fb\toCFunction()
    f(0)
--   print "CALLINGFUNC:", f(0)


program = "
printWithSglQuotes = (v) ->
    print(\"'\" .. tostring(v) .. \"'\")
printWithDblQuotes = (v) ->
    print('\"' .. tostring(v) .. '\"')
printN = (n, printer) ->
    i = 0
    while i < n
        printer(i)
        i += 1
printN(10, printWithSglQuotes)
printN(10, printWithDblQuotes)
"

compile(program, true)
do return
program = "
j = 2
k = 3 
i = 1
i = i + 1
i = i + i
print(i, j + k)
"

compile(program, true)
do return
program = "
print(2)
s = () ->
    print('hello from function')
b = 2
print()
"

compile(program, true)
program2 = "
i = 1
while i < 10
    i += 1
    print(i)
print('what')
"

compile(program2, true)

--------------------------------------------------------------------------------
-- Imports
--------------------------------------------------------------------------------
require "util"

lj = require "libjit"
ffi = require "ffi"
librun = require "libruntime"
rt = require "runtime"
C = require "compiler"
P = require "parser"
ansiCol = require "system.AnsiColors"
--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

PSTACKSIZE = C.VAL_SIZE*1024^2

--------------------------------------------------------------------------------
-- Runtime initialization
--------------------------------------------------------------------------------

makeContext = () ->
    con = lj.Context()
    con.globals = ffi.new("struct LangGlobals[1]")
    con.initialized = true
    librun.langGlobalsInit(con.globals, PSTACKSIZE)
    log "makeContext(): makeContext has ran."
    return con

ljContext = makeContext()
globalScope = rt.makeGlobalScope(ljContext)

grayPrint  = (s) -> print ansiCol.WHITE(s,ansiCol.FAINT)
compileString = (str) ->
    ast = P.parse(str)
    fb = C.compileFunc(ljContext, {}, ast, globalScope)
    cFunc = fb\toCFunction()
    grayPrint '-- Stack Allocated Tree ----------------------------------------------------------------------'
    print(ast)
    grayPrint '-- Running -----------------------------------------------------------------------------------'
    return () -> cFunc(0)

compileFile = (fileName) ->
    file = io.open(fileName, "r")
    contents = file\read("*all")
    return compileString(contents)

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

main = () ->
    fileName = _ARGS[1]
    if not fileName
        print "No fileName given!"
        return 
    f = compileFile(fileName)
    f()

main()


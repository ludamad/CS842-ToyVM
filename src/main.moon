--------------------------------------------------------------------------------
-- Imports
--------------------------------------------------------------------------------
require "util"

lj = require "libjit"
ffi = require "ffi"
librun = require "libruntime"
rt = require "runtime"
ansiCol = require "system.AnsiColors"
import LangContext, compileFuncBody, parse from require "cmp"

math.randomseed(os.time())

--------------------------------------------------------------------------------
-- Runtime initialization
--------------------------------------------------------------------------------

grayPrint  = (s) -> print ansiCol.WHITE(s,ansiCol.FAINT)
compileString = (str) ->
    ast = parse(str)
    fb = compileFuncBody({}, ast)
    cFunc = fb\toCFunction()
    if os.getenv("SHOW_AST")
        grayPrint '-- Stack Allocated Tree ----------------------------------------------------------------------'
        print(ast)
        grayPrint '-- Running -----------------------------------------------------------------------------------'
    -- print fb\smartDump()
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


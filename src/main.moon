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

--------------------------------------------------------------------------------
-- Runtime initialization
--------------------------------------------------------------------------------

grayPrint  = (s) -> print ansiCol.WHITE(s,ansiCol.FAINT)
compileString = (str) ->
    ast = parse(str)
    grayPrint '-- Bare Parse Tree ---------------------------------------------------------------------------'
    fb = compileFuncBody({}, ast)
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


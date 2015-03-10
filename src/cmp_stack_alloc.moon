--------------------------------------------------------------------------------
-- Imports
--------------------------------------------------------------------------------

ast = require "ast"
ffi = require "ffi"
runtime = require "runtime"
librun = require 'libruntime'
gc = require "ggggc"

lj = require "libjit"

col = require "system.AnsiColors"

import INT_SIZE, VAL_SIZE, TYPE_TAG_BOOL, TYPE_TAG_INT
    from require "cmp_constants"

import FunctionBuilder
    from require "cmp_func_builder"

--------------------------------------------------------------------------------
-- Second pass of compilation:
--  - Resolve stack locations
--------------------------------------------------------------------------------

ast.installOperation {
    methodName: "stackResolve"
    recurseName: "_stackRecurse"
    default: (f) =>
        f\saveStackLoc()
        @_stackRecurse(f)
        f\loadStackLoc()
    Function: (f) => 
        -- Do nothing with the AST (belongs to different context)
        if @dest
            @dest\resolve(f)
    FuncCall: (f) =>
        @lastStackLoc = f.stackLoc
        f\saveStackLoc()
        @_stackRecurse(f)
        f\loadStackLoc()
        if @dest
            @dest\resolve(f)
    Expr: (f) =>
        f\saveStackLoc()
        @_stackRecurse(f)
        f\loadStackLoc()
        if @dest
            @dest\resolve(f)
}


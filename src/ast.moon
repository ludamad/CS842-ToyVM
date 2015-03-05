ffi = require "ffi"
runtime = require "runtime"
librun = require 'libruntime'
gc = require "ggggc"
Cggggc = require "compiler_ggggc"

lj = require "libjit"

import Variable, Param from require "compiler_syms"

import Any, List, checkedType, checkerType, String from require "typecheck"

M = {} -- Module
--------------------------------------------------------------------------------
-- Constructors for making checked AST Ts
--------------------------------------------------------------------------------
toName = (T) ->
    for k,v in pairs(M)
        if v == T
            return k
    return "(?)"
__INDENT = 1
NodeT = (t) ->
    t.__node = true
    T = checkedType(t)
    T.toString = () =>
        __INDENT = 1
        return tostring(@)
    T.__tostring = () =>
        indentStr = ''
        lines = {toName(T.create)}
        for i=1,__INDENT do indentStr ..= '  '
        __INDENT += 1
        for i=1,#t
            val = @[t[i].name]
            if type(val) == "string" 
                val = "'#{val}'"
            elseif #val > 0
                __INDENT +=1 
                strs = ["#{indentStr}  - #{s}" for s in *val]
                __INDENT -=1 
                val = '\n' .. table.concat(strs, '\n')
            else
                val = pretty_tostring(val)
            append lines, "#{indentStr}#{t[i].name}: #{val}"
        __INDENT -= 1
        return table.concat(lines, '\n')
    return T.create -- Keep as function, less callback indirection

ExprT = (t) ->
    t.__expr = true
    return NodeT(t)

AssignableExprT = (t) ->
    t.__assignable_expr == true
    return NodeT(t)

StatementT = (t) ->
    t.__statement = true
    return NodeT(t)
PolyT = (t) ->
    t.__expr = true
    t.__statement = true
    return NodeT(t)
--------------------------------------------------------------------------------
-- Constructors for declaring checked AST fields
--------------------------------------------------------------------------------
Expr = checkerType {
    emitCheck: (code) =>
        --append code, "assert(#{@name}.__expr)"
}
AssignableExpr = checkerType {
    emitCheck: (code) =>
        append code, "assert(#{@name}.__assignable_expr)"
}
Statement = checkerType {
    emitCheck: (code) => 
        append code, "assert(#{@name}.__statement)"
}

--------------------------------------------------------------------------------
-- The AST types
--------------------------------------------------------------------------------
M.Ref = AssignableExprT {
    String.value
}

M.Operator = ExprT {
    (List AssignableExpr).vars
    (List Expr).values
}

M.FloatLit = ExprT {
    String.value
}

M.StringLit = ExprT {
    String.value
}

M.ObjectLit = ExprT {
    String.value
}

M.IntLit = ExprT {
    String.value
}

M.Declare = StatementT {
    List(AssignableExpr).vars
    List(Expr).values
}

M.While = StatementT {
    List(AssignableExpr).vars
    List(Expr).values
}

M.Assign = StatementT {
    List(AssignableExpr).vars
    List(Expr).values
}

M.FuncCall = PolyT {
    Expr.func
    --Any.args
    List(Expr).args
    test: () => print "WEEE"
}

return M

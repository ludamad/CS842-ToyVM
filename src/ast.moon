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

toCommas = (args) ->
    strs = ["#{val}" for val in *args]
    return table.concat(strs, ', ')

__INDENT = 1
NodeT = (t) ->
    t._node = true
    t._expr or= false
    t._assignable or= false
    t._statement or= false
    t.__init or= () =>
    local T
    t.__tostring or= () =>
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
    T = checkedType(t)
    T.toString = () =>
        __INDENT = 1
        return tostring(@)
    return T.create -- Keep as function, less callback indirection

ExprT = (t) ->
    t._expr = true
    return NodeT(t)

AssignableT = (t) ->
    t._assignable = true
    return NodeT(t)

StatementT = (t) ->
    t._statement = true
    return NodeT(t)
PolyT = (t) ->
    t._expr = true
    t._statement = true
    return NodeT(t)

M.typeSwitch = (val, table) =>
    if val._expr and table.Expr
        return table.Expr(val
    elseif val._statement and table.Statement
        return table.Statement(val))
    elseif val._assignable and table.Assignable
        return table.Assignable(val)
    elseif val._node and table.Node
        return table.Node(val)
    elseif val._list and table.List
        return table.List(val)

--------------------------------------------------------------------------------
-- Constructors for declaring checked AST fields
--------------------------------------------------------------------------------
Expr = checkerType {
    emitCheck: (code) =>
        append code, @assert("#{@name}._expr")
}
Assignable = checkerType {
    emitCheck: (code) =>
        append code, @assert("#{@name}._assignable")
}
Statement = checkerType {
    emitCheck: (code) => 
        append code, @assert("#{@name}._statement")
}

--------------------------------------------------------------------------------
-- The AST types
--------------------------------------------------------------------------------
M.astTypes = {}
A = M.astTypes
A.RefStore = AssignableT {
    String.name
    __tostring: () =>
        return "$#{@name}"
}
A.RefLoad = ExprT {
    String.name
    __tostring: () =>
        return "$#{@name}"
}

A.Operator = ExprT {
    Expr.left
    String.op
    Expr.right
    __tostring: () =>
        return "#{@left} #{@op} #{@right}"
}

A.FloatLit = ExprT {
    String.value
    __tostring: () =>
        return @value
}

A.StringLit = ExprT {
    String.value
    __tostring: () =>
        return "\"#{@value}\""
}

A.ObjectLit = ExprT {
    String.value
}

A.IntLit = ExprT {
    String.value
    __tostring: () =>
        return @value
}

A.Declare = StatementT {
    List(Assignable).vars
    List(Expr).values
}

A.While = StatementT {
    Expr.condition
    List(Statement).block
}

A.Assign = StatementT {
    List(Assignable).vars
    String.op
    List(Expr).values
    __tostring: () =>
        return "#{toCommas @vars} #{@op} #{toCommas @values}"
}

A.FuncCall = PolyT {
    Expr.func
    List(Expr).args
    test: () => print "WEEE"
    __tostring: () =>
        return "#{@func}(#{toCommas @args})"
}

_installOperation = (criterion) -> (funcs) ->
    name = funcs.methodName
    for k, v in pairs A
        if not criterion or T[criterion]
            if funcs[k]
                A[name] = k
            elseif funcs.default
                A[name] = funcs.default

-- Code planting API:
M.installNodeOperation       = _installOperation('_node')
M.installExprOperation       = _installOperation('_expr')
M.installAssignableOperation = _installOperation('_assignable')
M.installStatementOperation  = _installOperation('_statement')

-- Copy over AST nodes into main exported module
for k,v in pairs A
    M[k] = v

return M

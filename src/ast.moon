ffi = require "ffi"
runtime = require "runtime"
librun = require 'libruntime'
gc = require "ggggc"
Cggggc = require "compiler_ggggc"

lj = require "libjit"

import Any, List, checkedType, checkerType, defaultInit, String from require "typecheck"

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
    t._fields = [field for field in *t] 
    t.init or= () =>
    local T
    t._indent = () =>
        indentStr = ''
        for i=1,__INDENT do indentStr ..= '  '
        return indentStr

    t.__tostring or= () =>
        indent = @_indent()
        lines = {toName(T.create)}
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
    return T

ExprT = (t) ->
    t._expr = true
    t.init or= () =>
        @dest = false
    return NodeT(t)

AssignableT = (t) ->
    t._assignable = true
    return NodeT(t)

StatementT = (t) ->
    t._statement = true
    return NodeT(t)
PolyT = (t) ->
    t._statement = true
    return ExprT(t)

M.typeSwitch = (val, table) =>
    if val._expr and table.Expr
        return table.Expr(val)
    elseif val._statement and table.Statement
        return table.Statement(val)
    elseif val._assignable and table.Assignable
        return table.Assignable(val)
    elseif val._node and table.Node
        return table.Node(val)
    elseif val._list and table.List
        return table.List(val)

nodeCheckerInit = () =>
    defaultInit(@)
    @_expr = false
    @_node = true
    @_assignable = false
--------------------------------------------------------------------------------
-- Constructors for declaring checked AST fields
--------------------------------------------------------------------------------
Expr = checkerType {
    init: (@name) =>
        nodeCheckerInit(@)
        @_expr =true
    emitCheck: (code) =>
        append code, @assert("#{@name}._expr")
}
Assignable = checkerType {
    init: (@name) =>
        nodeCheckerInit(@)
        @_assignable = true
    emitCheck: (code) =>
        append code, @assert("#{@name}._assignable")
}
Statement = checkerType {
    init: (@name) =>
       nodeCheckerInit(@)
       @_statement = true
    emitCheck: (code) => 
        append code, @assert("#{@name}._statement")
}

--------------------------------------------------------------------------------
-- The AST types
--------------------------------------------------------------------------------
M.astTypes = {}
A = M.astTypes

A.FuncBody = StatementT {
    List(Statement).body
    __tostring: () =>
        __INDENT += 1
        f = "func()\n" .. table.concat(["#{v}" for v in *@body], '\n') .. "\nend"
        __INDENT -= 1
        return f
}

A.RefStore = AssignableT {
    String.name
    init: () =>
        @symbol = false
    toExpr: () =>
        return A.RefLoad @name
    __tostring: () =>
        if @symbol
            return tostring(@symbol)
        return "$#{@name}"
}
A.RefLoad = ExprT {
    String.name
    init: () =>
        @symbol = false
        @dest = false
    __tostring: () =>
        if @symbol
            return tostring(@symbol)
        return "$#{@name}"
}

A.Operator = ExprT {
    Expr.left
    String.op
    Expr.right
    __tostring: () =>
        return "(#{@left} #{@op} #{@right})"
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
    init: () =>
        assert(#@vars == #@values)
    __tostring: () =>
        return "#{@_indent()}#{toCommas @vars} #{@op} #{toCommas @values}"
}

A.FuncCall = PolyT {
    Expr.func
    List(Expr).args
    test: () => print "WEEE"
    __tostring: () =>
        return "#{@_indent()}#{@func}(#{toCommas @args})"
}

_codegenRecursor = (criterion = '_node', T, methodName) ->
    code = {"return function(self,f)"}
    for f in *T._fields
        if f._list
            append code, "for i=1,# self.#{f.name} do"
            append code, "    self.#{f.name}[i]:#{methodName}(f)"
            append code, "end"
        elseif rawget(f, criterion)
            append code, "self.#{f.name}:#{methodName}(f)"
    append code, "end"
    codeString = table.concat(code, "\n")
    --print "-------------------#{methodName}------------------"
    --print codeString
    --print "END-------------------#{methodName}------------------"
    func, err = loadstring(codeString)
    if func == nil
        error(err)
    return func()

_installRecursor = (criterion, recursorName, methodName) ->
    for tname, T in pairs A
        if not criterion or T[criterion]
            T[recursorName] = _codegenRecursor(criterion, T, methodName)

_installOperation = (criterion) -> (funcs) ->
    {:methodName} = funcs
    if funcs.recurseName
        _installRecursor(criterion, funcs.recurseName, methodName)
    for tname, T in pairs A
        if not criterion or T[criterion]
            f = funcs[tname]
            if T._expr
                f or= funcs.Expr
            if T._statement
                f or= funcs.Statement
            if T._assignable
                f or= funcs.Assignable
            f or= funcs.default
            T[methodName] = f


-- Code planting API:
M.installOperation       = _installOperation(nil)
M.installExprOperation       = _installOperation('_expr')
M.installAssignableOperation = _installOperation('_assignable')
M.installStatementOperation  = _installOperation('_statement')

-- Copy over AST nodes into main exported module
for tname, T in pairs A
    M[tname] = T.create
    -- Ensure expression nodes show their 'dest' values
    if T._expr 
        oldTS = T.__tostring
        T.__tostring = () =>
            if @dest
                return "#{oldTS @}->#{@dest}"
            return oldTS(@)

return M

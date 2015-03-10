ffi = require "ffi"
runtime = require "runtime"
librun = require 'libruntime'
gc = require "ggggc"

lj = require "libjit"

import Bool, String, Num, Any, List, checkedType, checkerType, defaultInit from require "typecheck"

M = {} -- Module
M.astTypes = {}
A = M.astTypes

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
        @initialized = true
    local T
    t._indent = (d=0) =>
        indentStr = ''
        for i=1,__INDENT+d do indentStr ..= '  '
        return indentStr

    t.__tostring or= () =>
        indent = @_indent()
        lines = {toName(T.create)}
        indentStr = @_indent()
        __INDENT += 1
        for i=1,#t
            val = @[t[i].name]
            if type(val) == "string" 
                val = "'#{val}'"
            elseif type(val) == "table" and #val > 0
                __INDENT +=1 
                strs = ["#{indentStr}  - #{s}" for s in *val]
                __INDENT -=1 
                val = '\n' .. table.concat(strs, '\n')
            else
                val = pretty_tostring(val)
            append lines, "#{indentStr}#{t[i].name}: #{val}"

        __INDENT -= 1
        return table.concat(lines, '\n')
    T, methods = checkedType(t)
    T.toString = () =>
        __INDENT = 1
        return tostring(@)

    T.__newindex = (k,v) =>
        if v == nil 
            error "Cannot add '#{k}' nil member to #{toName T.create}!"
        if rawget @, 'initialized'
            error "Cannot add '#{k}' to initialized object! #{toName T.create}"
        rawset(@, k, v)

    getmetatable(methods).__index = (k) =>
        raw = rawget(@, k)
        if raw == nil
            error "No member '#{k}' in #{toName T.create}!"
        return raw
 
    return T

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
-- Top AST nodes for function definition:
--------------------------------------------------------------------------------

A.Function = ExprT {
    List(String).paramNames
    Statement.body
    Any.dest false
    Any.name false
    Any.compiledVal false
    Any.compiledFunc false
    _d: () => if @dest then @dest else ''
    __tostring: () =>
        code = {'('..table.concat(@paramNames, ", ")..")#{@_d()} ->"}
        __INDENT += 1
        append code, tostring(@body)
        __INDENT -= 1
        return table.concat(code,'\n')
}

A.FuncBody = StatementT {
    Statement.block
    __tostring: () =>
        __INDENT += 1
        f = table.concat(["#{@_indent()}#{v}" for v in *@block.body], '\n')
        __INDENT -= 1
        return f
}

--------------------------------------------------------------------------------
-- Assignable (and addressable) expressions:
--------------------------------------------------------------------------------

-- Store node for stack variables
A.RefStore = AssignableT {
    String.name
    Any.symbol false
    toExpr: () =>
        return A.RefLoad @name
    setUpForStore: (node) =>
        @symbol\link(node)
    generateStore: (fb, node) =>
        -- no op, we are a stack variable
    __tostring: () =>
        if @symbol
            return tostring(@symbol)
        return "$#{@name}"
}

A.BoxStore= AssignableT {
    Expr.ptr
    setUpForStore: (node) =>
    generateStore: (fb, node) =>
        assert @ptr.compiledVal, "Box value should be compiled!"
        assert node.compiledVal, "Node value should be compiled!"
        fb\boxStore(@ptr.compiledVal, node.compiledVal)

    toExpr: () =>
        return A.BoxLoad @ptr
    __tostring: () =>
        return "*#{@ptr}"
}

--------------------------------------------------------------------------------
-- Value expressions:
--------------------------------------------------------------------------------

A.RefLoad = ExprT {
    String.name
    Any.symbol false
    Any.dest false
    Any.compiledVal false
    __tostring: () =>
        if @symbol
            return tostring(@symbol)
        return "$#{@name}"
}

A.Operator = ExprT {
    Expr.left
    String.op
    Expr.right
    Any.dest false
    Any.compiledVal false
    __tostring: () =>
        return "(#{@left} #{@op} #{@right})"
}

A.FloatLit = ExprT {
    String.value
    Any.dest false
    Any.compiledVal false
    __tostring: () =>
        return @value
}

A.StringLit = ExprT {
    String.value
    Any.dest false
    Any.compiledVal false
    __tostring: () =>
        return "\"#{@value}\""
}

A.Object = ExprT {
    String.value
    Any.dest false
    Any.compiledVal false
}

A.IntLit = ExprT {
    String.value
    Any.dest false
    Any.compiledVal false
    __tostring: () =>
        return @value
}

-- Boxes are first class values used for mutability.
-- Box handlers:

A.BoxGet = ExprT {
    Assignable.ref
    Any.dest false
    Any.compiledVal false
    __tostring: () =>
        return "&#{@ref}"
}

A.BoxNew = ExprT {
    Expr.expr
    Any.dest false
    Any.compiledVal false
    __tostring: () =>
        return "new #{@expr}"
}

A.BoxLoad = ExprT {
    Expr.ptr
    Any.dest false
    Any.compiledVal false
    __tostring: () =>
        return "*#{@ptr}"
}

--------------------------------------------------------------------------------
-- Control statements and variable assignments:
--------------------------------------------------------------------------------

A.Declare = StatementT {
    List(Assignable).vars
    List(Expr).values
}

A.Block = StatementT {
    List(Statement).body
    __tostring: () =>
        __INDENT += 1
        f = '\n'..table.concat(["#{@_indent()}#{v}" for v in *@body], '\n')
        __INDENT -= 1
        return f
}

A.While = StatementT {
    Expr.condition
    Statement.block
    Any.labelCheck false
    Any.labelLoopStart false
    __tostring: () =>
        f = "\n#{@_indent()}while #{@condition}\n"
        __INDENT += 1
        f ..= table.concat(["#{@_indent()}#{v}" for v in *@block.body], '\n')
        __INDENT -= 1
        return f
}

A.If = StatementT {
    Expr.condition
    Statement.block
}

A.ForNum = StatementT {
    Assignable.var
    List(Expr).limits
    Statement.block
}

A.ForObj = StatementT {
    List(Assignable).vars
    List(Expr).vars
    Statement.block
}

A.Assign = StatementT {
    List(Assignable).vars
    String.op
    List(Expr).values
    init: () =>
        assert(#@vars == #@values)
    __tostring: () =>
        op = @op
        if op ~= '=' then op ..= '='
        return "#{toCommas @vars} #{op} #{toCommas @values}"
}

--------------------------------------------------------------------------------
-- Function calls, which can be both statements and values.
--------------------------------------------------------------------------------

A.FuncCall = PolyT {
    Expr.func
    List(Expr).args

    Num.lastStackLoc -1
    Bool.isExpression true
    Any.dest false
    Any.compiledVal false
    __tostring: () =>
        s = "#{@func}(#{toCommas @args})"
        if rawget(@, 'lastStackLoc')
            s ..= "#{@lastStackLoc}"
        return s
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
    if T._expr and T ~= A.Function
        oldTS = T.__tostring
        T.__tostring = () =>
            if @dest
                return "#{oldTS @}->#{@dest}"
            return oldTS(@)

return M

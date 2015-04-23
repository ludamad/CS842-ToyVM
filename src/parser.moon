require "util"
ast = require "ast"

lpeg = require "lpeg"
lpeg.setmaxstack(10000)

------------------------------------------------------------------------------
-- I found lpeg *too* terse.
-- Here is'longhand' for the library.
------------------------------------------------------------------------------

inject1 = (name) -> (val) -> {kind: name, value: val}
injectArr = (name) -> (...) -> {kind: name, value: {...}}

ToPattern = lpeg.P

MatchAnyOf = lpeg.S
MatchExact = lpeg.P
MatchGrammar = lpeg.P
MatchRange = lpeg.R
OneOrLess = (p) -> (ToPattern p)^-1
OneOrMore = (p) -> (ToPattern p)^1
TwoOrMore = (p) -> (ToPattern p)^2
ZeroOrMore = (p) -> (ToPattern p)^0
EndOfLine = -1
IgnoreCapture = (p) -> #(ToPattern p)
Capture = (p) -> lpeg.C(ToPattern p)
CaptureTable = (p) -> lpeg.Ct(ToPattern p)
Complement = (p) -> 1 - (ToPattern p)
Union = (...) ->
    parts = (if type(...) == "table" then (...) else {...})
    p = parts[1]
    for i=2,#parts do p += parts[i]
    return p
-- Variable for a grammar
Var = lpeg.V

------------------------------------------------------------------------------
-- Common parsing elements. Plagarized from Moonscript's parser.
------------------------------------------------------------------------------

_Space = ZeroOrMore MatchAnyOf " \t"
_NonBreakSpace = ZeroOrMore MatchAnyOf " \t"
Break = (OneOrLess "\r") * (MatchExact "\n")
Stop = Break + EndOfLine

Comment = (MatchExact "--") * (ZeroOrMore Complement MatchAnyOf "\r\n") * #Stop
Space = _Space * (OneOrLess Comment)
NonBreakSpace = _NonBreakSpace * (OneOrLess Comment)
SomeSpace = (OneOrMore MatchAnyOf " \t") * (OneOrLess Comment)
SpaceBreak = Space * Break
EmptyLine = SpaceBreak
AlphaNum = MatchRange("az", "AZ", "09", "__")
_Name = Capture (MatchRange "az", "AZ", "__")*(ZeroOrMore AlphaNum)
Name = Space * _Name

stringPart = (avoidChr) ->
    return (1 - MatchAnyOf("#{avoidChr}\r\n\f\\"))
DoubleQuotedString = Space * (MatchExact('"') * (ZeroOrMore(stringPart '"')/ast.StringLit) * MatchExact('"'))
SingleQuotedString = Space * (MatchExact("'") * (ZeroOrMore(stringPart "'")/ast.StringLit) * MatchExact("'"))

_Digits = OneOrMore MatchRange "09"
-- For long integer literals, eg 0ull or ulL
_IntEnding = OneOrLess  (OneOrLess MatchAnyOf "uU")*(TwoOrMore MatchAnyOf "lL")
_HexInt = (MatchExact "0x")*(OneOrMore MatchRange "09", "af", "AF")*_IntEnding
_Int = _Digits*_IntEnding + _HexInt
-- Accepts scientific notation
_FloatStart = Union _Digits*(OneOrLess (MatchExact ".")*_Digits), (MatchExact ".")*_Digits
_Float = _FloatStart * (OneOrLess MatchAnyOf("eE")*OneOrLess("-")*_Digits)

Float = _Float / ast.FloatLit
Int = _Int / ast.IntLit
Num = Space * (Int+Float)

symC = (chars) -> Space * Capture(MatchExact chars)
sym = (chars) -> Space * (MatchExact chars)
-- In increase precendence:
LogicOp = Space * Capture(MatchAnyOf("<>") + MatchExact("<=") + MatchExact(">="))
Op1 = Space * Capture(MatchAnyOf "%+%-")
Op2 = symC("..") + symC("and") + symC("or")
Op3 = Space * Capture(MatchAnyOf "%*%/%%")
Op4 = Space * Capture(MatchAnyOf "%^")

Shebang = MatchExact("#!") * (ZeroOrMore Complement Stop)

-- can't have P(false) because it causes preceding patterns not to run
Cut = ToPattern ()->false

StartBrace = sym("{") 
EndBrace = sym("}")
KeyValSep = sym(":") 

------------------------------------------------------------------------------
-- The actual grammar. Heavily 'inspired' by Moonscript's grammar (thanks, Leaf!)
------------------------------------------------------------------------------

-- Grammar reference syntactic helper (allows for var.k => Var "k")
gref = setmetatable {}, __index: (k) => Var k

extend = (src, new) ->
    for k,v in pairs(src)
        new[k] = v
    return new

indentStack = {0}
last_pos = 0

Indent = (Capture ZeroOrMore MatchAnyOf "\t ") / (str) ->
    -- Transform capture by counting the indent
    sum = 1
    for v in str\gmatch "[\t ]"
        if v == ' ' then sum += 1
        if v == '\t' then sum += 4
    return sum

_pushIndent = (indent) -> append indentStack, indent
_cbPopIndent = () -> 
    indentStack[#indentStack] = nil
    return true
_topIndent = () -> indentStack[#indentStack] 

_cbCheckIndent = (str, pos, indent) ->
    last_pos = pos
    pass = _topIndent() == indent
    return pass

_cbAdvanceIndent = (str, pos, indent) ->
    top = _topIndent()
    if indent > top
       _pushIndent(indent)
       return true

_cbPushIndent = (str, pos, indent) ->
    _pushIndent(indent)
    return true

indentG = {
    Advance: #lpeg.Cmt(Indent, _cbAdvanceIndent), -- Advances the indent, gives back whitespace for CheckIndent
    PushIndent: lpeg.Cmt(Indent, _cbPushIndent)
    PreventIndent: lpeg.Cmt(lpeg.Cc(-1), _cbPushIndent)
    PopIndent: lpeg.Cmt("", _cbPopIndent)
    CheckIndent: lpeg.Cmt(Indent, _cbCheckIndent), -- validates line is in correct indent
}

toOps = (...) ->
    args = {...}
    left = args[1]
    for i=2,#args,2
        left = ast.Operator(left, args[i], args[i+1])
    return left

opWrap = (op) -> gref._Expr * OneOrMore(op * gref.Expr) / toOps 

-- Mock AST
nast = setmetatable {}, {
        __index: (k) =>
            injectArr(k)
    }
lineEnding = Space * Break
grammar = MatchGrammar extend indentG, {
    gref.SourceCode -- Initial Rule
    SourceCode: Union {
        -- it could be a whole file
        (OneOrLess Shebang) * gref.Body / (body) -> ast.FuncBody({}, body)
        -- or this could be a single expression, such as in a REPL...
--        gref.Expr 
    }
  
    Line: gref.CheckIndent * gref.Statement * ZeroOrMore(lineEnding) + OneOrMore(lineEnding)
    Block: CaptureTable(gref.Line * ZeroOrMore(gref.Line))
    Statement: Union {
        gref.Loop
        gref.ReturnStmnt
        gref.If
        gref.AssignStmnt
        gref.Declare
        gref.FuncCall    / (@isExpression=false)=>@
        gref.FuncCallS   / (@isExpression=false)=>@
    }
    InBlock: gref.Advance * gref.Block * gref.PopIndent
    Body: ZeroOrMore(lineEnding) * gref.InBlock / ast.Block -- an indented block
    Loop: Union {
        sym('while') * gref.Expr*gref.Body/ast.While
        sym("for") * gref.AssignableList * sym("in") * gref.ExprList * gref.Body / ast.ForObj
        sym("for") * gref.Assignable * sym("=") * gref.ExprList * gref.Body / ast.ForNum
    }
    If: sym("if") * gref.Expr * gref.Body / ast.If
    Assign: (gref._ValOper*MatchExact("=")  + symC("=")) * gref.ExprList
    AssignStmnt: gref.AssignableList * gref.Assign / ast.Assign
    ReturnStmnt: sym("return") * gref.Expr / ast.Return
    Declare: _Name * gref.AssignableList * (OneOrLess gref.Assign) / ast.Declare

    Assignable: Union {
        sym("*") * gref.Expr / ast.BoxStore
        Name/ast.RefStore
        gref.Expr * sym("[") * gref.Expr * sym("]")/ast.ObjStore
        sym("&")* Name/(name) -> 
            store = ast.RefStore(name)
            store.isPtrSet = true
    }
    AssignableList: CaptureTable(gref.Assignable * (ZeroOrMore sym(",")*gref.Assignable))

    -- Expressions:
    ExprList: CaptureTable OneOrLess(gref.Expr * ZeroOrMore(sym(",")*gref.Expr))
    ExprListS: CaptureTable(gref.Expr * ZeroOrMore(sym(",")*gref.Expr))
    KeyValPair: Name * KeyValSep * gref.Expr / (key, value) -> {key, value}
    Object: StartBrace * CaptureTable OneOrLess(gref.KeyValPair * (ZeroOrMore sym(",") *gref.KeyValPair)) * EndBrace
    FuncParams: CaptureTable(OneOrLess(Name * ZeroOrMore(sym(",")*Name)))
    FuncHead: Union {
        sym('(')* gref.FuncParams*sym(')') * sym("->")
        gref.FuncParams * sym("->") 
    }
    Function: gref.FuncHead * gref.Body / ast.FuncBody
    _ValOper: Union {Op1, Op2, Op3, Op4}
    Operator: Union {
        opWrap LogicOp
        opWrap Op1
        opWrap Op2
        opWrap Op3
        opWrap Op4
    }
    _Expr: Union {
        sym("new") * gref.Expr / ast.BoxNew
        Name/ast.RefLoad
        Num
        SingleQuotedString
        DoubleQuotedString
        gref.Object/ast.Object
    }

    Expr: Union {
        gref._Expr * sym("[") * gref.Expr * sym("]")/ast.ObjLoad
        sym("&") * gref.Assignable / ast.BoxGet
        sym("*") * gref.Expr / ast.BoxLoad
        gref.FuncCall
        gref.Operator
        gref._Expr
        gref.Function
        sym('(')* gref.Expr * sym(")")
    }
    -- Note, FuncCall is both an expression and a statement
    FuncCall: gref._Expr * sym("(") * gref.ExprList * sym(")") /ast.FuncCall
    -- This form only allowed as a statement:
    FuncCallS: gref._Expr * gref.ExprListS /ast.FuncCall * OneOrMore(lineEnding)
}

parse = (codeString) -> 
    lpeg.match(grammar, codeString)

return {
    :parse
}


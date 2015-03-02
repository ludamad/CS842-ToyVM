require "util"

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

_Space = ZeroOrMore MatchAnyOf " \n\r\t"
Break = (OneOrLess "\r") * (MatchExact "\n")
Stop = Break + EndOfLine

Indent = (Capture ZeroOrMore MatchAnyOf "\t ") / (str) ->
    -- Transform capture by counting the indent
    sum = 0
    for v in str\gmatch "[\t ]"
        if v == ' ' then sum += 1
        if v == '\t' then sum += 4
    -- Return the indent amount
    return sum

Comment = (MatchAnyOf "--") * (ZeroOrMore Complement MatchAnyOf "\r\n") * #Stop
Space = _Space * (OneOrLess Comment)
SomeSpace = (OneOrMore MatchAnyOf " \t") * (OneOrLess Comment)
SpaceBreak = Space * Break
EmptyLine = SpaceBreak
AlphaNum = MatchRange("az", "AZ", "09", "__")
_Name = Capture (MatchRange "az", "AZ", "__")*(ZeroOrMore AlphaNum)
Name = Space * _Name

stringPart = (avoidChr) ->
    return (1 - MatchAnyOf("#{avoidChr}\r\n\f\\"))
DoubleQuotedString = Space * (MatchExact('"') * (ZeroOrMore(stringPart '"')/inject1("StringLit")) * MatchExact('"'))
SingleQuotedString = Space * (MatchExact("'") * (ZeroOrMore(stringPart "'")/inject1("StringLit")) * MatchExact("'"))

_Digits = OneOrMore MatchRange "09"
-- For long integer literals, eg 0ull or ulL
_IntEnding = OneOrLess  (OneOrLess MatchAnyOf "uU")*(TwoOrMore MatchAnyOf "lL")
_HexInt = (MatchExact "0x")*(OneOrMore MatchRange "09", "af", "AF")*_IntEnding
_Int = _Digits*_IntEnding + _HexInt
-- Accepts scientific notation
_FloatStart = Union _Digits*(OneOrLess (MatchExact ".")*_Digits), (MatchExact ".")*_Digits
_Float = _FloatStart * (OneOrLess MatchAnyOf("eE")*OneOrLess("-")*_Digits)

Float = _Float / inject1("FloatLit")
Int = _Int / inject1("IntLit")
Num = Space * (Int+Float)

FactorOp = Space * Capture(MatchAnyOf "+-")
TermOp = Space * Capture(MatchAnyOf "*/%^")

Shebang = MatchExact("#!") * (ZeroOrMore Complement Stop)

-- can't have P(false) because it causes preceding patterns not to run
Cut = ToPattern ()->false


sym = (chars) -> Space * (MatchExact chars)

StartObj = sym("{") 
EndObj = sym("}")
KeyValSep = sym(":") 

------------------------------------------------------------------------------
-- The actual grammar. Heavily 'inspired' by Moonscript's grammar (thanks, Leaf!)
------------------------------------------------------------------------------

-- Grammar reference syntactic helper (allows for var.k => Var "k")
gref = setmetatable {}, __index: (k) => Var k

grammar = MatchGrammar {
    gref.File -- Initial Rule          
    File: (OneOrLess Shebang) * (gref.Block + CaptureTable(""))
    Block: CaptureTable(gref.Line * ZeroOrMore(OneOrMore(Break) * gref.Line))
    Line: Space*gref.Statement + Space*IgnoreCapture(Stop)
    Statement: Union {
        gref.AssignStmnt
        gref.Declare
        gref.FuncCall
    }
    Assign: sym("=") * gref.ExprList
    AssignStmnt: gref.NameList * sym("=") * gref.ExprList /injectArr("Assign")
    Declare: _Name * gref.NameList * (OneOrLess gref.Assign) /injectArr("Declare")
    NameList: CaptureTable(Name * (ZeroOrMore sym(",")*Name))

    -- Expressions:
    ExprList: CaptureTable(gref.Expr * (ZeroOrMore sym(",")*gref.Expr))
    KeyValPair: Name * KeyValSep * gref.Expr / (key, value) -> {:key, :value}
    Object: StartObj * CaptureTable OneOrLess(gref.KeyValPair * (ZeroOrMore sym(",") *gref.KeyValPair)) * EndObj
    _Expr: Union {
        Name/inject1("Ref")
        Num
        SingleQuotedString
        DoubleQuotedString
        gref.Object/inject1("ObjectLit")
    }
    Expr: Union {
        gref.FuncCall
        gref._Expr
    }
    -- Note, FuncCall is both an expression and a statement
    FuncCall: gref._Expr * sym("(") * gref.ExprList * sym(")") /injectArr("FuncCall")
}

--matches = lpeg.match grammar, "
--    print({
--        hi: '', there: 2, 
--        people: 3
--    })
--"
--for m in *matches
--    pretty m

parse = (codeString) -> lpeg.match(grammar, codeString)

astToString = (node) ->
    if node == nil 
        return ""
    if type(node) ~= "table" 
        return node
    if #node > 0
        parts = {}
        for i=1,#node
            append(parts, astToString(node[i]))
        return table.concat parts, ' '
    if node.key
        return "#{node.key}: #{astToString(node.value)}"
    if node.kind
        return "(#{node.kind}: #{astToString(node.value)})"
    return ""

return {
    :parse, :astToString
}


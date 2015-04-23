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

import Scope from require "cmp_sym_resolve"

--------------------------------------------------------------------------------
-- Loaded once:
--------------------------------------------------------------------------------

_globalScope = nil

getGlobalScope = () ->
    if _globalScope
        return _globalScope
    import LangContext from require "cmp_context"
    globalLjContext = LangContext()
    _globalScope = runtime.makeGlobalScope(globalLjContext)
    _globalScope.context = globalLjContext
    return _globalScope

--------------------------------------------------------------------------------
-- The exported module
--------------------------------------------------------------------------------
M = {} -- Module

-- Utilities
loadE = (f,e) -> 
    if e.dest 
        return e.dest\load(f)
    else
        return e.compiledVal

--------------------------------------------------------------------------------
-- Third pass of compilation:
--  - Output code
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
--  Expression compilation:
--------------------------------------------------------------------------------

ast.installOperation {
    methodName: "compileVal"
    recurseName: "_compileValRecurse"
    -- AST node handlers:
    RefLoad: (f) => 
        return @symbol\load(f)
    IntLit: (f) =>
        return f\taggedIntConst(tonumber @value)
    StringLit: (f) =>
        ptr = f.ljContext\getStringPtr(@value)
        return f\loadRelative f\longConst(ptr), 0, lj.ulong
    FuncBody: (f) =>
        @compiledFunc = M.compileFuncBody @paramNames, @
        return f\longConst  @compiledFunc\toCFunction()
    Operator: (f) =>
        @_compileRecurse(f)
        val1 = loadE(f, @left)
        val2 = loadE(f, @right)
        if @op == '..'
            func = runtime.stringConcat
            return f\call(func, 'stringConcat', {val1, val2})
        op, boxer = switch @op
            when '-' then f.sub, f.makeLValInt
            when '+' then f.add, f.makeLValInt
            when '*' then f.mul, f.makeLValInt
            when '/' then f.div, f.makeLValInt
            when '%' then f.rem, f.makeLValInt
            when '<' then f.lt, f.makeLValBool
            when '>' then f.gt, f.makeLValBool
            when '>=' then f.gte, f.makeLValBool
            when '<=' then f.lte, f.makeLValBool
            when '==' then f.eq, f.makeLValBool
--        if op ~= '=='
            --compileNumCheck(val1)
            --compileNumCheck(val2)
        i1 = f\getLVal(val1)
        i2 = f\getLVal(val2)
        ret = op(f,i1, i2) 
        return boxer(f, ret)
    BoxNew: (f) => 
        @_compileRecurse(f)
        -- Not much else to do but ask the runtime kindly for a box.
        box = f\boxNew()
        expr = @expr.compiledVal
        f\boxStore(box, expr)
        return box
    BoxLoad: (f) => 
        @_compileRecurse(f)
        -- Not much else to do but ask the runtime kindly for a box.
        return f\boxLoad(@ptr.compiledVal)
}

ast.installOperation {
    methodName: "compile"
    recurseName: "_compileRecurse"
    FuncBody: (f) =>
        -- Are we the function being compiled?
        if @functionBuilder
            print("Funcbody")
            f\compileFuncPrelude()
            @block\compile(f)
            f\compileFuncReturn({})
       else -- No:
            @compiledVal = @compileVal(f)
            if @dest
                @dest\store(f, @compiledVal)
    If: (f) =>
        isTrue = f\truthCheck(@condition\compileVal(f))
        @labelEnd = lj.Label()
        f\branchIfNot(isTrue, @labelEnd)
        @block\compile(f)
        f\label(@labelEnd)
    While: (f) =>
        @labelCheck = lj.Label()
        @labelLoopStart = lj.Label()
        f\branch(@labelCheck)
        -- Resolve block label:
        f\label(@labelLoopStart)
        @block\compile(f)
        -- Resolve check label:
        f\label(@labelCheck)
        isTrue = f\truthCheck(@condition\compileVal(f))
        f\branchIf(isTrue, @labelLoopStart)
    Block: (f) =>
        @_compileRecurse(f)
    FuncCall: (f) =>
        @_compileRecurse(f)
        fVal = loadE(f, @func)
        -- @lastStackLoc is the next stack index after the current variables
        callSpace = f\longConst VAL_SIZE * (@lastStackLoc + #@args)
        if (@lastStackLoc + #@args ~= f.stackPtrsUsed)
            f\storeRelative(f.stackTopPtr, 0, f\add(f.stackFrameVal, callSpace))
        val = f\callIndirect(fVal, {f\intConst(#@args)}, lj.uint, {lj.uint})
        -- Must restore after return value changes in top pointer:
        f\storeRelative(f.stackTopPtr, 0, f.stackTopVal)
        if @isExpression
            @compiledVal = @dest\load(f)
    Expr: (f) =>
        @compiledVal = @compileVal(f)
        if @dest
            @dest\store(f, @compiledVal)
    Assignable: (f) => @_compileRecurse(f)
    Assign: (f) =>
        for i=1,#@vars
            var, val = @vars[i], @values[i]
            val\compile(f)
            var\compile(f)
            var\generateStore(f, val)
}

M.compileFuncBody = (paramNames, ast) ->
    scope = Scope(getGlobalScope())
    fb = FunctionBuilder(scope.parentScope.context, ast, scope, paramNames)
    scope.funcRoot = fb
    ast.functionBuilder = fb
    ast.block.scope = scope
    ast\symbolResolve(scope)
    ast\stackResolve(fb)    
    ast\compile(fb)
    fb\compile()
    return fb

return M

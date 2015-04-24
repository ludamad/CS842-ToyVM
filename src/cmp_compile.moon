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
        return @dest\load(f)
 
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
            when '!=' then f.ne, f.makeLValBool
--        if op ~= '=='
            --compileNumCheck(val1)
            --compileNumCheck(val2)
        if @op ~= "==" and @op ~= "!="
            i1 = f\getLVal(val1)
            i2 = f\getLVal(val2)
            ret = op(f,i1, i2) 
            return boxer(f, ret)
        else
            return boxer(f, op(f, val1, val2))
    BoxNew: (f) => 
        @_compileRecurse(f)
        -- Not much else to do but ask the runtime kindly for a box.
        box = f\boxNew()
        expr = @expr.compiledVal
        f\boxStore(box, expr)
        return box
    BoxLoad: (f) => 
        @_compileRecurse(f)
        return f\boxLoad(@ptr.compiledVal)
    ObjLoad: (f) =>
        @_compileRecurse(f)
        freshCache = f\longConst f.ljContext\getNewInlineCache()
        return f\call runtime.objectGet, 'objectGet', {f\longConst(0), @obj.compiledVal, @key.compiledVal, freshCache}

    Object: (f) =>
        obj = f\call(runtime.objectNew, 'objectNew', {f\longConst runtime.getGlobals()})
        @dest\store(f, obj) -- Store in case object moves during initialization
        for {k,v} in *@value
            kPtr = f.ljContext\getStringPtr(k)
            kVal = f\loadRelative f\longConst(kPtr), 0, lj.ulong

            v\compile(f)
            -- It's unlikely for an object constructor to have stable writes
            -- we shouldn't use an inline cache here -- ideally, an object template would have been made.
            freshCache = f\longConst 0
            -- freshCache = f\longConst f.ljContext\getNewInlineCache()
            f\call runtime.objectSet, 'objectSet', {f\longConst(0), @dest\load(f), kVal, v.compiledVal, freshCache}

        return @dest\load(f)
}

ast.installOperation {
    methodName: "compile"
    recurseName: "_compileRecurse"
    FuncBody: (f) =>
        -- Are we the function being compiled?
        if @functionBuilder
  
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
    Return: (f) =>
        -- @_compileRecurse(f)
        f\compileFuncReturn({@value})
    FuncCall: (f) =>
        @_compileRecurse(f)
        fVal = loadE(f, @func)
        callSpaceN = VAL_SIZE * (@lastStackLoc + #@args)
        -- @lastStackLoc is the next stack index after the current variables
        callSpace = f\longConst callSpaceN
        -- if (@lastStackLoc + #@args ~= f.stackPtrsUsed)
        f\storeRelative(f.stackTopPtr, 0, f\add(f.stackFrameVal, callSpace))
        val = f\callIndirect(fVal, {f\intConst(#@args)}, lj.uint, {lj.uint})
        -- Must restore after return value changes in top pointer:
        f\storeRelative(f.stackTopPtr, 0, f.stackTopVal)
        if @isExpression
            @compiledVal = f\loadRelative(f.stackFrameVal, callSpaceN - VAL_SIZE * (#@args), lj.ulong)
            @dest\store(f, @compiledVal)
    Object: (f) =>
        -- compileVal sets dest
        @compiledVal = @compileVal(f)
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
    -- print ast
    ast\compile(fb)
    fb\compile()
    return fb

return M

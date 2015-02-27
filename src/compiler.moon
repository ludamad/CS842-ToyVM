ffi = require "ffi"

lj = require "libjit"

ffi.cdef [[
    typedef struct {
        int parts[2];
    } LangValue;
    typedef uint64_t (*LangRuntimeFunc1)(uint64_t);
]]

import astToString from require "parser"

M = {} -- Module

M.Variable = newtype {
    init: (@name) =>
        @isConstant = false
    makeConstant: (value) =>
        @isConstant = true
        @constantValue = value
}

M.Param = newtype {
    init: (@name) =>
        @var = M.Variable(@name)
}

M.Scope = newtype {
    init: (@parentScope = false) =>
        @variables = {}
    -- By default, a = 1 will declare in current context if not in above contexts
    declareIfNotPresent: (name) =>
        if @get(name) == nil
            @declare(name)
    declare: (var) =>
        if type(var) == "table"
            @variables[var.name] = var
        else
            @variables[name] = M.Variable(name)
    get: (name) =>
        scope = @
        while scope ~= false
            if scope.variables[name] ~= nil
                return scope.variables[name]
            scope = scope.parentScope
        return nil
}

fficast = ffi.cast
vcast = (val) -> fficast("void*", val)

-- Preallocated for convenience
label1, label2 = ffi.new("jit_label_t[1]"), ffi.new("jit_label_t[1]")
int1, int2, result = ffi.new("jit_uint[1]", 21), ffi.new("jit_uint[1]", 42), ffi.new("jit_uint[1]", 0)


TYPE_TAG_INT = 1
M.FunctionBuilder = newtype {
    parent: lj.Function
    init: (@ljContext, @params, @scope = M.Scope()) =>
        ljParamTypes = {}
        for i=1,#@params
            ljParamTypes[i] = lj.ptr
        print('lj',lj.ulong)
        lj.Function.init(@, @ljContext, lj.ulong, ljParamTypes)
        for i=1,#@params
            {:var} = @params[i]
            var.value = @getParam(i-1)
            @scope\declare(var)
    pushScope: () =>
        @scope = M.Scope(@scope)
    Ref: (node) =>
        var = @scope\get(node.value)
        if var.isConstant
            return var.constantValue
        return var.valuA
    IntLit: (node) =>
        val = ffi.new("LangValue")
        val.parts[0] = tonumber(node.value)
        val.parts[1] = TYPE_TAG_INT
        return @createLongConstant(lj.ulong, ffi.cast("uint64_t", val))

    -- AST node handlers:
    FuncCall: (node) =>
        {func, args} = node.value
        value = @compileNode(func)
        fargs = {}
        for i=1,#args
            fargs[i] = @compileNode(args[i])
        @call(value, func.value, fargs)

    compileNode: (node) =>
        print "Compiling #{astToString(node)}"
        @[node.kind](@,node)
    compileAst: (ast) =>
        @ljContext\buildStart()
        for node in *ast
            @compileNode(node)
        @ljContext\buildEnd()
    callFromLua: (values, ret) =>
        for i=1,#values
            values[i] = vcast(values[i])
        @apply(values, vcast(ret))
        print("Result is: ", result[0])
}
return M

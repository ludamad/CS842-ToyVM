ffi = require "ffi"

lj = require "libjit"

VAL_SIZE = 8
ffi.cdef [[
    typedef struct {
        int val, tag;
    } LangValue;
    typedef uint64_t (*LangRuntimeFunc)(LangValue* args, unsigned int n);
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
            ljParamTypes[i] = lj.ulong
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
        return var.value
    IntLit: (node) =>
        val = ffi.new("uint64_t[1]")
        int_view = ffi.cast("int*", val)
        int_view[0] = tonumber(node.value)
        int_view[1] = TYPE_TAG_INT
        return @createLongConstant(lj.ulong, val[0])

    allocate: () =>
        @call 
        
    -- AST node handlers:
    FuncCall: (node) =>
        {func, args} = node.value
        value = @compileNode(func)
        print "Calling"
        @call(value, "", @frame [@compileNode arg for arg in *args])
    frame: (args) =>
        ptr = @alloca(@createLongConstant(lj.ulong, #args * 8))
        for i=1,#args
            @storeRelative(ptr, 8*(i-1), args[i]) 
        return {ptr, @createLongConstant(lj.ulong, #args)} 
    compileNode: (node) =>
        print "Compiling #{astToString(node)}"
        val = @[node.kind](@,node)
        print "Compiled #{astToString(node)}"
        return val

    compileAst: (ast) =>
        @ljContext\buildStart()
        for node in *ast
            @compileNode(node)
        @compile()
        @ljContext\buildEnd()
    callFromLua: (values, ret) =>
        for i=1,#values
            values[i] = vcast(values[i])
        @apply(values, vcast(ret))
}
return M

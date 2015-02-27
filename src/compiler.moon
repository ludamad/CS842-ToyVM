ffi = require "ffi"

lj = require "libjit"

ffi.cdef [[
    typedef uint64_t (*LangRuntimeFunc)(uint64_t* args, unsigned long n);
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

__frameCache = {}
frameType = (n) ->
    if not __frameCache[n]
        types = [lj.ulong for i=1,n]
        __frameCache[n] = lj.createStruct(types)
    return __frameCache[n]


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
        return var.valuA
    IntLit: (node) =>
        val = ffi.new("uint64_t[1]")
        int_view = ffi.cast("int*", val)
        int_view[0] = tonumber(node.value)
        int_view[1] = TYPE_TAG_INT
        return @createLongConstant(lj.ulong, val[0])

    -- AST node handlers:
    FuncCall: (node) =>
        {func, args} = node.value
        value = @compileNode(func)
        fargs = {}
        for i=1,#args
            fargs[i] = @compileNode(args[i])
        frame = @frame(fargs)
        print "Calling"
        @call(value, func.value, frame)

    compileNode: (node) =>
        print "Compiling #{astToString(node)}"
        val = @[node.kind](@,node)
        print "Compiled #{astToString(node)}"
        return val
    frame: (values) =>
        frame = @create(frameType(#values))
        framePtr = @addressOf(frame)
        for i=1,#values
            @storeRelative(framePtr, (i-1)*8, values[i])
        return {frame, @createLongConstant(lj.ulong, #values)}

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
        print("Result is: ", result[0])
}
return M

ffi = require "ffi"
runtime = require "runtime"
librun = require 'libruntime'
gc = require "ggggc"
Cggggc = require "compiler_ggggc"

lj = require "libjit"

import astToString from require "parser"

import Variable, Param from require "compiler_syms"

M = {} -- Module

VAL_SIZE = 8 -- TODO add some constants file

M.Scope = newtype {
    init: (@parentScope = false) =>
        @variables = {}
    -- By default, a = 1 will declare in current context if not in above contexts
    declareIfNotPresent: (name) =>
        val = @get(name) 
        if val then return val
        return @declare(name)
    declare: (var) =>
        if type(var) == "table"
            @variables[var.name] = var
        else
            @variables[name] = var
        return var
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

initContext = (C) -> 
    if not rawget C, 'initialized'
        log "initContext is running! mmap funkiness ahead."
        PSTACKSIZE = VAL_SIZE*1024^2
        C.globals = ffi.new("struct LangGlobals[1]")
        C.initialized = true
        librun.langGlobalsInit(C.globals, PSTACKSIZE)
        log "initContext has ran."

stringPtrs = {}
neg8unsigned64bit = ffi.cast "uint64_t", ffi.cast("int64_t", -8)
M.FunctionBuilder = newtype {
    parent: lj.Function
    -- Returns the offset from @pstack:
    pushObjPtr: (val) =>
        if not val
            val = @createLongConstant(lj.ulong, @ljContext.globals[0].defaultValue)
        neg8 = @createLongConstant(lj.ulong, neg8unsigned64bit)
        stackPtr = @loadRelative(@pstackTop, 0, lj.ptr)
        @storeRelative stackPtr, -8, vall
        @storeRelative @pstackTop, 0, @addRelative(@pstackTop, 0, neg8)
        return @loadRelative stackPtr, 0, lj.ptr

    popObjPtr: () =>
        pos8 = @createLongConstant(lj.ulong, 8)
        @storeRelative @pstackTop, 0, @addRelative(@pstackTop, 0, pos8)
    init: (@ljContext, @params, @scope = M.Scope()) =>
        initContext(@ljContext)
        lj.Function.init(@, @ljContext, lj.ulong, {lj.ptr, lj.uint})
        -- Keep track of pointers that must be freed if this function is trashed:
        @constantPtrs = {}
        @cfunc = false
        {:pstackTop, :pstack} = @ljContext.globals[0]
        @pstackTop = @createPtrRaw(pstackTop)
        @pstack = @createPtrRaw(pstack)
        argsV = @getParam(0)
        for i=1,#@params
            {:var} = @params[i]
            var.value = @loadRelative(argsV, 8*(i-1), lj.ulong)
            @scope\declareIfNotPresent(var)
    -- Wraps a pointer value directly:
    createPtrRaw: (ptr) =>
        return @createLongConstant(lj.ptr, ffi.cast("unsigned long", ptr))
    -- Creates a managed pointer:
    createPtr: (val) =>
        logV "createPtr", val
        ptr = librun.langCreatePointer()
        ptr[0] = val
        append @constantPtrs, ptr
        return ptr, @createPtrRaw(ptr)
    pushScope: () =>
        @scope = M.Scope(@scope)

    -- AST node handlers:
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
    Assign: (node) =>
        {varDecls, op, varValues} = node.value
        assert #varDecls == #varValues
        for i=1,#varDecls
            decl, val  = varDecls[i], varValues[i]
            --if @scope

    StringLit: (node) =>
        if not stringPtrs[node.value]
            stringPtrs[node.value] = librun.langNewString(node.value, #node.value)
        ptr, jitVal = @createPtr(stringPtrs[node.value])
        return @loadRelative(jitVal, 0, lj.ulong)
    
    FuncCall: (node) =>
        {func, args} = node.value
        value = @compileNode(func)
        logV "Calling"
        @call(value, "", @frame [@compileNode arg for arg in *args])
    frame: (args) =>
        ptr = @alloca(@createLongConstant(lj.ulong, #args * 8))
        for i=1,#args
            @storeRelative(ptr, 8*(i-1), args[i]) 
        return {ptr, @createLongConstant(lj.ulong, #args)} 
    compileNode: (node) =>
        logV "Compiling #{astToString(node)}"
        val = @[node.kind](@,node)
        logV "Compiled #{astToString(node)}"
        return val

    compileAsm: (ast) =>
        @compile()
        @ljContext\buildEnd()
    compileIR: (ast) =>
        @ljContext\buildStart()
        for node in *ast
            @compileNode(node)
    __call: (...) =>
        args = {...}
        @cfunc = @cfunc or ffi.cast("LangFunc", @toCFunction())
        cargs = ffi.new('LangValue[?]', #args)
        for i=1,#args do cargs[i-1] = args[i]
        return @.cfunc(cargs, #args)
}

-- Ad-hoc multiple inheritance:
for k,v in pairs(Cggggc.functionBuilderGGGCMethods)
    M.FunctionBuilder[k] = v

return M


-- TODO: Make environment variable
DEBUGGING = true

M = {} -- Module

M.checkerType = (methods) -> 
    methods.init or= ((@name) =>) 
    methods.meta or=  () => "getmetatable(#{@name})"
    methods.typeof or=  () => "type(#{@name})"
    methods.assert or= (cond) => 
        return "assert(#{cond},[[#{@name} failed: #{cond}]])"
    methods.__call or= (@defaultValue) => 
        return @
    methods.default = () =>
        if @defaultValue ~= M.NO_DEFAULT
            return @defaultValue
        return nil

    T = newtype(methods)
    return setmetatable {type: T}, {
        __index: (k) =>
            return T(k)
        __call: (...) => T(...)
    }

M.NO_DEFAULT = {}
M.defaultInit = () =>
    @_any = false
    @_metatype = false
    @_list = false
    @_prim = false
    @defaultValue = M.NO_DEFAULT

M.Any = M.checkerType {
    init: (@name) =>
        M.defaultInit(@)
        @_any = true
    emitCheck: (code, repr) => nil
}

M.MetaType = (metatable) -> M.checkerType {
    init: (@name) =>
        M.defaultInit(@)
        @_metatype = true
        @metatable = metatable
    emitCheck: (code, repr) => 
        append code, @assert("#{@meta()} == #{repr}.metatable")
}

M.List = (subtype) -> M.checkerType {
    init: (@name) =>
        M.defaultInit(@)
        @_list = true
        @subtype = subtype
        @obj = @.subtype("#{@name}[i]")
    emitCheck: (code, repr) => 
        -- Perform full typechecking.
        append code, @assert("#{@typeof()} == 'table'")
        append code, @assert("#{@meta()} == nil")
        append code, "for i=1, # #{@name} do"
        --append code, "print('namei', #{@name}[i])"
        @obj\emitCheck(code, "#{repr}.subtype")
        append code, "end"
}

M.PrimType = (str) -> M.checkerType {
    init: (@name) =>
        M.defaultInit(@)
        @_prim = true
    emitCheck: (code, repr) => 
        append code, @assert("#{@typeof()} == '#{str}'")
}

M.String, M.Num, M.Table = M.PrimType('string'), M.PrimType('number'), M.PrimType('table')
M.Bool = M.PrimType('boolean')

__makeCacheLine = (...) ->
    commaList = table.concat {...}, ', '
    return "local #{commaList} = #{commaList}"

import concat from table
M.makeInit = (T, fields) ->
    code = {}
    ids = ["__Tcheck_repr#{i}" for i=1,#fields]
    names = [f.name for f in *fields]
    append code, "-- #{table.concat names}"
    append code, __makeCacheLine('assert', 'type', 'getmetatable', 'setmetatable')
    append code, "local __TYPE, #{concat ids, ', '} = ..."
    append code, "return function(#{concat names, ', '})"
    append code, "local self = setmetatable({}, __TYPE)"
    for i=1,#fields
        {:name} = fields[i]
        --if DEBUGGING
        --    append(code, "print('#{name} =', #{name})") 
        if fields[i]\default() ~= nil
            defS = pretty_s fields[i]\default()
            append(code, "self.#{name} = #{name} ~= nil and #{name} or #{defS}")
        else
            append code, "if #{name} ~= false then"
            fields[i]\emitCheck(code, ids[i])
            append code "end"
            append(code, "self.#{name} = #{name}") 
    append code, "self:init()"
    append code, "return self\nend"
    codeString = table.concat(code, '\n')
    logV("---------------\n", codeString, "\n-------------")
    func, err = loadstring(codeString)
    if func == nil
        error(err)
    return func(T, unpack(fields))

M.checkedType = (t) ->
    assert(t.init)
    cpy = {}
    for k,v in pairs(t)
        if type(k) ~= "number"
            cpy[k] = v
    T = newtype(cpy)
    T.create = M.makeInit(T, t)
    getmetatable(T).__call = (...) =>
        return T.create(...)
    return T, cpy

return M

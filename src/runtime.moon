ffi = require "ffi"
lj = require "libjit"
librun = require "libruntime"
gc = require "ggggc"

ffi.cdef [[
    typedef struct {
        int tag, val;
    } LangValue;
    typedef unsigned int (*LangFunc)(unsigned int n);
]]

longConst = (f, v) ->
    return f\createLongConstant(lj.ulong, ffi.cast("int64_t",v))
lcast = (v) -> ffi.cast 'uint64_t', v
local C 
makeGlobalScope = (ljContext) ->
    C or= require "compiler"
    scope = C.Scope()

    {:pstack, :pstackTop} = ljContext.globals[0]
    pstackTop = ffi.cast("LangValue**", pstackTop)
    getArgs = (n) ->
        return pstackTop[0] - n

    setRet = (n, r, type) ->
        top = pstackTop[0]
        bottom = pstackTop[0] - n + 1
        pstackTop[0] = bottom
        ffi.cast("#{type}*", bottom)[-1] = r
        while bottom < top
            ffi.cast("uint64_t*", bottom)[0] = 0
            bottom += 1
        return 1

    toStr = (valPtr) ->
        val = valPtr[0]
        assert val.tag ~= 0, 'nil value!'
        if val.tag == C.TYPE_TAG_INT
            v = tostring(val.val)
            return librun.langStringCopy(v, #v)
        if val.tag == C.TYPE_TAG_BOOL
            v = if val.val == 0 then 'false' else 'true'
            return librun.langStringCopy(v, #v)
        return (ffi.cast "LangString*", valPtr)[0]

    -- Runtime functions.
    -- LuaJIT 'converts' these to C pointers callable by libjit, what a dear ...
    funcs = {
        tostring: (n) ->
            log 'tostring', n
            assert n == 1, "tostring takes 1 argument!"
            argPtr = getArgs(n)
            s = toStr(argPtr)
            return setRet(n, s, "LangString*")
        print: (n) ->
           log "#{n} args to print"
           args = getArgs(n)
           for i=0,tonumber(n)-1
              log(args[i].tag, args[i].val)
              if i >= 1 
                  io.write '\t'
              if args[i].tag == 0
                  io.write 'nil'
              elseif args[i].tag == C.TYPE_TAG_INT
                  io.write(args[i].val)
              elseif args[i].tag == C.TYPE_TAG_BOOL
                  if args[i].val ~= 0
                      io.write("true")
                  else
                      io.write("false")
              else -- Assume string!
                  asString = ffi.cast("void**", args + i)[0]
                  librun.langStringPrint(asString)
           io.write('\n')
           return 0
    }

    -- Wrap as runtime funcs:
    for k,v in pairs(funcs)
        funcs[k] = lj.NativeFunction(ffi.cast("LangFunc", v), lj.ulong, {lj.ptr, lj.uint})

    for k,v in pairs(funcs)
        scope\declare(C.Constant(k, v))

    values = {
        "true": (f) -> longConst(f, 4294967297)
        "false": (f) -> longConst(f, 1)
    }

    for k,v in pairs(values)
        scope\declare(C.Constant(k, v))
    return scope

gcMalloc = lj.NativeFunction(gc.ggggc_malloc, lj.ptr, {lj.ptr})
gcMallocPointerArray = lj.NativeFunction(gc.ggggc_mallocPointerArray, lj.ptr, {})
gcMallocDataArray = lj.NativeFunction(gc.ggggc_mallocDataArray, lj.ptr, {})

stringConcat = lj.NativeFunction(librun.langStringConcat, lj.ptr, {lj.ptr, lj.ptr})
return {:makeGlobalScope, :gcMalloc, :gcMallocPointerArray, :gcMallocDataArray, :stringConcat}


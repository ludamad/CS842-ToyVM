-- This module simply extends FunctionBuilder for dumping.

runtime = require "runtime"
ffi = require "ffi"
lj = require "libjit"
col = require "system.AnsiColors"

import FunctionBuilder 
    from require "cmp_func_builder"

-- Utilties
fcast = ffi.cast
fnew = ffi.new

--------------------------------------------------------------------------------
-- Colorful LibJIT IR dumper:
--------------------------------------------------------------------------------
FunctionBuilder.smartDump = () =>
    {:stackTop, :boxTypeDesc, :stringTypeDesc} = @ljContext
    f = fcast("unsigned long", stackTop)
    stackStr = tostring(f) 
    stackStr = stackStr\sub(1, #stackStr-3)
    d = @dump()\split('\n')
    nameCache = {}
    names = {"foo", "bar", "baz", "cindy", "alpha", "bravo", "wilfrid", "tusk", "sam", "valz", "sin", 'pindet', 'sukki', 'oPtr', 'ranDat'}
    cntr = 0
    nameBetter = (digits) ->
        if nameCache[digits] 
            return nameCache[digits]
        nameCache[digits] = names[cntr%#names+1]
        if cntr >= #names
            nameCache[digits] ..= math.floor(cntr/#names)
        cntr += 1
        return nameCache[digits]

    cnt = 1
    for i=1,#d
        replace = (s, m) ->
            d[i] = d[i]\gsub s, m
        replaceConstant = (name, func) ->
            f = fcast("unsigned long", func)
            str1 = tostring(f) 
            str1 = str1\sub(1, #str1-3)
            str2 = ("0x%x")\format(tonumber f)
            replace(str1, col.GREEN("$#{name}",col.BOLD))
            replace(str2, col.GREEN("$#{name}",col.BOLD))
        for k, v in pairs runtime
            if getmetatable(v) == lj.NativeFunction 
                replaceConstant(k, v.func)
        scope = @scope
        while scope
            for k, v in pairs scope.variables
                if rawget(v, 'value') and type(v.value) == 'table'
                    replaceConstant(v.name, v.value.func)
            scope = scope.parentScope
        replace '.L:%s*', () ->
            s = col.WHITE("--- Section #{cnt} ---", col.FAINT)
            cnt += 1
            return s
        replace(stackStr, col.YELLOW('$stack',col.BOLD))
        replace 'load_relative_long%((.*), (.*)%)', (a,b) ->
            return "#{a}[#{b/8}]" 
        replace 'call.*%((.*)%)', (a) -> "call #{a}"
        replace 'store_relative_long%((.*), (.*), (.*)%)', (a,b,c) ->
            c = tonumber(c)/8
            return "#{a}[#{c}] = #{b}" 
        replace 'l(%d+)', (digits) ->
            color = col.pickCol(tonumber digits)
            return color(nameBetter digits)
        replace '(%d+)%[0%]', (digits) ->
            -- This should be a constant GC object.
            -- (Otherwise, we may very well segfault :-)
            asLong = fcast("unsigned long", tonumber digits)
            asS = fcast("LangString**", asLong)[0]
            if asS[0].gcHeader.descriptor__ptr == stringTypeDesc[0]
                arr = asS[0].array[0]
                newStr = ffi.string(arr.a__data, arr.length - 1)
                return col.MAGENTA("\"#{newStr}\"", col.BOLD)
            -- Check if this object is a descritpor:
            if asS[0].gcHeader.descriptor__ptr == stringTypeDesc[0][0].header.descriptor__ptr
                return col.WHITE("<BoxType>", col.BOLD)
            return "*(GC** #{digits})"
        replace '(%d+)', (digits) ->
            if tonumber(digits) < 4294967296
                return digits
            endChr = fnew('char*[1]')
            num = ffi.C.strtoull(digits, endChr, 10)
            numPtr = fnew('uint64_t[1]', num)
            val = fcast('LangValue*', numPtr)[0]
            return col.GREEN("#{val.val}" , col.BOLD).. col.WHITE("!#{val.tag}", col.FAINT)

    return table.concat(d,'\n')


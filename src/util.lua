local rawset,setmetatable,pairs=rawset,setmetatable,pairs -- Caching
local nilprotect_meta = {__index = function(self, k)
    error( ("Key '%s' does not exist in table!"):format(k) )
end}

-- Set to a metatable that does not allow nil accesses
function nilprotect(t)
    return setmetatable(t, nilprotect_meta)
end

function values(table)
    local idx = 1
    return function()
        local val = table[idx]
        idx = idx + 1
        return val
    end
end

local VERBOSITY = tonumber(os.getenv("V") or '0')
local DO_VERBOSE = VERBOSITY >= 3
local DO_INFO = VERBOSITY >= 2
local DO_LOG = VERBOSITY >= 1

-- Global logging facility:
function do_nothing() end
logV = DO_VERBOSE and print or do_nothing
logI = DO_INFO    and print or do_nothing
log  = DO_LOG     and print or do_nothing

-- Like C printf, but always prints new line
function printf(fmt, ...) print(fmt:format(...)) end
function errorf(fmt, ...) error(fmt:format(...)) end
function assertf(cond, fmt, ...) return assert(cond, fmt:format(...)) end

-- Lua table API extensions:
append = table.insert

--- Get a  human-readable string from a lua value. The resulting value is generally valid lua.
-- Note that the paramaters should typically not used directly, except for perhaps 'packed'.
-- @param val the value to pretty-print
-- @param tabs <i>optional, default 0</i>, the level of indentation
-- @param packed <i>optional, default false</i>, if true, minimal spacing is used
-- @param quote_strings <i>optional, default true</i>, whether to print strings with spaces
function pretty_tostring(val, --[[Optional]] tabs, --[[Optional]] packed, --[[Optional]] quote_strings)
    tabs = tabs or 0
    quote_strings = (quote_strings == nil) or quote_strings

    local tabstr = ""

    if not packed then
        for i = 1, tabs do
            tabstr = tabstr .. "  "
        end
    end
    if type(val) == "string" then val = val:gsub('\n','\\n') end
    if type(val) == "string" and quote_strings then
        return tabstr .. "\"" .. val .. "\""
    end

    local meta = getmetatable(val) 
    if (meta and meta.__tostring) or type(val) ~= "table" then
        return tabstr .. tostring(val)
    end

    local parts = {"{", --[[sentinel for remove below]] ""}

    for k,v in pairs(val) do
        table.insert(parts, packed and "" or "\n") 

        if type(k) == "number" then
            table.insert(parts, pretty_tostring(v, tabs+1, packed))
        else 
            table.insert(parts, pretty_tostring(k, tabs+1, packed, false))
            table.insert(parts, " = ")
            table.insert(parts, pretty_tostring(v, type(v) == "table" and tabs+1 or 0, packed))
        end

        table.insert(parts, ", ")
    end

    parts[#parts] = nil -- remove comma or sentinel

    table.insert(parts, (packed and "" or "\n") .. tabstr .. "}");

    return table.concat(parts)
end

function pretty_tostring_compact(v)
    return pretty_tostring(v, nil, true)
end

-- string trim12 from lua wiki
function string:trim()
    local from = self:match"^%s*()"
    return from > #self and "" or self:match(".*%S", from)
end

-- Lua string API extension:
function string:split(sep) 
    local t = {}
    self:gsub(("([^%s]+)"):format(sep), 
        function(s) table.insert(t, s) end
    )
    return t 
end

local __DEBUGGING = true
function newtype(methods)
    methods = methods or {}
    local typemeta = {}
    local methodsmeta = {}
    setmetatable(methods, methodsmeta)
    local type = setmetatable({__index = methods}, typemeta)
    for k,v in pairs(methods) do
        if k:find("__") == 1 then
            methods[k] = nil
            type[k] = v
        end
    end
    -- Inheritance:
    if methods.parent ~= nil then
        local unboxed = getmetatable(methods.parent).__index
        for k,v in pairs(unboxed) do 
            methods[k] = methods[k] or v
        end
        methods.parent = nil
    end

    -- The constructor:
    function typemeta:__call(...)
        local val = setmetatable({}, type)
        methods.init(val, ...)
        return val
    end
    function typemeta:__newindex(k, v)
        if k:find("__") == 1 then
            rawset(self, k, v)
        else
            methods[k] = v
        end
    end
    typemeta.__index = methods
    if __DEBUGGING then
        function methodsmeta:__index(k)
            error("Key '"..k.."' does not exist!") 
        end
        function type:__newindex(k, v)
            if v == nil then 
                error("Cannot set '"..k.."' to nil") 
            end
            rawset(self, k, v)
        end
    end
    return type
end

--- Get a  human-readable string from a lua value. The resulting value is generally valid lua.
-- Note that the paramaters should typically not used directly, except for perhaps 'packed'.
-- @param val the value to pretty-print
-- @param tabs <i>optional, default 0</i>, the level of indentation
-- @param packed <i>optional, default false</i>, if true, minimal spacing is used
function pretty_print(val, --[[Optional]] tabs, --[[Optional]] packed)
    print(pretty_tostring(val, tabs, packed))
end

function pretty_s(val)
    if type(val) == "string" then
        return val
    end
    if type(val) ~= "function" then
        return pretty_tostring_compact(val)
    end
    local info = debug.getinfo(val)
    local ups = "{" ; for i=1,info.nups do 
        local k, v = debug.getupvalue(val,i) ; ups = ups .. k .."="..tostring(v)..","
    end
    return "function " .. info.source .. ":" .. info.linedefined .. "-" .. info.lastlinedefined .. ups .. '}'
end

-- Convenience print-like function:
function pretty(...)
    local args = {}
    for i=1,select("#", ...) do
        args[i] = pretty_s(select(i, ...))
    end
    print(unpack(args))
end


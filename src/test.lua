-- Lua

print "Hello World!"
someTableFunction {
    a = 1
}
aVarFunction(print)

local arr = {1}
while arr[1] < 10 do
    arr[1] = arr[1] + 1
end

local obj = {}

function obj:myMethod(...)
    return ...
end
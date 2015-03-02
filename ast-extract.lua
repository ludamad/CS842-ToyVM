
require "util"

local AstTracer = newtype {}
function AstTracer:init(name)
    
end

local function extractAst(func) 
    local newG = {}
    local newGMeta = {}
    function newGMeta:__index(k)
    end
    function newGMeta:__newindex(k)
    end
    setmetatable(newG,newGMeta)
    setfenv(func, newG)
end
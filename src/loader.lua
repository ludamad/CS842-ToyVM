-------------------------------------------------------------------------------
-- Ensure undefined global access is an error.
-------------------------------------------------------------------------------

local global_meta = {}
setmetatable(_G, global_meta)

function global_meta:__index(k)
    error("Undefined global variable '" .. k .. "'!")
end

-------------------------------------------------------------------------------
-- Define global utilities.
-------------------------------------------------------------------------------

package.path = package.path .. ';./src/?.lua' 
package.cpath = package.cpath .. ';./build/?.so' 

-------------------------------------------------------------------------------
-- Ensure proper loading of moonscript files.
-------------------------------------------------------------------------------

require("moonscript.base").insert_loader()

require "util"
local ErrorReporting = require "system.ErrorReporting"

ErrorReporting.wrap(function() 
    require("main")
end)()

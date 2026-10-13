-- metatables / metamethods
local V = {}
V.__index = V
V.__add = function(a, b) return setmetatable({x = a.x + b.x}, V) end
V.__tostring = function(a) return "V(" .. a.x .. ")" end
function V.new(x) return setmetatable({x = x}, V) end
local p = V.new(3) + V.new(4)
print(tostring(p))
-- __index function fallback
local base = setmetatable({}, {__index = function(_, k) return "missing:" .. k end})
print(base.whatever)

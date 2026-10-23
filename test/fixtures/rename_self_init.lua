-- Regression: `local x = <expr using x>` — RHS must read the OUTER x,
-- not the new binding. Also parameter self-shadow and do-block shadow.
local function f(x)
  local x = x or 5
  return x
end
print(f(10))   -- 10
print(f(nil))  -- 5

local y = 3
do
  local y = y + 1
  print(y)     -- 4
end
print(y)       -- 3

local t = setmetatable({}, { __index = function() return 7 end })
local t = t                 -- RHS t is the metatabled table
print(t.anything)           -- 7

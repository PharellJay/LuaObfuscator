-- closures & shared upvalues
local function counter()
  local n = 0
  return function() n = n + 1; return n end
end
local c = counter()
print(c(), c(), c())

local function makePair()
  local v = 10
  local get = function() return v end
  local set = function(x) v = x end
  return get, set
end
local g, s = makePair()
print(g()); s(42); print(g())

-- closure capturing loop variable (each iteration distinct in Lua 5.4)
local fns = {}
for i = 1, 3 do fns[i] = function() return i end end
print(fns[1](), fns[2](), fns[3]())

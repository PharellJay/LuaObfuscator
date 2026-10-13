-- varargs and select
local function sum(...)
  local t = {...}
  local s = 0
  for i = 1, select("#", ...) do s = s + t[i] end
  return s, select("#", ...)
end
print(sum(1, 2, 3, 4))
print(sum())
local function fwd(...) return ... end
print(fwd(1, nil, 3))  -- preserve embedded nils via select count
print(select("#", fwd(1, nil, 3)))

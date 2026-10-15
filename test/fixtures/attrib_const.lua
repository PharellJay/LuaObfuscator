-- Lua 5.4: <const> variable attribute.
local x <const> = 42
local y <const> = x * 2
local t = {}
for i = 1, 3 do t[i] = i * x end
print(x, y, t[1], t[2], t[3])

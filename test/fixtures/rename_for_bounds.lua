-- Regression: for-loop bounds / iterator expressions evaluate in the
-- ENCLOSING scope, not the fresh loop scope.
local i = 2
local sum = 0
for i = i, i + 3 do sum = sum + i end
print(sum)   -- 2+3+4+5 = 14

local data = { a = 1, b = 2 }
local keys = 0
for data in pairs(data) do keys = keys + 1 end
print(keys)  -- 2

local n = 1
for n = n, n do print(n) end  -- prints 1

-- multiple return values & adjustment
local function mr() return 1, 2, 3 end
local a, b, c = mr()
print(a, b, c)
print((mr()))          -- parens truncate to 1
local t = {mr(), mr()} -- first call truncated, last expands
print(#t)
print(mr(), 99)        -- non-tail call truncated to 1

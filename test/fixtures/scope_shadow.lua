-- Block-local shadowing: a local declared in an if/while/repeat block must not
-- leak into siblings or outward (VariableRenamer scope-precision regression).
local function eq(a, d) print(a and ("PASS " .. d) or ("FAIL " .. d)) end

local n = 5
local r
if false then local n = 999 r = n elseif true then r = n end
eq(r == 5, "if-clause local does not leak to elseif")

local a = 1
if true then local a = 2 end
eq(a == 1, "if-then local shadow")

local b = 1
while b < 3 do local b = 99 break end
eq(b == 1, "while body local shadow (cond uses outer)")

local c = 5
repeat local c = 0 until true
eq(c == 5, "repeat body local shadow")

local sum = 0
for i = 1, 3 do local sum = i end  -- inner sum shadows
eq(sum == 0, "for body local shadow")

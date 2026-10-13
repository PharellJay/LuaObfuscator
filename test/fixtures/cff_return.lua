-- Control-flow flattening of return-bearing blocks (C1a). Plain top-level
-- functions (not vm_) so the native flattener path is exercised.
local function eq(a, d) print(a and ("PASS " .. d) or ("FAIL " .. d)) end

function straight() local a = 1 local b = 2 local c = 3 return a + b + c end
function loopThenReturn() local s = 0 for i = 1, 5 do s = s + i end return s end
function ifThenReturn(cond) local r = 0 if cond then r = r + 10 end r = r + 1 return r end
function earlyReturn(c) if c then return 1 end return 2 end       -- nested return -> bails, must stay correct
function noReturn(t) t.x = 1 t.y = 2 end                          -- no trailing return (current behavior)
function manyStmts() local a = 1 local b = a + 1 local c = b + 1 local d = c + 1 return a + b + c + d end

eq(straight() == 6, "straight-line then return")
eq(loopThenReturn() == 15, "loop then return")
eq(ifThenReturn(true) == 11 and ifThenReturn(false) == 1, "if (no return) then return")
eq(earlyReturn(true) == 1 and earlyReturn(false) == 2, "early return inside if (bail path)")
local tt = {}; noReturn(tt); eq(tt.x == 1 and tt.y == 2, "no trailing return")
eq(manyStmts() == 10, "many statements then return")

-- Nested returns flattened via the RETSIG protocol (C1b-1). Plain functions.
local function eq(a, d) print(a and ("PASS " .. d) or ("FAIL " .. d)) end

-- early return inside if, then more work + trailing return
function f1(x) local a = 1 if x > 0 then return "pos" end a = a + 1 return "nonpos" .. a end
-- return in elseif / else
function f2(x) local r = 0 if x == 1 then return "one" elseif x == 2 then return "two" else r = 9 end return "other" .. r end
-- return nested two levels deep
function f3(x) local y = x if x > 0 then if x > 10 then return "big" end y = y + 1 end return "small" .. y end
-- return inside a for-loop body (search)
function f4(t, target) for i = 1, #t do if t[i] == target then return i end end return -1 end
-- return inside a while body
function f5(n) local i = 0 while i < n do i = i + 1 if i == 3 then return i * 100 end end return i end
-- multi-value nested return
function f6(x) if x then return 1, 2, 3 end return 0 end
-- bare nested return (no value)
function f7(x) local acc = 0 if x then acc = 1 return end acc = 2 return acc end
-- nested function literal whose own return must stay internal
function f8(x) local g = function(n) return n * 2 end if x then return g(5) end return g(1) end

eq(f1(5) == "pos" and f1(-1) == "nonpos2", "early return in if")
eq(f2(1) == "one" and f2(2) == "two" and f2(3) == "other9", "return in elseif/else")
eq(f3(20) == "big" and f3(5) == "small6" and f3(-1) == "small-1", "return two levels deep")
eq(f4({ 10, 20, 30 }, 20) == 2 and f4({ 1, 2 }, 9) == -1, "return inside for")
eq(f5(10) == 300 and f5(2) == 2, "return inside while")
local a, b, c = f6(true); eq(a == 1 and b == 2 and c == 3, "multi-value nested return")
eq(f6(false) == 0, "multi-return else path")
eq(f7(true) == nil and f7(false) == 2, "bare nested return")
eq(f8(true) == 10 and f8(false) == 2, "inner function return stays internal")

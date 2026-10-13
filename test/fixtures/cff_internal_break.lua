-- Internal breaks (C1b-2): a break enclosed by a loop within a flattened block
-- is safe and should now flatten. Plain functions.
local function eq(a, d) print(a and ("PASS " .. d) or ("FAIL " .. d)) end

-- for + internal break, followed by more statements and a trailing return
function firstEven(t) local found = -1 for i = 1, #t do if t[i] % 2 == 0 then found = t[i] break end end local tag = "e" return tag .. found end
-- while + internal break
function countTo(n) local i = 0 local c = 0 while true do i = i + 1 if i > n then break end c = c + i end return c end
-- internal break AND a nested return in the same block (C1b-1 + C1b-2 together)
function search(t, x) local seen = 0 for i = 1, #t do seen = seen + 1 if t[i] == x then return i end if t[i] < 0 then break end end return -seen end
-- nested loops, break in the inner one only
function grid(n) local total = 0 for i = 1, n do for j = 1, n do if j > i then break end total = total + 1 end end return total end

eq(firstEven({ 1, 3, 4, 6 }) == "e4", "for internal break")
eq(countTo(5) == 15, "while internal break")
eq(search({ 5, 7, 2 }, 2) == 3 and search({ 5, -1, 2 }, 9) == -2, "internal break + nested return")
eq(grid(3) == 6, "nested loops inner break")

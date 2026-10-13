-- Escaping breaks (C1b-3): a break targeting a loop that ENCLOSES the flattened
-- block. Loop bodies have >=2 statements so they flatten. Plain functions.
local function eq(a, d) print(a and ("PASS " .. d) or ("FAIL " .. d)) end

function sumUntil(t, limit) local s = 0 for i = 1, #t do local v = t[i] if s + v > limit then break end s = s + v end return s end
function firstNeg(t) local idx = 0 local i = 0 while i < #t do i = i + 1 local x = t[i] if x < 0 then idx = i break end idx = 0 end return idx end
-- escaping break AND a return in the same loop body
function scan(t) local c = 0 for i = 1, #t do c = c + 1 if t[i] == 0 then break end if t[i] < 0 then return -c end end return c end
-- nested loops: inner internal break + outer escaping break in one body
function mix(n) local total = 0 for i = 1, n do local hit = false for j = 1, n do if j > 2 then break end hit = true end if i > 3 then break end total = total + 1 end return total end

eq(sumUntil({ 1, 2, 3, 10, 1 }, 6) == 6, "for escaping break")
eq(sumUntil({ 1, 2 }, 100) == 3, "break not taken")
eq(firstNeg({ 3, 5, -2, 8 }) == 3, "while escaping break")
eq(scan({ 4, 5, 0, 9 }) == 3 and scan({ 4, -1, 9 }) == -2, "escaping break + return same loop")
eq(mix(5) == 3, "nested loops: inner internal + outer escaping break")

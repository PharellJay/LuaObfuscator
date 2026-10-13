-- repeat...until in the VM (A1). vm_* compiled to the VM.
local function eq(a, d) print(a and ("PASS " .. d) or ("FAIL " .. d)) end

function vm_countdown(n) local r = "" repeat r = r .. n n = n - 1 until n == 0 return r end
function vm_sum_repeat(n) local s, i = 0, 1 repeat s = s + i i = i + 1 until i > n return s end
function vm_repeat_break(t) local i, r = 1, "" repeat if t[i] == nil then break end r = r .. t[i] i = i + 1 until false return r end
function vm_scope_until() local i = 0 repeat local x = i * 2 i = i + 1 until x >= 6 return i end

eq(vm_countdown(5) == "54321", "repeat countdown")
eq(vm_sum_repeat(10) == 55, "repeat sum")
eq(vm_repeat_break({ "a", "b", "c" }) == "abc", "break in repeat")
eq(vm_scope_until() == 4, "local visible in until")

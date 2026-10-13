-- Functions named vm_* are compiled to the bytecode VM. A plain checker
-- (not virtualized) prints PASS/FAIL so the harness can compare behavior.
local function eq(a, d) print(a and ("PASS " .. d) or ("FAIL " .. d)) end

function vm_add(a, b) return a + b end
function vm_poly(x) return x * x + 2 * x - 1 end
function vm_cmp(a, b) return a < b, a <= b, a == b, a ~= b end
function vm_fact(n) local r = 1; local i = 1; while i <= n do r = r * i; i = i + 1 end return r end
function vm_sumfor(n) local s = 0; for i = 1, n do s = s + i end return s end
function vm_andor(a, b) return a and b, a or b end
function vm_concat(a, b) return a .. b end
function vm_tbl(a, b) local t = { a, b, ["sum"] = a + b } return t[1], t[2], t.sum end
function vm_len(s) return #s end
function vm_call(n) return vm_add(n, 10) end
function vm_method(s) return s:upper() end
function vm_recur(n) if n <= 1 then return 1 else return n * vm_recur(n - 1) end end
function vm_neg(x) return - -x end

eq(vm_add(3, 4) == 7, "add")
eq(vm_poly(5) == 34, "poly")
local a, b, c, d = vm_cmp(1, 2)
eq(a == true and b == true and c == false and d == true, "multi-return compare")
eq(vm_fact(5) == 120, "while factorial")
eq(vm_sumfor(10) == 55, "numeric for")
local x, y = vm_andor(nil, 7)
eq(x == nil and y == 7, "and/or")
eq(vm_concat("foo", "bar") == "foobar", "concat")
local p, q, r = vm_tbl(2, 3)
eq(p == 2 and q == 3 and r == 5, "table ctor")
eq(vm_len("hello") == 5, "length")
eq(vm_call(5) == 15, "cross-call")
eq(vm_method("abc") == "ABC", "method call")
eq(vm_recur(6) == 720, "recursion")
eq(vm_neg(5) == 5, "double unary minus")

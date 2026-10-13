-- Vararg virtualization. vm_* functions are compiled to the VM.
local function eq(a, d) print(a and ("PASS " .. d) or ("FAIL " .. d)) end

function vm_count(...) return select("#", ...) end
function vm_sum(...) local s = 0 for i = 1, select("#", ...) do s = s + select(i, ...) end return s end
function vm_pack(...) local t = { ... } return #t end
function vm_fwd(...) return ... end
function vm_mixed(a, b, ...) return a + b, select("#", ...) end
function vm_viamax(...) return math.max(...) end
function vm_tableva(...) local t = { 0, ... } return #t end
function vm_rettrail(x, ...) return x, ... end

eq(vm_count(1, 2, 3) == 3, "select count")
eq(vm_count() == 0, "select count empty")
eq(vm_sum(1, 2, 3, 4) == 10, "vararg sum")
eq(vm_pack("a", "b", "c") == 3, "table from varargs")
local a, b, c = vm_fwd(7, 8, 9)
eq(a == 7 and b == 8 and c == 9, "forward varargs")
local s, n = vm_mixed(10, 20, "x", "y", "z")
eq(s == 30 and n == 3, "fixed+vararg")
eq(vm_viamax(3, 9, 5, 1) == 9, "pass ... to math.max")
eq(vm_tableva(1, 2, 3) == 4, "table {0, ...}")
local p, q, r = vm_rettrail("h", 1, 2)
eq(p == "h" and q == 1 and r == 2, "return x, ...")

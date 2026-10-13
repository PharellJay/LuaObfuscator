-- Upvalue capture (step 3b). vm_* are compiled to the VM.
local function eq(a, d) print(a and ("PASS " .. d) or ("FAIL " .. d)) end

function vm_counter() local n = 0 return function() n = n + 1 return n end end
function vm_pair() local v = 10 return function() return v end, function(x) v = x end end
function vm_adder(a) return function(b) return a + b end end
function vm_loopcap() local t = {} for i = 1, 3 do t[i] = function() return i end end return t[1]() * 100 + t[2]() * 10 + t[3]() end
function vm_two() local x = 5 return function() return function() return x end end end
function vm_accum() local s = 0 local function add(n) s = s + n end add(3) add(4) return s end
function vm_shared() local c = 0 local function inc() c = c + 1 end local function get() return c end inc() inc() inc() return get() end

local c = vm_counter()
eq(c() == 1 and c() == 2 and c() == 3, "counter captures/mutates")
local get, set = vm_pair(); set(99)
eq(get() == 99, "shared get/set cell")
local add5 = vm_adder(5)
eq(add5(10) == 15, "adder factory")
eq(vm_loopcap() == 123, "loop var fresh per iteration")
eq(vm_two()()() == 5, "two-level transitive upvalue")
eq(vm_accum() == 7, "local function captures/mutates")
eq(vm_shared() == 3, "two closures share one cell")

-- Top-level `local function vm_*` virtualization (option 2).
local function eq(a, d) print(a and ("PASS " .. d) or ("FAIL " .. d)) end

local function vm_double(x) return x * 2 end
local function vm_sum3(a, b, c) local s = a + b s = s + c return s end
-- recursive local function: must stay NATIVE (self-ref bail) and still be correct
local function vm_fact(n) if n <= 1 then return 1 end return n * vm_fact(n - 1) end

eq(vm_double(21) == 42, "local fn virtualized")
eq(vm_sum3(1, 2, 3) == 6, "local fn multi-stmt")
eq(vm_fact(5) == 120, "recursive local fn (native fallback, correct)")

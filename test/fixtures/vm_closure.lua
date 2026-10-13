-- Non-capturing nested functions (step 3a). vm_* are compiled to the VM.
local function eq(a, d) print(a and ("PASS " .. d) or ("FAIL " .. d)) end

function vm_make() return function(x) return x * 2 end end
function vm_apply(f, v) return f(v) end
function vm_localfn(n) local function g(k) return k * k end return g(n) end
function vm_nested2() local function a(x) return x + 1 end local function b(x) return x + 2 end return a(10) + b(10) end
function vm_hof(v) return vm_apply(function(x) return x * 3 end, v) end
function vm_recurnest(n) function _vmfib(k) if k < 2 then return k else return _vmfib(k - 1) + _vmfib(k - 2) end end return _vmfib(n) end

local dbl = vm_make()
eq(dbl(21) == 42, "returned closure")
eq(vm_apply(function(x) return x + 5 end, 10) == 15, "higher-order arg")
eq(vm_localfn(6) == 36, "local function no-capture")
eq(vm_nested2() == 23, "two local functions")
eq(vm_hof(4) == 12, "anon passed through")
eq(vm_recurnest(10) == 55, "global nested recursion")

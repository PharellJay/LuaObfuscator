-- Coroutines driven through the VM (step 4a). vm_* are compiled to the VM.
local function eq(a, d) print(a and ("PASS " .. d) or ("FAIL " .. d)) end

function vm_squares(n) for i = 1, n do coroutine.yield(i * i) end return -1 end
function vm_counter_co() local n = 0 while true do n = n + 1 coroutine.yield(n) end end
function vm_echo() local x = coroutine.yield("ready") return "got:" .. x end

local co = coroutine.create(vm_squares)
local _, a = coroutine.resume(co, 3)
local _, b = coroutine.resume(co)
local _, c = coroutine.resume(co)
local _, d = coroutine.resume(co)
eq(a == 1 and b == 4 and c == 9 and d == -1, "coroutine.yield from VM for-loop")

local g = coroutine.wrap(vm_counter_co)
eq(g() == 1 and g() == 2 and g() == 3, "coroutine.wrap VM generator")

local e = coroutine.create(vm_echo)
local _, r1 = coroutine.resume(e)
local _, r2 = coroutine.resume(e, "hi")
eq(r1 == "ready" and r2 == "got:hi", "yield returns resume value")

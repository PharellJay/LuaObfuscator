-- Multi-assign incl. index targets (A2). vm_* compiled to the VM.
local function eq(a, d) print(a and ("PASS " .. d) or ("FAIL " .. d)) end

function vm_swap(a, b) a, b = b, a return a, b end
function vm_idx2(t) t.x, t.y = 10, 20 return t.x + t.y end
function vm_mixed(t) local a = 0 a, t.z = 5, 6 return a + t.z end
function vm_from_call(t) local function two() return 7, 8 end t.p, t.q = two() return t.p * 10 + t.q end
function vm_arr(t) t[1], t[2], t[3] = "a", "b", "c" return t[1] .. t[2] .. t[3] end

local x, y = vm_swap(3, 4)
eq(x == 4 and y == 3, "name swap")
eq(vm_idx2({}) == 30, "two index targets")
eq(vm_mixed({}) == 11, "mixed name + index")
eq(vm_from_call({}) == 78, "index targets from call")
eq(vm_arr({}) == "abc", "array index targets")

-- Generic-for virtualization. vm_* functions are compiled to the VM.
local function eq(a, d) print(a and ("PASS " .. d) or ("FAIL " .. d)) end

function vm_sumpairs(t) local s = 0 for k, v in pairs(t) do s = s + v end return s end
function vm_concat_ipairs(t) local r = "" for i, v in ipairs(t) do r = r .. v end return r end
function vm_count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function vm_keysum(t) local s = 0 for k, v in pairs(t) do s = s + k end return s end
function vm_gmatch() local r = {} for x in string.gmatch("a,bb,ccc", "[^,]+") do r[#r + 1] = x end return r[1] .. r[2] .. r[3] end
function vm_nested(t) local s = 0 for _, row in ipairs(t) do for _, v in ipairs(row) do s = s + v end end return s end
function vm_break(t) local r = "" for i, v in ipairs(t) do if v == "stop" then break end r = r .. v end return r end

eq(vm_sumpairs({ 10, 20, 30 }) == 60, "pairs sum")
eq(vm_concat_ipairs({ "a", "b", "c" }) == "abc", "ipairs concat")
eq(vm_count({ x = 1, y = 2, z = 3 }) == 3, "pairs count")
eq(vm_keysum({ [1] = 0, [2] = 0, [5] = 0 }) == 8, "pairs key sum")
eq(vm_gmatch() == "abbccc", "gmatch iterator")
eq(vm_nested({ { 1, 2 }, { 3, 4 }, { 5 } }) == 15, "nested for-in")
eq(vm_break({ "a", "b", "stop", "c" }) == "ab", "break in for-in")

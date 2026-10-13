-- Top-level method/field virtualization. Global module table M (virtualizes);
-- local table L (base is a chunk-local -> must stay native, still correct).
local function eq(a, d) print(a and ("PASS " .. d) or ("FAIL " .. d)) end

M = {}
function M.vm_add(a, b) return a + b end
function M:vm_set(v) self.val = v end
function M:vm_get() return self.val end
function M.vm_fact(n) if n <= 1 then return 1 end return n * M.vm_fact(n - 1) end  -- recursion via global M

local L = { base = 100 }
function L.vm_x(n) return L.base + n end   -- base L is a chunk-local -> stays native

eq(M.vm_add(3, 4) == 7, "M.vm_add field")
M:vm_set(42)
eq(M:vm_get() == 42, "M:vm_set / M:vm_get (self)")
eq(M.vm_fact(5) == 120, "M.vm_fact recursion via global")
eq(L.vm_x(5) == 105, "L.vm_x (local base, native)")

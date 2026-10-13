-- Nested dotted/colon function definitions inside a virtualized function.
local function eq(a, d) print(a and ("PASS " .. d) or ("FAIL " .. d)) end

function vm_dotdef() local t = {} function t.m(x) return x * 2 end return t.m(21) end
function vm_colondef() local t = { v = 5 } function t:get() return self.v end function t:add(n) self.v = self.v + n end t:add(3) return t:get() end
function vm_deep() local a = { b = {} } function a.b.calc(x) return x + 100 end return a.b.calc(1) end

eq(vm_dotdef() == 42, "nested t.m def")
eq(vm_colondef() == 8, "nested t:method def (self)")
eq(vm_deep() == 101, "nested a.b.m def")

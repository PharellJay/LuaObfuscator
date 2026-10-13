-- Bitwise ops inside virtualized functions (VM bitwise opcodes). vm_* compiled.
local function eq(a, d) print(a and ("PASS " .. d) or ("FAIL " .. d)) end

function vm_band(a, b) return a & b end
function vm_bor(a, b) return a | b end
function vm_bxor(a, b) return a ~ b end
function vm_bnot(a) return ~a end
function vm_shl(a, n) return a << n end
function vm_shr(a, n) return a >> n end
function vm_idiv(a, b) return a // b end
function vm_mix(a, b) local x = (a & b) | (a ~ b) return x + (a << 1) end

eq(vm_band(6, 3) == 2, "band")
eq(vm_bor(5, 2) == 7, "bor")
eq(vm_bxor(6, 3) == 5, "bxor")
eq(vm_bnot(0) == -1, "bnot")
eq(vm_shl(1, 4) == 16, "shl")
eq(vm_shr(256, 2) == 64, "shr")
eq(vm_idiv(7, 2) == 3, "idiv")
eq(vm_mix(6, 3) == 19, "mixed bitwise")

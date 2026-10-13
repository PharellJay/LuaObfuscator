-- Bitwise operator support (parser Step 2). Round-trips through the pipeline.
local function eq(a, b, d) print((a == b) and ("PASS " .. d) or ("FAIL " .. d .. " got " .. tostring(a))) end

eq(5 & 3, 1, "and")
eq(5 | 2, 7, "or")
eq(6 ~ 3, 5, "xor")
eq(~0, -1, "unary not")
eq(1 << 4, 16, "shift left")
eq(256 >> 2, 64, "shift right")
eq(7 // 2, 3, "floor div")
eq(1 | 2 & 3, 3, "and binds tighter than or")   -- 1 | (2&3) = 1|2 = 3
eq((6 ~ 3) == 5, true, "xor then compare")
eq(~0 & 255, 255, "unary not then and")
eq(0xF0 | 0x0F, 255, "hex bitwise")
eq(2 << 1 << 1, 8, "shift chain")

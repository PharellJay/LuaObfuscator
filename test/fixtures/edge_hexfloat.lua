-- §2: hexadecimal floating-point literals (valid since Lua 5.2/5.3).
print(0x1p4)
print(0x1.8p1)
print(0xA.8)
print(0x1.8)
local x = 0x10p-2
print(x)
print(0x1p4 + 0x1.8p1)

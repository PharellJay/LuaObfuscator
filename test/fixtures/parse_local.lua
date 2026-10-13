-- Adjacent-statement parsing around `local` (parser Step 1).
B = 0  -- global
local a = 5
b = a + 1          -- global write; previously mis-parsed into the local list above
print(a, b, type(b))
local x = 10
local t = {}
t.k = x            -- index assignment right after a local
print(t.k)
local p, q = 1, 2  -- multi-name local still works
print(p, q)
local u            -- uninitialized local followed by a statement
u = 99
print(u)

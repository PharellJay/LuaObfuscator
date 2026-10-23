-- Regression: a leveled long string whose body contains ]] must not be truncated.
local s = [==[has ]] inside]==]
print(s)
print(#s)
local u = [=[level one ]] still going]=]
print(u)

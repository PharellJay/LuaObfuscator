-- Lua 5.4: <close> variable attribute (to-be-closed, invokes __close on scope exit).
local function make()
    return setmetatable({}, {__close = function() print("closed") end})
end
do
    local r <close> = make()
    print("inside")
end
print("after")

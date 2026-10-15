-- §1a regression: a GenericStatement whose RHS is a function literal containing
-- nested control flow before a function-level return must NOT be mis-detected as
-- a terminal statement (which previously dropped following statements / crashed).
local function run()
    local f = function() for i = 1, 3 do end return 7 end
    local g = function() if 1 > 0 then return 10 end return 0 end
    local a = f()
    local b = g()
    local c = a + b
    print(a, b, c)
end
run()

local function run2()
    local make = function(n)
        local acc = 0
        for i = 1, n do acc = acc + i end
        return acc
    end
    local x = make(4)
    local y = make(5)
    print(x, y, x + y)
end
run2()

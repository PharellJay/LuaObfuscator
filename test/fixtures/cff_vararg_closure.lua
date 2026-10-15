-- CFF wider-coverage regression: a flattenable block that contains nested vararg
-- CLOSURES must now flatten AND stay correct, while a `...` that escapes to the
-- enclosing function must still be handled correctly.
local function eq(a, d) print(a and ("PASS " .. d) or ("FAIL " .. d)) end

-- Block whose only `...` uses are inside nested closures -> should flatten now.
local function usesClosures()
    local count = function(...) return select("#", ...) end
    local first = function(x, ...) return x end
    local a = count(1, 2, 3, 4)
    local b = first(10, 20, 30)
    local c = a + b
    return c
end

-- Enclosing vararg used directly (escaping) inside a multi-statement body: must
-- stay correct whether or not CFF flattens it.
local function sumAll(...)
    local t = { ... }
    local s = 0
    for i = 1, #t do s = s + t[i] end
    local doubled = s * 2
    return s, doubled
end

-- Nested closure that itself captures and uses the outer vararg by value.
local function capture(...)
    local n = select("#", ...)
    local getn = function() return n end
    local m = getn()
    local r = m + 1
    return r
end

eq(usesClosures() == 14, "nested vararg closures flatten")
local s, d = sumAll(3, 4, 5); eq(s == 12 and d == 24, "escaping vararg stays correct")
eq(capture("a", "b", "c") == 4, "closure capturing outer vararg count")

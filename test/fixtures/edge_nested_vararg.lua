-- §1e: a flattenable block containing a nested closure that uses `...`. The outer
-- block must remain correct (CFF may conservatively skip it, but never miscompile).
local function outer()
    local pack = function(...) return select("#", ...) end
    local a = pack(1, 2, 3)
    local b = pack(1)
    local c = a + b
    print(a, b, c)
end
outer()

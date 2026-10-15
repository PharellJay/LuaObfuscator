local function NumHex(num)
    return string.format("0x%x", num)
end

local function NumMultiChain(num)
    if num < 0 then return nil end
    local numTerms = math.random(3, 6)
    local vals = {}
    local ops = {}
    local partial = 0

    for i = 1, numTerms - 1 do
        local v = math.random(1, math.max(100, math.floor(num * 0.5) + math.random(1000, 50000)))
        table.insert(vals, v)
        if i == 1 then
            partial = v
        else
            if math.random(0, 1) == 0 then
                table.insert(ops, "+")
                partial = partial + v
            else
                table.insert(ops, "-")
                partial = partial - v
            end
        end
    end

    local last_plus = num - partial
    local last_minus = partial - num
    local last_val, last_op
    if last_plus >= 0 then
        last_val, last_op = last_plus, "+"
    elseif last_minus >= 0 then
        last_val, last_op = last_minus, "-"
    else
        return nil
    end

    table.insert(vals, last_val)
    table.insert(ops, last_op)

    local expr = string.format("(0x%x", vals[1])
    for i = 2, #vals do
        expr = string.format("(%s%s0x%x)", expr, ops[i - 1], vals[i])
    end
    return expr .. ")"
end

-- Mixed boolean-arithmetic: encode `num` using an algebraic identity over native
-- Lua 5.3+ bitwise operators, so the constant never appears literally. The output
-- is final Lua (this is a text pass), so it may use `~ & |` directly.
--   a + b == (a | b) + (a & b)        and        a + b == (a ~ b) + 2*(a & b)
-- with a random split a, b = a, num-a (a in [0, num], so both are non-negative).
local function NumMBA(num)
    if num < 0 or num ~= math.floor(num) then return nil end
    local a = math.random(0, num)
    local b = num - a
    if math.random(0, 1) == 0 then
        return string.format("((0x%x|0x%x)+(0x%x&0x%x))", a, b, a, b)
    else
        return string.format("((0x%x~0x%x)+2*(0x%x&0x%x))", a, b, a, b)
    end
end

-- Double-XOR identity: (enc ~ K) == num, where enc = num ~ K is computed now.
-- Hides `num` behind two unrelated-looking constants.
local function NumXorId(num)
    if num < 0 or num ~= math.floor(num) then return nil end
    local key = math.random(1, 0xFFFFFFF)
    local enc = num ~ key
    return string.format("(0x%x~0x%x)", enc, key)
end

local intStrategies = {
    { name = "multiChain", fn = NumMultiChain },
    { name = "mba",        fn = NumMBA },
    { name = "xorId",      fn = NumXorId },
}

function ObfuscateAllIntegers(fullCode)
    return ProcessOutsideStrings(fullCode, function(segment)
        local numbers = {}
        local counter = 0

        -- Protect hex FLOAT literals (0x1.8p-2, 0x1p4, 0xA.8, 0x.8) from the hex
        -- integer matcher below, which would otherwise grab the `0x1` out of
        -- `0x1.8p1` and corrupt it. Kept as-is (\3), like scientific notation.
        local function keepHexFloat(before, hf)
            counter = counter + 1
            numbers[counter] = hf
            return before .. "\1" .. counter .. "\3"
        end
        segment = segment:gsub("([^%w_])(0[xX]%x*%.%x*[pP][%+%-]?%d+)", keepHexFloat)
        segment = segment:gsub("([^%w_])(0[xX]%x+[pP][%+%-]?%d+)", keepHexFloat)
        segment = segment:gsub("([^%w_])(0[xX]%x+%.%x*)", keepHexFloat)
        segment = segment:gsub("([^%w_])(0[xX]%.%x+)", keepHexFloat)

        -- Must NOT match inside _0x... variable names (used by DeadCodeInjector)
        segment = segment:gsub("([^%w_])(0[xX][0-9a-fA-F]+)", function(before, hex)
            counter = counter + 1
            numbers[counter] = hex
            return before .. "\1" .. counter .. "\2"
        end)
        -- Also match hex literals at start of a segment
        segment = segment:gsub("^(0[xX][0-9a-fA-F]+)", function(hex)
            counter = counter + 1
            numbers[counter] = hex
            return "\1" .. counter .. "\2"
        end)

        -- Protect scientific notation numbers from being split by simpler patterns
        -- Standard: 1e3, 1.5e-2, 0.5e+3
        segment = segment:gsub("(%d+%.?%d*[eE][%+%-]?%d+)", function(n)
            counter = counter + 1
            numbers[counter] = n
            return "\1" .. counter .. "\3"
        end)
        -- Dot-first scientific: .5e3, .5e-2
        segment = segment:gsub("(%.%d+[eE][%+%-]?%d+)", function(n)
            counter = counter + 1
            numbers[counter] = n
            return "\1" .. counter .. "\3"
        end)

        -- Numbers preceded by whitespace, punctuation, or assignment/comparison operators
        segment = segment:gsub("([%s%(%)%[%]%,%;%{%}=])(%d+%.?%d*)([%s%(%)%[%]%,%;%{%}.=]?)", function(before, n, after)
            counter = counter + 1
            numbers[counter] = n
            return before .. "\1" .. counter .. "\2" .. (after or "")
        end)

        -- Numbers preceded by arithmetic operators
        segment = segment:gsub("([%+%-%*/%%%^#])(%d+%.?%d*)([^%w_%=<>%~!]?)", function(op, n, after)
            counter = counter + 1
            numbers[counter] = n
            return op .. "\1" .. counter .. "\2" .. (after or "")
        end)

        -- Decimal numbers starting with dot (non-scientific)
        segment = segment:gsub("([%s%(%)%[%]%,%;%{%}=])(%.%d+)([%s%(%)%[%]%,%;%{%}.=]?)", function(before, n, after)
            counter = counter + 1
            numbers[counter] = n
            return before .. "\1" .. counter .. "\2" .. (after or "")
        end)

        -- Numbers at the start of a segment
        segment = segment:gsub("^(%d+%.?%d*)", function(n)
            counter = counter + 1
            numbers[counter] = n
            return "\1" .. counter .. "\2"
        end)

        -- Replace \2 sentinels (obfuscate numbers)
        segment = segment:gsub("\1(%d+)\2", function(idx)
            return ObfuscateNumber(numbers[tonumber(idx)])
        end)

        -- Replace \3 sentinels (scientific notation - keep as-is)
        segment = segment:gsub("\1(%d+)\3", function(idx)
            return numbers[tonumber(idx)]
        end)

        return segment
    end)
end

function ObfuscateNumber(n)
    local hexBody = n:match("^0[xX]([0-9a-fA-F]+)$")
    if hexBody then
        local sigHex = hexBody:match("^0*(.+)$")
        if not sigHex or #sigHex == 0 then
            return "(0x0)"
        end
        if #sigHex > 13 then
            return "(" .. n .. "+0x0)"
        end
        local num = tonumber(n)
        if num then
            return ObfuscateInteger(num)
        end
        return "(" .. string.format("0x%x", num) .. "+0x0)"
    end

    local num = tonumber(n)
    if not num then return n end

    -- A float LITERAL must stay a float even when its value is integral. Lua 5.3+
    -- distinguishes integers from floats (math.type, tostring/print formatting,
    -- bitwise-operator validity, string.format("%d")), so turning the literal
    -- `3.0` into an integer `3` is a behavior change. Decide float-ness from the
    -- literal TEXT (a '.' or an exponent marker), not from `num % 1`, because
    -- `3.0 % 1 == 0`. Integral-valued floats are obfuscated as an integer
    -- expression coerced back to float with `+ 0.0` (value-preserving).
    local isFloatLiteral = n:find("[%.eEpP]") ~= nil

    if num % 1 ~= 0 then
        local m = tostring(num):match("%.(%d+)")
        if not m then return n end
        local multiplier = 10 ^ #m
        local numerator = num * multiplier
        local frac = "(" .. NumHex(numerator) .. "/" .. NumHex(multiplier) .. ")"
        local extra = math.random(1, 999)
        if math.random(0, 1) == 0 then
            return frac
        else
            return "(" .. NumHex(numerator + extra) .. "-" .. NumHex(extra) .. ")/" .. NumHex(multiplier)
        end
    elseif isFloatLiteral then
        local intVal = math.tointeger(num) or math.floor(num)
        return "(" .. ObfuscateInteger(intVal) .. "+0.0)"
    else
        return ObfuscateInteger(num)
    end
end

function ObfuscateInteger(num)
    local candidates = {}
    for _, s in ipairs(intStrategies) do
        local ok, result = pcall(s.fn, num)
        if ok and result then
            table.insert(candidates, result)
        end
    end
    if #candidates == 0 then
        if num >= 0 then
            return "(" .. NumHex(num) .. "+0x0)"
        else
            return "(-" .. NumHex(-num) .. ")"
        end
    end
    return candidates[math.random(1, #candidates)]
end

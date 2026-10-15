local constants = {}
local constantMap = {}
local currentPoolName = ""
local entryKeys = {}

-- ─────────────────────────────────────────────
--  Internal helpers (run at obfuscation time)
-- ─────────────────────────────────────────────

local function shuffleWithMapping(t)
    local n = #t
    local order = {}
    for i = 1, n do order[i] = i end
    for i = n, 2, -1 do
        local j = math.random(i)
        order[i], order[j] = order[j], order[i]
    end
    local shuffled = {}
    local remap = {}
    for newIdx, oldIdx in ipairs(order) do
        shuffled[newIdx] = t[oldIdx]
        remap[oldIdx] = newIdx
    end
    return shuffled, remap
end

local function generatePoolName()
    return GenerateRandomName(VariableLength or 12)
end

local function generateKey()
    return math.random(100000, 999999999)
end

-- Expresses a key as a random math expression
-- Uses one of five strategies to keep variety in the output.
-- All strategies work with keys up to ~10^9 without precision loss.
local function obfuscateKey(k)
    local strategy = math.random(1, 5)

    if strategy == 1 then
        -- (a + b)  where a + b = k, a > b
        local a = math.random(math.floor(k / 2) + 1, k - 1)
        local b = k - a
        return string.format("(0x%x+0x%x)", a, b)
    elseif strategy == 2 then
        -- (a - b)  where a = k + b  => a > k
        local b = math.random(1, 50000)
        local a = k + b
        return string.format("(0x%x-0x%x)", a, b)
    elseif strategy == 3 then
        -- (a * b ± c)  where a * b ± c = k
        local a = math.random(100, math.min(9999, k))
        local b = math.max(2, math.min(9999, math.floor(k / a)))
        local product = a * b
        if product <= k then
            local c = k - product
            if c == 0 then
                return string.format("(0x%x*0x%x)", a, b)
            end
            return string.format("(0x%x*0x%x+0x%x)", a, b, c)
        else
            local c = product - k
            return string.format("(0x%x*0x%x-0x%x)", a, b, c)
        end
    elseif strategy == 4 then
        -- (a + b - c)  where a + b - c = k
        -- a > k ensures c = a + b - k is always positive
        local a = math.random(k + 1000, k + 50000)
        local b = math.random(1, 500)
        local c = a + b - k
        return string.format("(0x%x+0x%x-0x%x)", a, b, c)
    else
        -- (a + b + c - d)  where a + b + c - d = k
        local a = math.random(1, 1000)
        local b = math.random(1, 1000)
        local c = math.random(1, 1000)
        if a + b + c >= k then
            local d = a + b + c - k
            return string.format("(0x%x+0x%x+0x%x-0x%x)", a, b, c, d)
        else
            local d = k - a - b - c
            return string.format("(0x%x+0x%x+0x%x+0x%x)", a, b, c, d)
        end
    end
end

-- Portable bitwise XOR (works in all Lua versions)
local function xorInt(a, b)
    local result = 0
    local bit = 1
    while a > 0 or b > 0 do
        if a % 2 ~= b % 2 then result = result + bit end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bit = bit * 2
    end
    return result
end

-- Encrypts content bytes using a stream-cipher approach:
--   - Each byte position derives a unique key from the seed
--   - Operation (XOR vs ADD) alternates based on position
--   - Strings and numbers use different key-derivation constants
--     to match their respective runtime decoders
local function encryptString(content, key, mode)
    local mulConst, addConst, usePos
    if mode == "num" then
        mulConst = 23
        addConst = 13
        usePos   = false
    else
        mulConst = 31
        addConst = 17
        usePos   = true
    end

    local contentBytes = {}
    local i = 1
    while i <= #content do
        local byte
        if content:sub(i, i) == '\\' then
            local numStr = content:match("^(%d%d?%d?)", i + 1)
            if numStr then
                byte = tonumber(numStr)
                i = i + 1 + #numStr
            else
                byte = content:byte(i)
                i = i + 1
            end
        else
            byte = content:byte(i)
            i = i + 1
        end
        table.insert(contentBytes, byte)
    end

    local k1 = key % 65521
    local k2 = math.floor(key / 65521) % 65521
    local result = ""
    for pos, byte in ipairs(contentBytes) do
        local ki
        if mode == "num" then
            ki = ((k1 * 23 + k2 * 13 + pos * 7) % 255) + 1
        else
            ki = ((k1 * 31 + k2 * 17 + pos * 13) % 255) + 1
        end

        local encrypted
        if mode == "num" then
            if pos % 2 == 1 then
                encrypted = (byte + ki) % 256
            else
                encrypted = xorInt(byte, ki)
            end
        else
            if pos % 2 == 1 then
                encrypted = xorInt(byte, ki)
            else
                encrypted = xorInt((byte + ki) % 256, pos)
            end
        end
        result = result .. string.format("\\%03d", encrypted)
    end
    return '"' .. result .. '"'
end

-- ─────────────────────────────────────────────
--  Code generators for the embedded runtime
-- ─────────────────────────────────────────────

-- Self-contained string-decode function.
-- Inlines the XOR helper and derives a per-byte key from the seed.
-- Decryption matches the "str" mode of encryptString.
local function buildDecodeStr(dsName)
    return string.format(
        "local %s=function(s,k)local function x(a,b)local r,m=0,1 while a>0 or b>0 do if a%%2~=b%%2 then r=r+m end a=math.floor(a/2)b=math.floor(b/2)m=m*2 end return r end local i=0 local k1=k%%65521;local k2=math.floor(k/65521)%%65521;return s:gsub(\".\",function(c)i=i+1 local ki=((k1*31+k2*17+i*13)%%255)+1 local cb=c:byte() if i%%2==1 then return string.char(x(cb,ki))else return string.char((x(cb,i)-ki+256)%%256)end end)end;",
        dsName
    )
end

-- Self-contained number-decode function.
-- Uses a different key-derivation formula, inverted operation order,
-- and different variable names for the XOR helper to avoid identical
-- sub-strings with the string decoder.
local function buildDecodeNum(dnName)
    return string.format(
        "local %s=function(s,k)local function w(u,v)local p,q=0,1 while u>0 or v>0 do if u%%2~=v%%2 then p=p+q end u=math.floor(u/2)v=math.floor(v/2)q=q*2 end return p end local i=0 local k1=k%%65521;local k2=math.floor(k/65521)%%65521;return s:gsub(\".\",function(c)i=i+1 local ki=((k1*23+k2*13+i*7)%%255)+1 local cb=c:byte() if i%%2==1 then return string.char((cb-ki+256)%%256)else return string.char(w(cb,ki))end end)end;",
        dnName
    )
end

-- ─────────────────────────────────────────────
--  Public API
-- ─────────────────────────────────────────────

function GetPoolName()
    return currentPoolName
end

function AddToPool(value)
    if not constantMap[value] then
        table.insert(constants, value)
        constantMap[value] = #constants
        entryKeys[#constants] = generateKey()
    end
    return constantMap[value]
end

function CreateConstantPool(fullCode)
    constants       = {}
    constantMap     = {}
    entryKeys       = {}
    currentPoolName = generatePoolName()

    -- Each decoder is self-contained (no separate xor helper needed)
    local dsName    = generatePoolName()
    local dnName    = generatePoolName()

    -- Collect all strings and small hex literals into the pool
    -- Hex values > 2^53 (13+ significant hex digits) are skipped because
    -- Lua 5.1 doubles can't represent them precisely
    fullCode:gsub('"(.-)"', function(str)
        AddToPool('"' .. str .. '"')
    end)
    -- A trailing `.`/`p`/`P` means this `0x…` is actually a hex FLOAT (0x1p4,
    -- 0x1.8, 0xA.8); the `%x+` only grabbed its integer part, so pooling it would
    -- split the literal. Skip those. (An empty trailing capture is the normal
    -- hex-int case; a single `.` of a `..` concat is also safely skipped.)
    fullCode:gsub("([^%w_])(0x%x+)([pP.]?)", function(before, hex, trail)
        if trail == "p" or trail == "P" or trail == "." then return end
        local hexBody = hex:match("^0[xX]([0-9a-fA-F]+)$")
        if hexBody then
            local sigHex = hexBody:match("^0*(.+)$")
            if sigHex and #sigHex > 13 then
                return
            end
        end
        AddToPool(hex)
    end)

    if #constants == 0 then return fullCode end

    -- Build encrypted pool entries
    local encryptedEntries = {}
    for i, value in ipairs(constants) do
        local key    = entryKeys[i]
        local obfKey = obfuscateKey(key)

        if value:sub(1, 1) == '"' then
            local content   = value:sub(2, -2)
            local encrypted = encryptString(content, key, "str")
            local entry     = dsName .. "(" .. encrypted .. "," .. obfKey .. ")"
            -- ~20 % chance: wrap in an IIFE to break structural patterns
            if math.random() < 0.2 then
                entry = "((function()return " .. entry .. "end)())"
            end
            table.insert(encryptedEntries, entry)
        else
            local numAsStr  = tostring(tonumber(value))
            local encrypted = encryptString(numAsStr, key, "num")
            local entry     = "tonumber((" .. dnName .. "(" .. encrypted .. "," .. obfKey .. ")))"
            if math.random() < 0.2 then
                entry = "tonumber(((function()return " .. dnName .. "(" .. encrypted .. "," .. obfKey .. ")end)()))"
            end
            table.insert(encryptedEntries, entry)
        end
    end

    -- Shuffle entries; remap[oldIdx] = newIdx
    local shuffled, remap = shuffleWithMapping(encryptedEntries)

    -- ─────────────────────────────────────────────
    --  Junk entries: fake pool entries appended at the
    --  end.  They are never referenced by the code but
    --  look identical to real entries, bloating the
    --  pool and confusing static analysis.
    -- ─────────────────────────────────────────────
    if #shuffled > 0 then
        local minPct = JunkPoolRatioMin or 30
        local maxPct = JunkPoolRatioMax or 60
        local junkCount = math.max(2, math.floor(#shuffled * (math.random(minPct, maxPct) / 100)))
        for j = 1, junkCount do
            local junkEntry
            if math.random() < 0.5 then
                local fakeStr = {}
                for k = 1, math.random(3, 20) do
                    local r = math.random(1, 62)
                    if r <= 26 then fakeStr[k] = string.char(64 + r)
                    elseif r <= 52 then fakeStr[k] = string.char(70 + r)
                    else fakeStr[k] = string.char(47 + r) end
                end
                fakeStr = table.concat(fakeStr)
                local fk = generateKey()
                local fe = encryptString(fakeStr, fk, "str")
                local fkObf = obfuscateKey(fk)
                junkEntry = dsName .. "(" .. fe .. "," .. fkObf .. ")"
                if math.random() < 0.2 then
                    junkEntry = "((function()return " .. junkEntry .. "end)())"
                end
            else
                local fakeNum = math.random(0, 999999)
                local fakeNumStr = tostring(fakeNum)
                local fk = generateKey()
                local fe = encryptString(fakeNumStr, fk, "num")
                local fkObf = obfuscateKey(fk)
                junkEntry = "tonumber((" .. dnName .. "(" .. fe .. "," .. fkObf .. ")))"
                if math.random() < 0.2 then
                    junkEntry = "tonumber(((function()return " .. dnName .. "(" .. fe .. "," .. fkObf .. ")end)()))"
                end
            end
            table.insert(shuffled, junkEntry)
        end
    end

    local result = fullCode

    -- Replace all string literals in code with pool accesses
    result = result:gsub('"(.-)"', function(str)
        local oldIdx = constantMap['"' .. str .. '"']
        if not oldIdx or not remap[oldIdx] then return '"' .. str .. '"' end
        return currentPoolName .. "[" .. remap[oldIdx] .. "]"
    end)

    -- Replace all hex literals in code with pool accesses
    result = result:gsub("([^%w_])(0x%x+)([pP.]?)", function(before, hex, trail)
        if trail == "p" or trail == "P" or trail == "." then return before .. hex .. trail end
        local oldIdx = constantMap[hex]
        if not oldIdx or not remap[oldIdx] then return before .. hex end
        return before .. currentPoolName .. "[" .. remap[oldIdx] .. "]" .. trail
    end)

    -- Assemble final output:
    --   1. String-decode function  (self-contained, stream cipher)
    --   2. Number-decode function  (self-contained, different formula)
    --   3. Pool table  (shuffled, fully encrypted)
    --   4. Transformed source code
    local header  = buildDecodeStr(dsName) .. buildDecodeNum(dnName)
    local poolDef = "local " .. currentPoolName .. "={" .. table.concat(shuffled, ",") .. "};"

    return header .. poolDef .. result
end

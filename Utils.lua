function SplitCodeSegments(code)
    local segments = {}
    local pos = 1
    local len = #code
    local currentNonString = ""

    while pos <= len do
        local char = code:sub(pos, pos)

        if char == '"' or char == "'" then
            table.insert(segments, { isString = false, text = currentNonString })
            currentNonString = ""

            local quote = char
            local strStart = pos
            pos = pos + 1
            while pos <= len do
                local c = code:sub(pos, pos)
                if c == '\\' then
                    pos = pos + 2
                elseif c == quote then
                    pos = pos + 1
                    break
                else
                    pos = pos + 1
                end
            end
            table.insert(segments, { isString = true, text = code:sub(strStart, pos - 1) })

        elseif char == '-' and code:sub(pos, pos + 1) == '--' then
            currentNonString = currentNonString .. "--"
            pos = pos + 2
            local eqMatch = code:match("^%[(=*)%[", pos)
            if eqMatch then
                local endPattern = "]" .. eqMatch .. "]"
                local _, endIdx = code:find(endPattern, pos + #eqMatch + 2, true)
                if endIdx then
                    currentNonString = currentNonString .. code:sub(pos, endIdx)
                    pos = endIdx + 1
                else
                    currentNonString = currentNonString .. code:sub(pos)
                    pos = len + 1
                end
            else
                local _, lineEnd = code:find("[\r\n]", pos)
                if lineEnd then
                    currentNonString = currentNonString .. code:sub(pos, lineEnd)
                    pos = lineEnd + 1
                else
                    currentNonString = currentNonString .. code:sub(pos)
                    pos = len + 1
                end
            end

        elseif char == '[' then
            local eqMatch = code:match("^%[(=*)%[", pos)
            if eqMatch then
                table.insert(segments, { isString = false, text = currentNonString })
                currentNonString = ""
                local endPattern = "]" .. eqMatch .. "]"
                local _, endIdx = code:find(endPattern, pos + #eqMatch + 2, true)
                if endIdx then
                    table.insert(segments, { isString = true, text = code:sub(pos, endIdx) })
                    pos = endIdx + 1
                else
                    table.insert(segments, { isString = true, text = code:sub(pos) })
                    pos = len + 1
                end
            else
                currentNonString = currentNonString .. char
                pos = pos + 1
            end

        else
            currentNonString = currentNonString .. char
            pos = pos + 1
        end
    end

    if currentNonString ~= "" then
        table.insert(segments, { isString = false, text = currentNonString })
    end

    return segments
end

function ProcessOutsideStrings(code, fn)
    local segments = SplitCodeSegments(code)
    local result = {}
    for _, seg in ipairs(segments) do
        if seg.isString then
            table.insert(result, seg.text)
        else
            table.insert(result, (fn(seg.text)))
        end
    end
    return table.concat(result)
end

-- Build-time 32-bit arithmetic for the anti-tamper layer, written to be correct
-- on BOTH native Lua (64-bit integers) and hosts whose Lua integers are only
-- 32-bit (e.g. fengari-web in the browser: LUA_MAXINTEGER == 2^31-1). On such a
-- host any value in [2^31, 2^32) — which the FNV hash, LCG state and key all
-- span — cannot be an integer and becomes a float, so the native `*`, `% 2^32`
-- and bitwise operators (`~ >> & << |`) all break on it. We therefore do
-- EVERYTHING with plain float arithmetic kept exact (every intermediate < 2^53):
-- modulo/shift/mask via `% / *`, XOR via the helpers below, and we format 32-bit
-- values with `%.0f` (not `%d`, which demands an integer subtype). All of this is
-- provably bit-identical to the old `(a*b)%2^32` / `~` / `%d` forms on native, so
-- native output is byte-unchanged. Only used at BUILD time; the emitted load-time
-- Lua keeps the plain `*`/`%`/`>>` form (it runs on a real 64-bit interpreter).

-- 32-bit XOR via an 8-bit lookup table built once (no native bitwise operator).
local XOR8
local function xor8(a, b)
    if not XOR8 then
        XOR8 = {}
        for x = 0, 255 do
            local row = x * 256
            for y = 0, 255 do
                local r, p, xi, yi = 0, 1, x, y
                for _ = 1, 8 do
                    local xb, yb = xi % 2, yi % 2
                    if xb ~= yb then r = r + p end
                    xi = (xi - xb) / 2; yi = (yi - yb) / 2; p = p * 2
                end
                XOR8[row + y] = r
            end
        end
    end
    return XOR8[a * 256 + b]
end

-- Full 32-bit XOR (for key material; called only a handful of times per build).
local function axor(a, b)
    a = a % 4294967296; b = b % 4294967296
    local hi = xor8((a - a % 16777216) / 16777216, (b - b % 16777216) / 16777216) * 16777216
    local m2 = xor8((a // 65536) % 256, (b // 65536) % 256) * 65536
    local m1 = xor8((a // 256) % 256, (b // 256) % 256) * 256
    local lo = xor8(a % 256, b % 256)
    return hi + m2 + m1 + lo
end

-- (a * b) mod 2^32 with no intermediate exceeding ~2^48 (so it is exact even when
-- numbers are IEEE doubles, where `a * big` would otherwise lose low bits).
local function atMulMod32(a, b)
    a = a % 4294967296
    local ahi = (a - a % 65536) / 65536
    local alo = a % 65536
    local lo  = (alo * b) % 4294967296
    local hi  = ((ahi * b) % 65536) * 65536
    return (lo + hi) % 4294967296
end

-- FNV-1a-style 32-bit checksum. Used both at build time (here) and, as emitted
-- Lua below, at load time — they must stay byte-for-byte equivalent.
local function tamperChecksum(s)
    local h = 2166136261
    for i = 1, #s do
        h = (h - h % 256) + xor8(h % 256, string.byte(s, i)) -- XOR affects only the low byte
        h = atMulMod32(h, 16777619)
    end
    return h
end

-- Emit `core` as a single double-quoted Lua string literal using `\ddd` decimal
-- escapes for every byte. The lexer decodes this into the final string constant
-- at parse time, so the payload needs no runtime reconstruction (unlike the old
-- table.concat({string.char(...)}) form, which built it with many calls + a
-- concat on every startup). Handles arbitrary bytes, including NUL and newlines.
local function byteStringLiteral(core)
    local buf = {}
    for i = 1, #core do
        local b = string.byte(core, i)
        -- Printable ASCII (except " and \) goes in literally — 1 byte instead of
        -- a 4-char \ddd escape — so random ciphertext stays compact and parses
        -- fast. Everything else uses a fixed-width \ddd escape (always 3 digits,
        -- so a following literal digit can never extend it).
        if b >= 32 and b <= 126 and b ~= 34 and b ~= 92 then
            buf[i] = string.char(b)
        else
            buf[i] = string.format("\\%03d", b)
        end
    end
    return '"' .. table.concat(buf) .. '"'
end

-- Keystream cipher used at build time; the emitted Lua below must stay
-- byte-for-byte equivalent. 32-bit LCG state seeded by the key; each byte is
-- XORed with bits 16..23 of the advanced state. XOR makes decrypt == encrypt.
local function atRand32()
    -- (hi << 16) | lo, done as arithmetic (the halves don't overlap).
    return math.random(0, 65535) * 65536 + math.random(0, 65535)
end

-- Express a 32-bit value as `(a ~ b ~ c)` with random a,b so the stored key
-- material is not a recognizable magic number in the output.
local function atSplitXor(v)
    local a = atRand32()
    local b = atRand32()
    local c = axor(axor(v, a), b)
    -- %.0f, not %d: c/a/b can exceed 2^31 and have no integer subtype on a
    -- 32-bit-integer host, but print identically to %d for these exact values.
    return string.format("(%.0f ~ %.0f ~ %.0f)", a, b, c)
end

local function atCipher(s, key)
    local state = key % 4294967296
    local out = {}
    for i = 1, #s do
        state = (atMulMod32(state, 1103515245) + 12345) % 4294967296
        local kb = ((state - state % 65536) / 65536) % 256  -- bits 16..23, via arithmetic
        out[i] = string.char(xor8(string.byte(s, i), kb))
    end
    return table.concat(out)
end

function AddAntiTamper(code)
    local banner, core = code:match("^(%-%-%[%[.-%]%])(.*)$")
    if not banner then return code end

    -- Bind the integrity check to execution: the payload is encrypted, and the
    -- key is recovered ONLY from the checksum of the (unmodified) ciphertext.
    --   Kp = K XOR hash(ciphertext)   is stored;   K = Kp XOR hash(ciphertext).
    -- Editing the payload changes its hash -> wrong key -> decrypt yields garbage
    -- -> load() fails. The check cannot be stripped: its output IS the key.
    local K      = atRand32()
    local cipher = atCipher(core, K)
    local hC     = tamperChecksum(cipher)
    local Kp     = axor(K, hC)
    local lit    = byteStringLiteral(cipher)

    local t = GenerateRandomName(6)  -- type
    local s = GenerateRandomName(6)  -- ciphertext payload
    local h = GenerateRandomName(6)  -- running hash
    local j = GenerateRandomName(6)  -- hash loop index
    local k = GenerateRandomName(6)  -- recovered key
    local st = GenerateRandomName(6) -- keystream state
    local c = GenerateRandomName(6)  -- per-byte char (gsub)
    local p = GenerateRandomName(6)  -- decrypted plaintext

    -- Environment validation, then: hash the ciphertext, recover the key from the
    -- hash, decrypt (gsub = one C-level pass, no per-byte table building), run.
    return banner ..
        "do local " .. t .. "=type if " .. t .. "(string)~=\"table\" or " .. t .. "(string.byte)~=\"function\" or " ..
        t .. "(math.floor)~=\"function\" or " .. t .. "(load)~=\"function\"then return end end;" ..
        "local " .. s .. "=" .. lit .. ";" ..
        "local " .. h .. "=2166136261;for " .. j .. "=1,#" .. s .. " do " ..
        h .. "=" .. h .. " ~ string.byte(" .. s .. "," .. j .. ");" ..
        h .. "=(" .. h .. "*16777619)%4294967296 end;" ..
        "local " .. k .. "=(" .. atSplitXor(Kp) .. " ~ " .. h .. ")%4294967296;" ..
        "local " .. st .. "=" .. k .. ";" ..
        "local " .. p .. "=" .. s .. ":gsub(\".\",function(" .. c .. ")" ..
        st .. "=(" .. st .. "*1103515245+12345)%4294967296;" ..
        "return string.char(string.byte(" .. c .. ") ~ ((" .. st .. ">>16)&255))end);" ..
        "load(" .. p .. ")()"
end

function GenerateRandomName(len)
    local charset = "abcdefghijklmnopqrstuvwxyz0123456789"
    local name = "_"
    for i = 1, len do
        local r = math.random(1, #charset)
        name = name .. charset:sub(r, r)
    end
    return name
end

function GenerateSecureSeed()
    if _G.Config and _G.Config.RandomSeed ~= nil then
        return _G.Config.RandomSeed | 0
    end

    local function toInt(n)
        if n then
            local i = math.tointeger(n)
            return i
        end
        return nil
    end

    local isWindows = package.config:sub(1, 1) == "\\"

    if not isWindows then
        -- Unix/macOS: read 4 bytes from the OS crypto RNG. This also avoids
        -- shelling out to powershell/wmic (which don't exist here and would print
        -- "not found" to stderr on every run).
        local ok, result = pcall(function()
            local f = io.open("/dev/urandom", "rb")
            if not f then return nil end
            local bytes = f:read(4)
            f:close()
            if not bytes or #bytes < 4 then return nil end
            local b1, b2, b3, b4 = bytes:byte(1, 4)
            return ((b1 * 256 + b2) * 256 + b3) * 256 + b4
        end)
        if ok then
            local n = toInt(result)
            if n then return n % 2147483647 + 1 end
        end
    else
        -- Method 1: PowerShell crypto RNG (Windows CNG) - 32-bit fits Lua integer exactly
        local ok, result = pcall(function()
            local cmd = 'powershell -Command "$buf = New-Object byte[] 4; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buf); [BitConverter]::ToUInt32($buf, 0)"'
            local f = io.popen(cmd, "r")
            if not f then return nil end
            local output = f:read("*a")
            f:close()
            return tonumber(output:match("%d+"))
        end)
        if ok then
            local n = toInt(result)
            if n then return n % 2147483647 + 1 end
        end

        -- Method 2: PowerShell Get-Random (uses Windows crypto as backing)
        ok, result = pcall(function()
            local f = io.popen('powershell -Command "Get-Random -Minimum 0 -Maximum 2147483647"', "r")
            if not f then return nil end
            local output = f:read("*a")
            f:close()
            return tonumber(output:match("%d+"))
        end)
        if ok then
            local n = toInt(result)
            if n then return n end
        end
    end

    -- Method 3: Fallback - mix all available low-entropy sources
    local seed = os.time() * 31337
    seed = seed + math.floor(os.clock() * 1e9)
    seed = seed + math.floor((os.time() * 13) % 9973) * 1000003

    for _, name in ipairs({"COMPUTERNAME", "USERNAME", "USERDOMAIN", "PROCESSOR_IDENTIFIER", "NUMBER_OF_PROCESSORS"}) do
        local val = os.getenv(name)
        if val then
            for i = 1, #val do
                seed = seed * 31337 + string.byte(val, i)
            end
        end
    end

    if isWindows then
        local f = io.popen("wmic os get localdatetime", "r")
        if f then
            local dt = f:read("*a")
            f:close()
            local ms = dt:match("(%d%d%d%d%d%d%d%d%d%d%d%d%d%d)")
            if ms then
                seed = seed * 31337 + tonumber(ms) % 1000000
            end
        end
    end

    local tmpname = os.tmpname()
    for i = 1, #tmpname do
        seed = seed * 31337 + string.byte(tmpname, i)
    end

    return math.abs(seed) % 2147483647 + 1 | 0
end
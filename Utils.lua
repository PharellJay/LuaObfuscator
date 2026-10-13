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

-- FNV-1a-style 32-bit checksum. Used both at build time (here) and, as emitted
-- Lua below, at load time — they must stay byte-for-byte equivalent.
local function tamperChecksum(s)
    local h = 2166136261
    for i = 1, #s do
        h = h ~ string.byte(s, i)
        h = (h * 16777619) % 4294967296
    end
    return h
end

function AddAntiTamper(code)
    local banner, core = code:match("^(%-%-%[%[.-%]%])(.*)$")
    if not banner then return code end

    -- Encode core as chunks of string.char (Lua register limit: ~200 args max)
    local CHUNK = 150
    local chunks = {}
    local i = 1
    while i <= #core do
        local part = {}
        for _ = 1, CHUNK do
            if i > #core then break end
            table.insert(part, string.byte(core, i))
            i = i + 1
        end
        table.insert(chunks, "string.char(" .. table.concat(part, ",") .. ")")
    end

    local expected = tamperChecksum(core)

    local t = GenerateRandomName(6)  -- type
    local s = GenerateRandomName(6)  -- reconstructed payload
    local h = GenerateRandomName(6)  -- running hash
    local j = GenerateRandomName(6)  -- loop index

    -- Environment validation, then an integrity self-check: recompute the
    -- checksum of the reconstructed payload and bail out silently if it does not
    -- match the build-time value, so beautifying or editing the payload breaks it.
    return banner ..
        "do local " .. t .. "=type if " .. t .. "(string)~=\"table\" or " .. t .. "(string.byte)~=\"function\" or " ..
        t .. "(math.floor)~=\"function\" or " .. t .. "(load)~=\"function\"then return end end;" ..
        "local " .. s .. "=table.concat({" .. table.concat(chunks, ",") .. "});" ..
        "local " .. h .. "=2166136261;for " .. j .. "=1,#" .. s .. " do " ..
        h .. "=" .. h .. " ~ string.byte(" .. s .. "," .. j .. ");" ..
        h .. "=(" .. h .. "*16777619)%4294967296 end;" ..
        "if " .. h .. "~=" .. expected .. " then return end;" ..
        "load(" .. s .. ")()"
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

    local f = io.popen("wmic os get localdatetime", "r")
    if f then
        local dt = f:read("*a")
        f:close()
        local ms = dt:match("(%d%d%d%d%d%d%d%d%d%d%d%d%d%d)")
        if ms then
            seed = seed * 31337 + tonumber(ms) % 1000000
        end
    end

    local tmpname = os.tmpname()
    for i = 1, #tmpname do
        seed = seed * 31337 + string.byte(tmpname, i)
    end

    return math.abs(seed) % 2147483647 + 1 | 0
end
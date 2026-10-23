-- Simulate XOR for Lua 5.1 (no bit32)
local function xor(a, b)
    local r, p = 0, 1
    while a > 0 or b > 0 do
        if a % 2 ~= b % 2 then r = r + p end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        p = p * 2
    end
    return r
end

-- Encode `bytes` as a self-decoding expression. In addition to the per-string
-- XOR key, each plaintext byte is shifted by a CHUNK-LEVEL seed (`seedVar`, value
-- `seedVal`) before encryption and un-shifted on decode. The seed is not a literal
-- in the output — it is produced by a runtime loop (see ObfuscateAllStrings) — so a
-- single decode expression is no longer independently constant-foldable: an offline
-- folder / one-shot LLM must first evaluate the shared seed to recover ANY string,
-- instead of folding each IIFE in isolation. Only `+ - %` are used (no native
-- bitwise, no value exceeds 255 here), so it is exact under 64-bit Lua AND 32-bit
-- Fengari. (Honest ceiling: a full evaluator can still run the seed loop; this
-- defeats naive constant-folding and raises the bar on automated/LLM extraction.)
function ToXor(bytes, seedVal, seedVar)
    seedVal = seedVal or 0
    seedVar = seedVar or "0"
    local key = math.random(100000, 999999999)
    local enc = {}
    for _, b in ipairs(bytes) do
        table.insert(enc, xor((b + seedVal) % 256, key))
    end
    local encStr = table.concat(enc, ",")
    local src = '(function(k'
    for i = 1, #bytes do
        src = src .. ',e' .. i
    end
    src = src .. ')local function x(a,b)local r,p=0,1 while a>0 or b>0 do if a%2~=b%2 then r=r+p end a=math.floor(a/2)b=math.floor(b/2)p=p*2 end return r end;return string.char((x(e1,k)-' .. seedVar .. ')%256'
    for i = 2, #bytes do
        src = src .. ',(x(e' .. i .. ',k)-' .. seedVar .. ')%256'
    end
    src = src .. ')end)(' .. key .. ',' .. encStr .. ')'
    return src
end

-- Variant B: a helper-free ADDITIVE cipher with a running position term. No `x`
-- xor function at all, so its body looks nothing like ToXor; a devirtualizer
-- can't match one decoder template across the whole program. Uses only `+ - %`
-- (all values kept in [0,255] by the %256), so it is exact on 64-bit Lua AND
-- 32-bit Fengari. The chunk seed is still mixed in, so it is not independently
-- constant-foldable either.
function ToAdd(bytes, seedVal, seedVar)
    seedVal = seedVal or 0
    seedVar = seedVar or "0"
    local key = math.random(1, 255)
    local enc = {}
    for i, b in ipairs(bytes) do
        enc[i] = (b + seedVal + key + i * 7) % 256
    end
    local src = '(function(k'
    for i = 1, #bytes do src = src .. ',e' .. i end
    src = src .. ')return string.char('
    local terms = {}
    for i = 1, #bytes do
        terms[i] = '(e' .. i .. '-k-' .. seedVar .. '-' .. (i * 7) .. ')%256'
    end
    src = src .. table.concat(terms, ',') .. ')end)(' .. key .. ',' .. table.concat(enc, ',') .. ')'
    return src
end

-- Variant C: same XOR scheme as ToXor, but the plaintext is assembled through a
-- table + table.concat instead of a single multi-argument string.char call, so
-- the decoder's shape differs again.
function ToXorTable(bytes, seedVal, seedVar)
    seedVal = seedVal or 0
    seedVar = seedVar or "0"
    local key = math.random(100000, 999999999)
    local enc = {}
    for _, b in ipairs(bytes) do
        table.insert(enc, xor((b + seedVal) % 256, key))
    end
    local src = '(function(k'
    for i = 1, #bytes do src = src .. ',e' .. i end
    src = src .. ')local function x(a,b)local r,p=0,1 while a>0 or b>0 do if a%2~=b%2 then r=r+p end a=math.floor(a/2)b=math.floor(b/2)p=p*2 end return r end local t={}'
    for i = 1, #bytes do
        src = src .. 't[' .. i .. ']=string.char((x(e' .. i .. ',k)-' .. seedVar .. ')%256)'
    end
    src = src .. ' return table.concat(t)end)(' .. key .. ',' .. table.concat(enc, ',') .. ')'
    return src
end

local function EmptyString()
    if math.random(0, 1) == 1 then
        return '""'
    else
        return "''"
    end
end

-- Several structurally distinct decoders; one is picked per string at random so
-- no single template matches every obfuscated literal in the output.
local strategies = {
    { name = "xor",      fn = ToXor },
    { name = "add",      fn = ToAdd },
    { name = "xortable", fn = ToXorTable },
}

function ObfuscateAllStrings(fullCode)
    local segments = SplitCodeSegments(fullCode)
    local result = {}

    -- Decode-once pool. Each distinct string literal is encoded ONCE into this
    -- chunk-level table, which is evaluated a single time when it is declared at
    -- load; every use site becomes a cheap `POOL[idx]` table access instead of
    -- the inline decode expression. This matters enormously for strings that
    -- appear inside loops: previously the self-contained decode IIFE was emitted
    -- verbatim at each use and re-ran (closure build + per-byte XOR) on every
    -- iteration. The encoding itself is unchanged, so obfuscation strength is the
    -- same — only the evaluation count drops from per-use to once. Safe to hoist
    -- because every decode expression is self-contained (its only inputs are
    -- literal constants, no captured locals).
    local poolName = GenerateRandomName(VariableLength or 12)
    local pool = {}        -- list of decode expressions (pool entries)
    local poolIndex = {}   -- original literal text -> pool slot (dedup)

    -- Chunk-level decode seed that binds every string's decode to a value produced
    -- at load by a loop (NOT a literal), so no single decode expression folds on its
    -- own. Build-time `seedVal` is recomputed bit-for-bit by the emitted loop below;
    -- all arithmetic stays in [0,255] (Fengari-safe, no overflow, no native bitwise).
    local seedVar = GenerateRandomName(VariableLength or 12)
    local sN = math.random(8, 24)
    local sC = math.random(1, 255)
    local seedVal = 0
    for i = 1, sN do seedVal = (seedVal + i * sC) % 256 end

    local function intern(originalText, expr)
        local idx = poolIndex[originalText]
        if not idx then
            pool[#pool + 1] = expr
            idx = #pool
            poolIndex[originalText] = idx
        end
        return poolName .. "[" .. idx .. "]"
    end

    for _, seg in ipairs(segments) do
        if seg.isString then
            local text = seg.text
            local first = text:sub(1, 1)

            if first == '"' or first == "'" then
                local content = text:sub(2, -2)
                if #content == 0 then
                    table.insert(result, EmptyString())
                else
                    local actualStr = load("return " .. text)()
                    local bytes = {}
                    for i = 1, #actualStr do
                        table.insert(bytes, actualStr:byte(i))
                    end
                    local strategy = strategies[math.random(1, #strategies)]
                    table.insert(result, intern(text, strategy.fn(bytes, seedVal, seedVar)))
                end

            else
                -- Level-aware long-string extraction. The old lazy regex
                -- `%[=*%[(.-)%]=*%]` stopped at the first `]]` and ignored the
                -- `=` level, truncating any long string whose body contains `]]`
                -- (e.g. `[==[has ]] inside]==]`). `text` is exactly one long
                -- string literal, so slice off the opener/closer by their level.
                local eq = text:match("^%[(=*)%[")
                local content = nil
                if eq then
                    local n = #eq
                    content = text:sub(n + 3, #text - (n + 2))
                    -- Lua strips a single newline immediately after the opener.
                    if content:sub(1, 2) == "\r\n" or content:sub(1, 2) == "\n\r" then
                        content = content:sub(3)
                    elseif content:sub(1, 1) == "\n" or content:sub(1, 1) == "\r" then
                        content = content:sub(2)
                    end
                end
                if content then
                    if #content == 0 then
                        table.insert(result, EmptyString())
                    else
                        local bytes = {}
                        for i = 1, #content do
                            table.insert(bytes, content:byte(i))
                        end
                        local strategy = strategies[math.random(1, #strategies)]
                        table.insert(result, intern(text, strategy.fn(bytes, seedVal, seedVar)))
                    end
                else
                    table.insert(result, text)
                end
            end
        else
            table.insert(result, seg.text)
        end
    end

    local body = table.concat(result)
    if #pool == 0 then return body end

    -- Declare the pool as the very first statement so it is in scope (as a chunk
    -- local / upvalue) for every use below, including inside the VM interpreter
    -- function and nested closures.
    -- The seed loop is declared before the pool so it is in scope for every decode
    -- expression (which reference seedVar as an upvalue). Computed once at load.
    local seedDef = "local " .. seedVar .. "=(function() local a=0 for b=1," .. sN ..
        " do a=(a+b*" .. sC .. ")%256 end return a end)();"
    local poolDef = "local " .. poolName .. "={" .. table.concat(pool, ",") .. "};"
    return seedDef .. poolDef .. body
end
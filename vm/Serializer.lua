-- vm/Serializer.lua
--
-- Turns a compiled proto (from vm/Compiler.lua) into a Lua table-constructor
-- SOURCE string that the generated interpreter consumes, e.g.
--   {np=2,code={4,0,4,1,11,28,0},k={}}
--
-- Constants are emitted with string.format("%q", v), which round-trips numbers
-- (preserving integer vs. float) and strings (with correct escaping) for Lua
-- 5.3+. The resulting source then flows through the normal number/string/pool
-- text passes, so the blob is further obfuscated for free.
--
-- Per-build opcode permutation and constant encryption are planned hardening
-- (plan step 4); the structure here keeps them a localized change.

-- Symmetric byte-XOR keystream (same routine encrypts and decrypts). The
-- interpreter reconstructs the identical stream from the same seed to recover
-- the plaintext at proto load. Keeps string constants out of the blob in clear.
function VMXorCrypt(s, seed)
    local k = seed % 256
    local t = {}
    for i = 1, #s do
        k = (k * 31 + 7) % 256
        t[i] = string.char(string.byte(s, i) ~ k)
    end
    return table.concat(t)
end

-- String and number constants are both stored XOR-encrypted, with a one-byte
-- type tag so the interpreter can reconstruct them at load: "\0" = string,
-- "\1" = number (its exact %q literal, recovered via tonumber). This keeps a
-- virtualized function's literal secrets out of the blob even with no downstream
-- number/string passes. Booleans/nil aren't secrets and are left plain.
local function serializeConst(v, seed)
    local t = type(v)
    if t == "string" then
        return string.format("%q", VMXorCrypt("\0" .. v, seed))
    elseif t == "number" then
        return string.format("%q", VMXorCrypt("\1" .. string.format("%q", v), seed))
    elseif t == "boolean" then
        return tostring(v)
    elseif t == "nil" then
        return "nil"
    end
    error("VM serializer: cannot serialize constant of type " .. t)
end

function SerializeProto(proto, seed)
    seed = seed or 0
    local codeParts = {}
    for i = 1, #proto.code do codeParts[i] = tostring(proto.code[i]) end

    local kParts = {}
    for i = 1, #proto.k do kParts[i] = serializeConst(proto.k[i], seed) end

    local pParts = {}
    for i = 1, #(proto.p or {}) do pParts[i] = SerializeProto(proto.p[i], seed) end

    -- upvalue capture descriptors: {l=<parent cell id>} or {u=<parent upvalue idx>}
    local upParts = {}
    for i = 1, #(proto.up or {}) do
        local d = proto.up[i]
        if d.l ~= nil then upParts[i] = "{l=" .. d.l .. "}" else upParts[i] = "{u=" .. d.u .. "}" end
    end

    return string.format(
        "{np=%d,va=%d,code={%s},k={%s},p={%s},up={%s}}",
        proto.np,
        proto.va or 0,
        table.concat(codeParts, ","),
        table.concat(kParts, ","),
        table.concat(pParts, ","),
        table.concat(upParts, ",")
    )
end

-- Security-assertion harness for the Deadeye obfuscator.
--
-- Unlike run_tests.lua (which proves behavior parity), this script checks the
-- SECURITY properties of the output:
--   1. Secret leakage  — a known plaintext secret must NOT survive in the output.
--   2. Correctness     — the obfuscated program must still produce the secret at runtime.
--   3. Tamper response — flipping bytes in the anti-tamper payload must BREAK
--                        execution (the secret must never print from a tampered file).
--
-- Usage:   lua security_check.lua          (uses `lua` for child runs; LUA_BIN overrides)
-- Exit 0 if every assertion holds, 1 otherwise.

SUPPRESS_MAIN_DRIVER = true
dofile("Main.lua")

local LUA_BIN = os.getenv("LUA_BIN") or "lua"
local TMP = os.getenv("TMPDIR") or "/tmp"

-- Distinct, unlikely-to-collide secrets (string + numeric).
local SECRET_STR = "D3ADEYE_SECRET_PAYLOAD_7FF13"
local SECRET_NUM = "8675309314"
local SRC = ([[
local token = "%s"
local magic = %s
local function check() return token .. ":" .. magic end
print(check())
]]):format(SECRET_STR, SECRET_NUM)
local EXPECT = SECRET_STR .. ":" .. SECRET_NUM .. "\n"

local function writeFile(p, d) local f = assert(io.open(p, "wb")); f:write(d); f:close() end
local function run(path)
    local out = TMP .. "/deadeye_sec_" .. math.random(1, 1e9) .. ".out"
    os.execute(string.format('%q %q > %q 2>&1', LUA_BIN, path, out))
    local f = io.open(out, "rb"); local r = f and f:read("*a") or ""; if f then f:close() end
    os.remove(out)
    return r
end
local function obf(src)
    local real = print; _G.print = function() end
    local ok, res = pcall(Obfuscate, src); _G.print = real
    assert(ok, "obfuscation error: " .. tostring(res))
    return res
end

math.randomseed(os.time())
local failures = {}
local function assertion(name, ok, detail)
    io.write(("%-44s %s\n"):format(name, ok and "OK" or "FAIL"))
    if not ok then failures[#failures + 1] = name .. (detail and (" — " .. detail) or "") end
end

-- Run several builds so the checks aren't tied to one random seed.
for seed = 1, 6 do
    Config = Config or {}
    Config.RandomSeed = seed
    local output = obf(SRC)

    -- 1. No plaintext secret (string or numeric) in the output.
    assertion("seed " .. seed .. ": string secret absent",
        not output:find(SECRET_STR, 1, true))
    assertion("seed " .. seed .. ": numeric secret absent",
        not output:find(SECRET_NUM, 1, true))

    -- 2. Untampered output still produces the secret.
    local okPath = TMP .. "/deadeye_sec_ok_" .. seed .. ".lua"
    writeFile(okPath, output)
    local okRun = run(okPath)
    assertion("seed " .. seed .. ": runs correctly", okRun == EXPECT,
        okRun ~= EXPECT and ("got " .. okRun:gsub("%s+", " "):sub(1, 40)) or nil)
    os.remove(okPath)

    -- 3. Tampering must break execution: flip bytes at several positions in the
    --    back half (past the bootstrap, inside the ciphertext payload) and confirm
    --    the secret never prints from the mutated file.
    local leaked = false
    local n = #output
    for _, frac in ipairs({ 0.55, 0.7, 0.85, 0.95 }) do
        local i = math.max(1, math.floor(n * frac))
        local b = output:byte(i)
        -- flip to a different, still-printable byte so we test logic, not just a parse break
        local nb = (b == 65) and 66 or 65
        local mutated = output:sub(1, i - 1) .. string.char(nb) .. output:sub(i + 1)
        local tp = TMP .. "/deadeye_sec_tamper_" .. seed .. ".lua"
        writeFile(tp, mutated)
        local r = run(tp)
        os.remove(tp)
        if r:find(SECRET_STR, 1, true) then leaked = true end
    end
    assertion("seed " .. seed .. ": tamper does not leak secret", not leaked)
end

if #failures > 0 then
    print("\nSECURITY FAILURES:")
    for _, f in ipairs(failures) do print("  - " .. f) end
    os.exit(1)
end
print("\nAll security assertions passed.")
os.exit(0)

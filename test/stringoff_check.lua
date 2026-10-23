-- Regression check for the string-awareness bugs in the TEXT passes
-- (Minify, StringSplitter, ConstantPooling). These are masked in the default
-- pipeline because StringObf rewrites every user string literal before those
-- passes run, so they can only be exercised with StringObf OFF. The main
-- harness (run_tests.lua) uses one global config for all fixtures, so this
-- lives in its own script.
--
-- Usage:   lua test/stringoff_check.lua      (run from the repo root)
-- Exit code 0 when every case behaves identically to the original, 1 otherwise.

SUPPRESS_MAIN_DRIVER = true
dofile("Main.lua")

local LUA_BIN = os.getenv("LUA_BIN") or "lua"
local TMP = os.getenv("TMPDIR") or "/tmp"

local function run(src)
    local path = TMP .. "/soff_" .. math.random(1, 1e9) .. ".lua"
    local f = assert(io.open(path, "w")); f:write(src); f:close()
    local op = path .. ".out"
    os.execute(string.format('%q %q > %q 2>&1', LUA_BIN, path, op))
    local r = io.open(op); local out = r and r:read("*a") or ""; if r then r:close() end
    os.remove(path); os.remove(op)
    return out
end

local fails = 0
local function case(name, src, override)
    local passes = {}
    for k, v in pairs(Config.PRESETS.max) do passes[k] = v end
    for k, v in pairs(override) do passes[k] = v end
    Config.Passes = passes
    local real = print; _G.print = function() end
    local ok, obf = pcall(Obfuscate, src); _G.print = real
    if not ok then
        print(("%-26s FAIL (obfuscation error: %s)"):format(name, tostring(obf)))
        fails = fails + 1; return
    end
    local a, b = run(src), run(obf)
    if a == b then
        print(("%-26s OK"):format(name))
    else
        print(("%-26s FAIL\n  orig=[%s]\n  obf =[%s]"):format(name, a, b))
        fails = fails + 1
    end
end

-- Minify must not collapse whitespace/newlines inside string literals.
case("minify_string_literal", [[
print("a  ==  b")
print("x , y . z")
local s = [=[one
two   three]=]
print(s)
]], { StringObf = false, StringSplit = false })

-- StringSplitter must preserve the original quote style.
case("split_singlequote", [[
local s = 'He said "hello" to everyone, waving back warmly today friend'
print(s); print(#s)
]], { StringObf = false, StringSplit = true, ConstantPool = false, Minify = false })

-- ConstantPooling must not pool a "..." that lives inside a '...' literal.
case("pool_nested_quote", [[
local s = 'he said "hi there friend" and left the quiet little room'
print(s); print(#s)
]], { StringObf = false, StringSplit = false })

-- Full text-pass stack together, StringObf off.
case("all_text_passes", [[
local a = 'single "with" double and spaces  kept  here friend ok'
local b = "double 'with' single and a , comma . dot operator here"
print(a); print(b); print(#a + #b)
]], { StringObf = false })

if fails > 0 then
    print(("\n%d case(s) FAILED"):format(fails)); os.exit(1)
else
    print("\nAll string-awareness cases passed."); os.exit(0)
end

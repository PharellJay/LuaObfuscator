-- Round-trip correctness harness for the Deadeye obfuscator.
--
-- For every fixture it: runs the original under Lua, obfuscates the source,
-- runs the obfuscated output, and compares stdout + exit status. A fixture
-- PASSES only if the obfuscated program behaves identically to the original.
--
-- Usage:   lua run_tests.lua
-- The interpreter used for the child runs defaults to "lua"; override with
-- the LUA_BIN environment variable, e.g.  LUA_BIN=/path/to/lua lua run_tests.lua
--
-- Exit code is 0 when every fixture passes, 1 otherwise (CI-friendly).

SUPPRESS_MAIN_DRIVER = true
dofile("Main.lua") -- loads the pipeline and defines Obfuscate() without running the CLI driver

-- Opt-in: route expression emission through the ExprAST IR to validate it.
if os.getenv("USE_EXPR_AST") == "1" then
    USE_EXPR_AST = true
    print("[harness] USE_EXPR_AST enabled: emitting expressions via ExprAST IR")
end

-- Opt-in: virtualize EVERY eligible function (stress test), not just vm_-prefixed.
if os.getenv("VIRTUALIZE_ALL") == "1" then
    Config = Config or {}
    Config.VirtualizeAll = true
    print("[harness] VIRTUALIZE_ALL enabled: virtualizing all eligible functions")
end

-- Opt-in: exempt the spliced VM interpreter from dead-code/flattening.
if os.getenv("VM_LIGHTWEIGHT") == "1" then
    Config = Config or {}
    Config.VMLightweight = true
    print("[harness] VM_LIGHTWEIGHT enabled: interpreter skips dead-code/flatten")
end

-- Opt-in: validate a strength preset ("fast"/"max") across the whole suite.
if os.getenv("PRESET") then
    Config = Config or {}
    local name = os.getenv("PRESET")
    if Config.PRESETS and Config.PRESETS[name] then
        Config.Preset = name
        Config.Passes = Config.PRESETS[name]
        if name == "fast" then Config.VirtualizeAll = false end
        print("[harness] PRESET=" .. name .. " enabled")
    else
        print("[harness] unknown PRESET '" .. tostring(name) .. "', ignoring")
    end
end

local LUA_BIN = os.getenv("LUA_BIN") or "lua"

-- Fixtures: the comprehensive suite plus the targeted feature fixtures.
local FIXTURES = {
    "Input/testinput.lua",
    "Input/minitest.lua",
    "test/fixtures/closures.lua",
    "test/fixtures/varargs.lua",
    "test/fixtures/multiret.lua",
    "test/fixtures/metatables.lua",
    "test/fixtures/goto_labels.lua",
    "test/fixtures/coroutines.lua",
    "test/fixtures/expressions.lua",
    "test/fixtures/vm_basic.lua",
    "test/fixtures/vm_genfor.lua",
    "test/fixtures/vm_vararg.lua",
    "test/fixtures/vm_bitwise.lua",
    "test/fixtures/vm_nested_method.lua",
    "test/fixtures/vm_localfn.lua",
    "test/fixtures/vm_method_top.lua",
    "test/fixtures/vm_upvalref.lua",
    "test/fixtures/vm_closure.lua",
    "test/fixtures/vm_upval.lua",
    "test/fixtures/vm_coro.lua",
    "test/fixtures/parse_local.lua",
    "test/fixtures/bitwise.lua",
    "test/fixtures/scope_shadow.lua",
    "test/fixtures/cff_return.lua",
    "test/fixtures/cff_nested_return.lua",
    "test/fixtures/cff_internal_break.lua",
    "test/fixtures/cff_escaping_break.lua",
    "test/fixtures/vm_repeat.lua",
    "test/fixtures/vm_massign.lua",
    "test/fixtures/vm_goto.lua",
}

local TMP = os.getenv("TMPDIR") or "/tmp"

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local c = f:read("*a")
    f:close()
    return c
end

local function writeFile(path, data)
    local f = assert(io.open(path, "wb"))
    f:write(data)
    f:close()
end

-- Run a Lua script as a child process, capturing combined stdout/stderr and
-- the exit status. Shells out so the obfuscated file is executed exactly as a
-- user would run it (fresh interpreter state, no shared globals).
local function runScript(path)
    local outPath = TMP .. "/deadeye_run_" .. tostring(math.random(1, 1e9)) .. ".out"
    local cmd = string.format('%q %q > %q 2>&1', LUA_BIN, path, outPath)
    local ok, kind, code = os.execute(cmd)
    local out = readFile(outPath) or ""
    os.remove(outPath)
    -- Normalize os.execute return across Lua versions.
    local status
    if type(ok) == "number" then
        status = ok -- Lua 5.1
    else
        status = (kind == "exit") and code or (ok and 0 or 1)
    end
    return out, status
end

math.randomseed(os.time())

local passed, failed = 0, {}

for _, fixture in ipairs(FIXTURES) do
    io.write(("%-34s "):format(fixture))
    local src = readFile(fixture)
    if not src then
        io.write("SKIP (not found)\n")
    else
        -- 1. Baseline: run the original.
        local origOut, origStatus = runScript(fixture)

        -- 2. Obfuscate (in-process reuse of the real pipeline).
        local ok, obf = pcall(Obfuscate, src)
        if not ok then
            io.write("FAIL (obfuscation error)\n       " .. tostring(obf) .. "\n")
            failed[#failed + 1] = fixture
        else
            local obfPath = TMP .. "/deadeye_obf_" ..
                fixture:gsub("[^%w]", "_") .. ".lua"
            writeFile(obfPath, obf)

            -- 3. Run the obfuscated output and compare.
            local obfOut, obfStatus = runScript(obfPath)
            if obfOut == origOut and obfStatus == origStatus then
                io.write("PASS\n")
                passed = passed + 1
            else
                io.write("FAIL (behavior differs)\n")
                if obfStatus ~= origStatus then
                    io.write(("       exit: orig=%s obf=%s\n"):format(
                        tostring(origStatus), tostring(obfStatus)))
                end
                if obfOut ~= origOut then
                    local function lines(s)
                        local t = {}
                        for x in (s .. "\n"):gmatch("(.-)\n") do t[#t + 1] = x end
                        return t
                    end
                    local ol, bl = lines(origOut), lines(obfOut)
                    io.write("       --- first differing line ---\n")
                    for i = 1, math.max(#ol, #bl) do
                        if ol[i] ~= bl[i] then
                            io.write("       orig[" .. i .. "]: " .. tostring(ol[i]) .. "\n")
                            io.write("       obf [" .. i .. "]: " .. tostring(bl[i]) .. "\n")
                            break
                        end
                    end
                    io.write(("       (orig=%d bytes, obf=%d bytes)\n"):format(#origOut, #obfOut))
                end
                os.rename(obfPath, obfPath .. ".kept") -- keep failing output for inspection
                io.write("       kept obfuscated output: " .. obfPath .. ".kept\n")
                failed[#failed + 1] = fixture
            end
        end
    end
end

print(("\n%d passed, %d failed, %d total"):format(passed, #failed, #FIXTURES))
if #failed > 0 then
    print("FAILED: " .. table.concat(failed, ", "))
    os.exit(1)
end
os.exit(0)

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
    -- Edge/regression fixtures (added during the 2026-10 hardening audit).
    "test/fixtures/edge_funclit_return.lua",   -- §1a CFF terminal-statement miscount
    "test/fixtures/edge_nested_vararg.lua",    -- §1e CFF vararg over-bail (coverage)
    "test/fixtures/cff_vararg_closure.lua",    -- CFF wider-flatten: nested vararg closures
    "test/fixtures/edge_hexfloat.lua",         -- §2 hex float literals (Lua 5.3+)
    "test/fixtures/edge_strings.lua",          -- §1c tricky string literals
    "test/fixtures/edge_vm_special.lua",       -- §1d VM non-finite/special constants
}

-- 5.4-only fixtures: use syntax (<const>/<close>) that a 5.3 interpreter cannot
-- even parse, so their baseline must run under a Lua 5.4 binary. Set LUA_BIN_54 to
-- enable; otherwise they are skipped.
local FIXTURES_54 = {
    "test/fixtures/attrib_const.lua",
    "test/fixtures/attrib_close.lua",
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
local function runScript(path, bin)
    bin = bin or LUA_BIN
    local outPath = TMP .. "/deadeye_run_" .. tostring(math.random(1, 1e9)) .. ".out"
    local cmd = string.format('%q %q > %q 2>&1', bin, path, outPath)
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

-- Multi-seed fuzz: when FUZZ=N is set, each fixture is obfuscated under N pinned
-- seeds (1..N) and must pass under EVERY one. The per-build RNG drives opcode
-- permutation, CFF pattern/predicate choice and junk counts, so a single seed can
-- hide a probabilistic bug; the fuzz loop makes those deterministic & reproducible.
local NSEEDS = tonumber(os.getenv("FUZZ") or "")
-- Optional Lua 5.4 interpreter for the 5.4-only fixtures (attributes).
local LUA_BIN_54 = os.getenv("LUA_BIN_54")

local passed, failed, skipped = 0, {}, 0

-- Run Obfuscate with the pipeline's progress prints silenced (so a fuzz run of
-- hundreds of builds stays readable).
local function obfQuiet(src)
    local real = print
    _G.print = function() end
    local ok, res = pcall(Obfuscate, src)
    _G.print = real
    return ok, res
end

local function diffReport(origOut, obfOut)
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

-- Obfuscate `src` under one pinned seed (or ambient config when seed is nil), run
-- the output under `bin`, and compare to the baseline. Returns ok, msg, oo, bo.
local function checkOne(src, origOut, origStatus, bin, seed, tag)
    if seed ~= nil then
        Config = Config or {}
        Config.RandomSeed = seed
    end
    local ok, obf = obfQuiet(src)
    if not ok then return false, "obfuscation error: " .. tostring(obf) end
    local obfPath = TMP .. "/deadeye_obf_" .. tag .. ".lua"
    writeFile(obfPath, obf)
    local obfOut, obfStatus = runScript(obfPath, bin)
    if obfOut == origOut and obfStatus == origStatus then
        os.remove(obfPath)
        return true
    end
    os.rename(obfPath, obfPath .. ".kept")
    local parts = {}
    if obfStatus ~= origStatus then
        parts[#parts + 1] = ("exit orig=%s obf=%s"):format(tostring(origStatus), tostring(obfStatus))
    end
    parts[#parts + 1] = "kept " .. obfPath .. ".kept"
    return false, table.concat(parts, " | "), origOut, obfOut
end

local function runSuite(fixtures, bin, binName)
    for _, fixture in ipairs(fixtures) do
        io.write(("%-38s "):format(fixture))
        local src = readFile(fixture)
        if not src then
            io.write("SKIP (not found)\n"); skipped = skipped + 1
        elseif not bin then
            io.write("SKIP (set " .. binName .. ")\n"); skipped = skipped + 1
        else
            local origOut, origStatus = runScript(fixture, bin)
            local seeds
            if NSEEDS then
                seeds = {}
                for i = 1, NSEEDS do seeds[i] = i end
            else
                seeds = { false } -- sentinel: single run with ambient (random) seed
            end
            local firstFail
            for _, seed in ipairs(seeds) do
                local sv = (seed ~= false) and seed or nil
                local tag = fixture:gsub("[^%w]", "_") .. "_" .. tostring(sv)
                local ok, msg, oo, bo = checkOne(src, origOut, origStatus, bin, sv, tag)
                if not ok then firstFail = { seed = sv, msg = msg, oo = oo, bo = bo }; break end
            end
            if not firstFail then
                io.write(NSEEDS and ("PASS (" .. NSEEDS .. " seeds)\n") or "PASS\n")
                passed = passed + 1
            else
                io.write("FAIL" .. (firstFail.seed and (" (seed " .. firstFail.seed .. ")") or "") .. "\n")
                io.write("       " .. tostring(firstFail.msg) .. "\n")
                if firstFail.oo then diffReport(firstFail.oo, firstFail.bo) end
                failed[#failed + 1] = fixture
            end
        end
    end
end

runSuite(FIXTURES, LUA_BIN, "lua")
runSuite(FIXTURES_54, LUA_BIN_54, "LUA_BIN_54")

print(("\n%d passed, %d failed, %d skipped"):format(passed, #failed, skipped))
if #failed > 0 then
    print("FAILED: " .. table.concat(failed, ", "))
    os.exit(1)
end
os.exit(0)

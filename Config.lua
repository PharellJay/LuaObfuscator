InputPath = "testinput.lua" --Directory has to be Input
OutputPath = "testresult.lua" --Always saved into the directory Output

VariableLength = 12 --The length of the obfuscated variable names

DeadCodeInjectProbability = 0.45 --Chance (0.0-1.0) to inject a dead if-block before each statement

JunkPoolRatioMin = 50 --Minimum percentage of junk entries in the constant pool
JunkPoolRatioMax = 100 --Maximum percentage of junk entries in the constant pool

RandomSeed = nil --Optional: set a number to force a fixed seed (for reproducibility)

Config = Config or {}
Config.VirtualizePrefix = "vm_" --Top-level functions whose name starts with this are compiled to the bytecode VM (set to nil/"" to disable)
Config.VirtualizeAll = false --When true, virtualize EVERY eligible top-level function (prefix ignored). Maximum coverage; ineligible functions safely stay native.

-- When true, the VM interpreter that is spliced into the output is exempted from
-- dead-code injection and control-flow flattening (variable renaming + the text
-- passes still apply to it). The interpreter is the dominant runtime cost in
-- "max" mode, and those two passes applied to it are the bulk of that cost, so
-- this makes virtualized output run much faster WITHOUT weakening the
-- obfuscation of your own code at all. Tradeoff: only the interpreter itself
-- becomes a little easier to pattern-match (its opcodes are still per-build
-- permuted and its constants encrypted). Default false (full strength).
Config.VMLightweight = false

-- Obfuscation strength preset. Picks a base set of passes:
--   "max"  — maximum strength (every pass on). Highest runtime cost. (default)
--   "fast" — performance mode: weaker but much faster output. Drops the heaviest
--            runtime passes (control-flow flattening, dead-code injection, string
--            splitting) and virtualizes only prefix-selected functions, while
--            keeping cheap baseline obfuscation (rename, number/string, pool,
--            minify, anti-tamper). Protect sensitive functions with the
--            VirtualizePrefix so they still get the VM in this mode.
Config.Preset = "max"

local PRESETS = {
    max = {
        CommentRemoval = true, DeadCode = true, Rename = true, Flatten = true,
        NumberObf = true, StringObf = true, StringSplit = true,
        ConstantPool = true, Minify = true, AntiTamper = true,
    },
    fast = {
        CommentRemoval = true, DeadCode = false, Rename = true, Flatten = false,
        NumberObf = true, StringObf = true, StringSplit = false,
        ConstantPool = true, Minify = true, AntiTamper = true,
    },
}

Config.PRESETS = PRESETS -- exposed so tooling can select a preset by name

-- Per-pass toggles, seeded from the preset above. After this line you can still
-- override any individual pass (e.g. `Config.Passes.Flatten = true`) regardless
-- of the preset; the preset only chooses the starting point.
Config.Passes = PRESETS[Config.Preset] or PRESETS.max

-- The "fast" preset also turns off whole-program virtualization (virtualize only
-- the functions you prefix), since the VM interpreter is the dominant runtime cost.
if Config.Preset == "fast" then Config.VirtualizeAll = false end
-- (Selective virtualization is still driven by Config.VirtualizePrefix above.)
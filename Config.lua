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

-- Per-pass toggles. Each defaults to ON; set to false to skip that pass.
Config.Passes = {
    CommentRemoval = true, -- strip comments
    DeadCode       = true, -- inject junk / opaque-predicate dead blocks
    Rename         = true, -- scope-aware local renaming (both passes)
    Flatten        = true, -- control-flow flattening
    NumberObf      = true, -- numeric-literal obfuscation
    StringObf      = true, -- string-literal XOR encoding
    StringSplit    = true, -- split string literals into fragments
    ConstantPool   = true, -- collect constants into a shuffled pool
    Minify         = true, -- collapse to a single line
    AntiTamper     = true, -- env check + integrity checksum wrapper
}
-- (Virtualization is toggled via Config.VirtualizePrefix above.)
InputPath = "testinput.lua" --Directory has to be Input
OutputPath = "testresult.lua" --Always saved into the directory Output

VariableLength = 12 --The length of the obfuscated variable names

DeadCodeInjectProbability = 0.45 --Chance (0.0-1.0) to inject a dead if-block before each statement

JunkPoolRatioMin = 50 --Minimum percentage of junk entries in the constant pool
JunkPoolRatioMax = 100 --Maximum percentage of junk entries in the constant pool

RandomSeed = nil --Optional: set a number to force a fixed seed (for reproducibility)

Config = Config or {}
Config.VirtualizePrefix = "vm_" --Top-level global functions whose name starts with this are compiled to the bytecode VM (set to nil/"" to disable)
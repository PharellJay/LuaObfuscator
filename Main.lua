require("Libraries")

function Obfuscate(code)
    local seed = GenerateSecureSeed()
    math.randomseed(seed)
    for _ = 1, 5 do math.random() end

    -- Per-pass toggles (default ON unless explicitly set to false in Config.Passes).
    local P = (Config and Config.Passes) or {}
    local function on(name) return P[name] ~= false end

    local obfuscatedCode = code

    if on("CommentRemoval") then obfuscatedCode = RemoveAllComments(obfuscatedCode) end
    print("[*] Tokenizing...")
    local tokens = Tokenize(obfuscatedCode)
    print("[*] Parsing...")
    local ast = Parse(tokens)
    print("[*] Virtualizing functions...")
    ast.body = VirtualizeAST(ast.body) -- a no-op when Config.VirtualizePrefix is unset
    if on("DeadCode") then
        print("[*] Injecting dead code...")
        ast.body = InjectDeadCode(ast.body)
    end
    if on("Rename") then
        print("[*] Renaming variables (pass 1)...")
        RenameVariablesInAST(ast)
    end
    if on("Flatten") then
        print("[*] Flattening AST...")
        ast.body = FlattenAST(ast.body)
    end
    if on("Rename") then
        print("[*] Renaming variables (pass 2)...")
        RenameVariablesInAST(ast)
    end
    print("[*] Emitting...")
    obfuscatedCode = Emit(ast)
    do local f = io.open("Output/after_emit.lua", "w"); if f then f:write(obfuscatedCode); f:close() end end
    if on("NumberObf") then
        print("[*] Obfuscating integers...")
        obfuscatedCode = ObfuscateAllIntegers(obfuscatedCode)
    end
    if on("StringObf") then
        print("[*] Obfuscating strings...")
        obfuscatedCode = ObfuscateAllStrings(obfuscatedCode)
    end
    if on("StringSplit") then
        print("[*] Splitting strings...")
        obfuscatedCode = SplitStrings(obfuscatedCode)
    end
    if on("ConstantPool") then
        print("[*] Creating constant pool...")
        obfuscatedCode = CreateConstantPool(obfuscatedCode)
    end
    do local f = io.open("Output/preminify.lua", "w"); if f then f:write(obfuscatedCode); f:close() end end
    if on("Minify") then
        print("[*] Minifying...")
        obfuscatedCode = Minify(obfuscatedCode)
    end
    obfuscatedCode = [=[
--[[
██████╗ ███████╗ █████╗ ██████╗ ███████╗██╗   ██╗███████╗
██╔══██╗██╔════╝██╔══██╗██╔══██╗██╔════╝╚██╗ ██╔╝██╔════╝
██║  ██║█████╗  ███████║██║  ██║█████╗   ╚████╔╝ █████╗
██║  ██║██╔══╝  ██╔══██║██║  ██║██╔══╝    ╚██╔╝  ██╔══╝
██████╔╝███████╗██║  ██║██████╔╝███████╗   ██║   ███████╗
╚═════╝ ╚══════╝╚═╝  ╚═╝╚═════╝ ╚══════╝   ╚═╝   ╚══════╝

Deadeye Obfuscator | Advanced Lua Obfuscation | https://github.com/PharellJay
]]
]=] .. obfuscatedCode

    if on("AntiTamper") then
        obfuscatedCode = AddAntiTamper(obfuscatedCode)
    end

    return obfuscatedCode
end

-- The block below is the command-line driver. It is skipped when another
-- script (e.g. the test harness) loads this file only to reuse Obfuscate(),
-- by setting SUPPRESS_MAIN_DRIVER before the load.
if not SUPPRESS_MAIN_DRIVER then
    local status, inputCode = pcall(ReadFile, "Input/" .. InputPath)

    if status then
        print("[+] Starting obfuscation...")

        local result = Obfuscate(inputCode)

        local outFile = io.open("Output/" .. OutputPath, "w")
        if outFile then
            outFile:write(result)
            outFile:close()
            print("[+] Obfuscated file saved: " .. "Output/" .. OutputPath)
        end
    else
        print("[-] Error: " .. inputCode)
    end
end

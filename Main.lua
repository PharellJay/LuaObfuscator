require("Libraries")

function Obfuscate(code)
    local seed = GenerateSecureSeed()
    math.randomseed(seed)
    for _ = 1, 5 do math.random() end

    local obfuscatedCode = code

    obfuscatedCode = RemoveAllComments(obfuscatedCode)
    print("[*] Tokenizing...")
    local tokens = Tokenize(obfuscatedCode)
    print("[*] Parsing...")
    local ast = Parse(tokens)
    print("[*] Injecting dead code...")
    ast.body = InjectDeadCode(ast.body)
    print("[*] Renaming variables (pass 1)...")
    RenameVariablesInAST(ast)
    print("[*] Flattening AST...")
    ast.body = FlattenAST(ast.body)
    print("[*] Renaming variables (pass 2)...")
    RenameVariablesInAST(ast)
    print("[*] Emitting...")
    obfuscatedCode = Emit(ast)
    do local f = io.open("Output\\after_emit.lua", "w"); if f then f:write(obfuscatedCode); f:close() end end
    print("[*] Obfuscating integers...")
    obfuscatedCode = ObfuscateAllIntegers(obfuscatedCode)
    print("[*] Obfuscating strings...")
    obfuscatedCode = ObfuscateAllStrings(obfuscatedCode)
    print("[*] Splitting strings...")
    obfuscatedCode = SplitStrings(obfuscatedCode)
    print("[*] Creating constant pool...")
    obfuscatedCode = CreateConstantPool(obfuscatedCode)
    do local f = io.open("Output\\preminify.lua", "w"); if f then f:write(obfuscatedCode); f:close() end end
    print("[*] Minifying...")
    obfuscatedCode = Minify(obfuscatedCode)
    obfuscatedCode = [=[
--[[
██████╗ ███████╗ █████╗ ██████╗ ███████╗██╗   ██╗███████╗
██╔══██╗██╔════╝██╔══██╗██╔══██╗██╔════╝╚██╗ ██╔╝██╔════╝
██║  ██║█████╗  ███████║██║  ██║█████╗   ╚████╔╝ █████╗
██║  ██║██╔══╝  ██╔══██║██║  ██║██╔══╝    ╚██╔╝  ██╔══╝
██████╔╝███████╗██║  ██║██████╔╝███████╗   ██║   ███████╗
╚═════╝ ╚══════╝╚═╝  ╚═╝╚═════╝ ╚══════╝   ╚═╝   ╚══════╝

Deadeye Obfuscator | Advanced Lua Obfuscation | https://store.deadeyeac.com
]]
]=] .. obfuscatedCode

    obfuscatedCode = AddAntiTamper(obfuscatedCode)

    return obfuscatedCode
end

local status, inputCode = pcall(ReadFile, "Input\\" .. InputPath)

if status then
    print("[+] Starting obfuscation...")

    local result = Obfuscate(inputCode)

    local outFile = io.open("Output\\" .. OutputPath, "w")
    if outFile then
        outFile:write(result)
        outFile:close()
        print("[+] Obfuscated file saved: " .. "Output\\" .. OutputPath)
    end
else
    print("[-] Error: " .. inputCode)
end

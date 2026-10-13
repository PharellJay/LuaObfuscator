local PROTECTED_NAMES = {
    ["..."] = true, ["nil"] = true, ["true"] = true, ["false"] = true,
    ["and"] = true, ["or"] = true, ["not"] = true, ["function"] = true,
    ["in"] = true, ["repeat"] = true, ["until"] = true, ["while"] = true,
    ["for"] = true, ["do"] = true, ["end"] = true, ["if"] = true,
    ["then"] = true, ["else"] = true, ["elseif"] = true, ["return"] = true,
    ["break"] = true, ["local"] = true,
}

-- Uses global GenerateRandomName from Utils.lua

-- Scope management
local function newScope()
    return { map = {}, names = {} } -- map: name -> obfuscated, names: array of original names
end

-- Add a variable to the current scope
local function addToScope(scope, name)
    if PROTECTED_NAMES[name] then return end
    if not scope.map[name] then
        scope.map[name] = GenerateRandomName(VariableLength)
        table.insert(scope.names, name)
    end
end

-- Always creates a new binding (for same-scope re-declaration: local x = 1; local x = 2)
local function addToScopeForce(scope, name)
    if PROTECTED_NAMES[name] then return end
    scope.map[name] = GenerateRandomName(VariableLength)
    table.insert(scope.names, name)
end

-- Find the obfuscated name for a variable, searching scope chain
local function findInScopes(scopeStack, name)
    for i = #scopeStack, 1, -1 do
        local mapped = scopeStack[i].map[name]
        if mapped then
            return mapped
        end
    end
    return nil
end

-- Extract identifier names from a token list
local function collectIdentifiers(tokens)
    local names = {}
    for _, tok in ipairs(tokens or {}) do
        if tok.type == "IDENTIFIER" then
            table.insert(names, tok.value)
        end
    end
    return names
end

-- Replace identifiers in a token list using scope stack
local function renameTokens(tokens, scopeStack)
    for _, tok in ipairs(tokens or {}) do
        if tok.type == "IDENTIFIER" then
            local mapped = findInScopes(scopeStack, tok.value)
            if mapped then
                tok.value = mapped
            end
        end
    end
end

-- Extract 'local' variable names from a LocalStatement
local function collectLocalNames(node)
    local names = {}
    local tokens = node.vars and node.vars.tokens or {}
    for _, tok in ipairs(tokens) do
        if tok.type == "IDENTIFIER" then
            table.insert(names, tok.value)
        end
    end
    return names
end

-- Extract parameter names from a FunctionStatement head
local function collectParamNames(headTokens)
    local names = {}
    local inParen = false
    for _, tok in ipairs(headTokens or {}) do
        if tok.type == "SYMBOL" and tok.value == "(" then
            inParen = true
        elseif tok.type == "SYMBOL" and tok.value == ")" then
            break
        elseif inParen and tok.type == "IDENTIFIER" then
            table.insert(names, tok.value)
        end
    end
    return names
end

-- Extract variable names from ForStatement head (numeric for loop)
local function collectForVarNames(headTokens)
    local names = {}
    if headTokens and #headTokens > 0 and headTokens[1].type == "IDENTIFIER" then
        table.insert(names, headTokens[1].value)
    end
    return names
end

-- Extract variable names from ForInStatement vars
local function collectForInVarNames(vars)
    local names = {}
    for _, tok in ipairs((vars and vars.tokens) or {}) do
        if tok.type == "IDENTIFIER" then
            table.insert(names, tok.value)
        end
    end
    return names
end

-- Walk the AST and rename variables with scope awareness
local function walkAndRename(node, scopeStack)
    if not node then return end

    -- Array of statements (no type field)
    if type(node) == "table" and not node.type then
        -- Pre-scan for local function hoisting (Lua hoists local functions to block start)
        for _, stmt in ipairs(node) do
            if stmt.type == "FunctionStatement" and stmt.isLocal then
                for _, tok in ipairs(stmt.head or {}) do
                    if tok.type == "IDENTIFIER" then
                        addToScope(scopeStack[#scopeStack], tok.value)
                        break
                    end
                end
            end
        end
        for _, stmt in ipairs(node) do
            walkAndRename(stmt, scopeStack)
        end
        return
    end

    local t = node.type

    if t == "Chunk" then
        walkAndRename(node.body, scopeStack)

    elseif t == "GenericStatement" then
        -- Handle `local` declarations inside GenericStatement tokens
        local tokens = node.tokens
        if tokens and #tokens >= 2 and tokens[1].type == "KEYWORD" and tokens[1].value == "local" then
            local skipLocal = false
            -- Check for `local function`
            for i = 2, #tokens do
                if tokens[i].type == "KEYWORD" and tokens[i].value == "function" then
                    skipLocal = true
                    break
                end
                if tokens[i].type == "IDENTIFIER" then
                    addToScopeForce(scopeStack[#scopeStack], tokens[i].value)
                end
                if tokens[i].type == "SYMBOL" and tokens[i].value == "=" then
                    break
                end
            end
            renameTokens(tokens, scopeStack)
        else
            renameTokens(tokens, scopeStack)
        end

    elseif t == "ReturnStatement" then
        if node.values and node.values.tokens then
            renameTokens(node.values.tokens, scopeStack)
        end

    elseif t == "BreakStatement" then
        -- nothing to rename

    elseif t == "LocalStatement" then
        local names = collectLocalNames(node)
        for _, name in ipairs(names) do
            addToScopeForce(scopeStack[#scopeStack], name)
        end
        if node.vars and node.vars.tokens then
            renameTokens(node.vars.tokens, scopeStack)
        end
        if node.values and node.values.tokens then
            renameTokens(node.values.tokens, scopeStack)
        end

    elseif t == "AssignmentStatement" then
        if node.values and node.values.tokens then
            renameTokens(node.values.tokens, scopeStack)
        end
        if type(node.vars) == "table" then
            if node.vars.type == "Expression" then
                renameTokens(node.vars.tokens, scopeStack)
            elseif type(node.vars) == "table" and node.vars[1] then
                -- multiple var expressions
                for _, v in ipairs(node.vars) do
                    if v.tokens then renameTokens(v.tokens, scopeStack) end
                end
            end
        end

    elseif t == "FunctionCallStatement" then
        if node.call and node.call.tokens then
            renameTokens(node.call.tokens, scopeStack)
        end

    elseif t == "WhileStatement" then
        renameTokens(node.condition and node.condition.tokens, scopeStack)
        -- the loop body is its own block scope (locals must not leak out)
        local wScope = newScope()
        table.insert(scopeStack, wScope)
        walkAndRename(node.body, scopeStack)
        table.remove(scopeStack)

    elseif t == "ForStatement" then
        -- for control variable creates new scope
        local fScope = newScope()
        table.insert(scopeStack, fScope)
        local forVarNames = collectForVarNames(node.head)
        for _, name in ipairs(forVarNames) do
            addToScope(fScope, name)
        end
        renameTokens(node.head, scopeStack)
        walkAndRename(node.body, scopeStack)
        table.remove(scopeStack)

    elseif t == "ForInStatement" then
        local fiScope = newScope()
        table.insert(scopeStack, fiScope)
        local forInVarNames = collectForInVarNames(node.vars)
        for _, name in ipairs(forInVarNames) do
            addToScope(fiScope, name)
        end
        renameTokens(node.vars and node.vars.tokens, scopeStack)
        renameTokens(node.exps and node.exps.tokens, scopeStack)
        walkAndRename(node.body, scopeStack)
        table.remove(scopeStack)

    elseif t == "RepeatStatement" then
        -- body and the `until` condition share one block scope (the condition
        -- can reference locals declared in the body)
        local rScope = newScope()
        table.insert(scopeStack, rScope)
        walkAndRename(node.body, scopeStack)
        renameTokens(node.condition and node.condition.tokens, scopeStack)
        table.remove(scopeStack)

    elseif t == "IfStatement" then
        -- each clause body (and the else body) is its own block scope, so a
        -- local declared in one clause does not leak into siblings or outward
        for _, clause in ipairs(node.clauses) do
            renameTokens(clause.condition and clause.condition.tokens, scopeStack)
            local cScope = newScope()
            table.insert(scopeStack, cScope)
            walkAndRename(clause.body, scopeStack)
            table.remove(scopeStack)
        end
        if node.elseBody then
            local eScope = newScope()
            table.insert(scopeStack, eScope)
            walkAndRename(node.elseBody, scopeStack)
            table.remove(scopeStack)
        end

    elseif t == "FunctionStatement" then
        -- Function creates new scope
        local fnScope = newScope()
        table.insert(scopeStack, fnScope)

        -- Add parameters
        local paramNames = collectParamNames(node.head)
        for _, name in ipairs(paramNames) do
            addToScope(fnScope, name)
        end

        -- Rename function name if local
        if node.isLocal then
            -- The function name is the first identifier in the head
            for _, tok in ipairs(node.head or {}) do
                if tok.type == "IDENTIFIER" then
                    -- Add to OUTER scope first (creates the obfuscated binding)
                    if #scopeStack >= 2 then
                        addToScope(scopeStack[#scopeStack - 1], tok.value)
                    end
                    -- Then add to INNER scope using THE SAME obfuscated name
                    -- so recursive calls and outer references stay in sync
                    local obfuscatedName = findInScopes(scopeStack, tok.value)
                    fnScope.map[tok.value] = obfuscatedName
                    table.insert(fnScope.names, tok.value)
                    break
                end
            end
        end

        -- Rename the head tokens using OUTER scope (function name might be set by outer)
        if #scopeStack >= 2 then
            renameTokens(node.head, scopeStack)
        end

        walkAndRename(node.body, scopeStack)
        table.remove(scopeStack)

    elseif t == "DoStatement" then
        local doScope = newScope()
        table.insert(scopeStack, doScope)
        walkAndRename(node.body, scopeStack)
        table.remove(scopeStack)

    elseif t == "LabelStatement" then
        -- nothing to rename

    elseif t == "GotoStatement" then
        -- nothing to rename
    end
end

function RenameVariablesInAST(ast)
    local globalScope = newScope()
    -- Pre-populate with common Lua globals so they don't get renamed
    -- (but they can be shadowed by locals)
    local globals = {"print", "type", "tostring", "tonumber", "ipairs", "pairs",
        "next", "select", "unpack", "pcall", "xpcall", "error", "assert",
        "require", "dofile", "load", "loadfile", "rawget", "rawset",
        "rawequal", "setmetatable", "getmetatable", "math", "string",
        "table", "io", "os", "debug", "_G", "coroutine", "bit32", "utf8",
        "CollectTracingData", "GetResourceState", "AddEventHandler",
        "TriggerServerEvent", "TriggerClientEvent", "Citizen", "Config", "ESX",
        -- string methods
        "byte", "char", "find", "format", "gmatch", "gsub", "len", "lower",
        "match", "rep", "reverse", "sub", "upper",
        -- table methods
        "concat", "insert", "maxn", "remove", "sort",
        -- math methods
        "abs", "acos", "asin", "atan", "atan2", "ceil", "cos", "cosh",
        "deg", "exp", "floor", "fmod", "frexp", "ldexp", "log", "log10",
        "max", "min", "modf", "pow", "rad", "random", "randomseed", "sin",
        "sinh", "sqrt", "tan", "tanh",
        -- io methods
        "close", "flush", "input", "lines", "open", "output", "popen",
        "read", "tmpfile", "type", "write",
        -- os methods
        "clock", "date", "difftime", "execute", "exit", "getenv", "remove",
        "rename", "setlocale", "time", "tmpname",
        -- coroutine methods
        "create", "isyieldable", "resume", "running", "status", "wrap",
        "yield",
        -- debug methods
        "debug", "gethook", "getinfo", "getlocal", "getmetatable",
        "getregistry", "getupvalue", "getuservalue", "sethook", "setlocal",
        "setmetatable", "setupvalue", "setuservalue", "traceback",
        "upvalueid", "upvaluejoin",
        -- bit32 methods
        "arshift", "band", "bnot", "bor", "btest", "bxor", "extract",
        "lrotate", "lshift", "replace", "rrotate", "rshift",
    }
    for _, name in ipairs(globals) do
        globalScope.map[name] = name -- identity mapping (not renamed)
    end

    local scopeStack = { globalScope }
    walkAndRename(ast, scopeStack)
end

-- Keep old function signature for compatibility (not used in new pipeline)
function RenameVariables(code, length)
    return code
end

local INJECT_PROBABILITY = DeadCodeInjectProbability or 0.45
local unpack = table.unpack or unpack

local deadLocalCount = 0
local MAX_DEAD_LOCALS_PER_FUNCTION = 150

local function randomVarName()
    deadLocalCount = deadLocalCount + 1
    return GenerateRandomName(VariableLength or 12)
end

local function resetDeadLocalCount()
    deadLocalCount = 0
end

local function makeLocalNumStmt(name, val)
    return { type = "GenericStatement", tokens = {
        { type = "KEYWORD", value = "local" },
        { type = "IDENTIFIER", value = name },
        { type = "SYMBOL", value = "=" },
        { type = "NUMBER", value = tostring(val) },
    }}
end

local function makeAssignStmt(name, val)
    return { type = "GenericStatement", tokens = {
        { type = "IDENTIFIER", value = name },
        { type = "SYMBOL", value = "=" },
        { type = "NUMBER", value = tostring(val) },
    }}
end

local function makeLocalTableStmt(name)
    return { type = "GenericStatement", tokens = {
        { type = "KEYWORD", value = "local" },
        { type = "IDENTIFIER", value = name },
        { type = "SYMBOL", value = "=" },
        { type = "SYMBOL", value = "{" },
        { type = "SYMBOL", value = "}" },
    }}
end

-- ─── Opaque predicate generators ───────────────

local function wrapInvert(toks)
    local r = { { type = "KEYWORD", value = "not" }, { type = "SYMBOL", value = "(" } }
    for _, t in ipairs(toks) do table.insert(r, t) end
    table.insert(r, { type = "SYMBOL", value = ")" })
    return r
end

local function predGlobalMath(_, _, invert)
    -- math.abs(-1) == 1 and math.floor(3.14) == 3  (always true, uses global func calls)
    local result = {
        { type = "IDENTIFIER", value = "math" },
        { type = "SYMBOL", value = "." },
        { type = "IDENTIFIER", value = "abs" },
        { type = "SYMBOL", value = "(" },
        { type = "SYMBOL", value = "-" },
        { type = "NUMBER", value = "1" },
        { type = "SYMBOL", value = ")" },
        { type = "SYMBOL", value = "==" },
        { type = "NUMBER", value = "1" },
        { type = "KEYWORD", value = "and" },
        { type = "IDENTIFIER", value = "math" },
        { type = "SYMBOL", value = "." },
        { type = "IDENTIFIER", value = "floor" },
        { type = "SYMBOL", value = "(" },
        { type = "NUMBER", value = "3.14" },
        { type = "SYMBOL", value = ")" },
        { type = "SYMBOL", value = "==" },
        { type = "NUMBER", value = "3" },
    }
    if invert then result = wrapInvert(result) end
    return result
end

local function predGlobalType(_, _, invert)
    -- type(string) == "table" and type(string.byte) == "function" (always true)
    local result = {
        { type = "IDENTIFIER", value = "type" },
        { type = "SYMBOL", value = "(" },
        { type = "IDENTIFIER", value = "string" },
        { type = "SYMBOL", value = ")" },
        { type = "SYMBOL", value = "==" },
        { type = "STRING", value = '"table"' },
        { type = "KEYWORD", value = "and" },
        { type = "IDENTIFIER", value = "type" },
        { type = "SYMBOL", value = "(" },
        { type = "IDENTIFIER", value = "string" },
        { type = "SYMBOL", value = "." },
        { type = "IDENTIFIER", value = "byte" },
        { type = "SYMBOL", value = ")" },
        { type = "SYMBOL", value = "==" },
        { type = "STRING", value = '"function"' },
    }
    if invert then result = wrapInvert(result) end
    return result
end

local function predGlobalLen(_, _, invert)
    -- #tostring(math.random()) > 0 (runtime string from global func calls)
    local result = {
        { type = "SYMBOL", value = "#" },
        { type = "IDENTIFIER", value = "tostring" },
        { type = "SYMBOL", value = "(" },
        { type = "IDENTIFIER", value = "math" },
        { type = "SYMBOL", value = "." },
        { type = "IDENTIFIER", value = "random" },
        { type = "SYMBOL", value = "(" },
        { type = "SYMBOL", value = ")" },
        { type = "SYMBOL", value = ")" },
        { type = "SYMBOL", value = ">" },
        { type = "NUMBER", value = "0" },
    }
    if invert then result = wrapInvert(result) end
    return result
end

local function predGlobalString(_, _, invert)
    -- string.find("abc","a") == 1 (global table member call)
    local result = {
        { type = "IDENTIFIER", value = "string" },
        { type = "SYMBOL", value = "." },
        { type = "IDENTIFIER", value = "find" },
        { type = "SYMBOL", value = "(" },
        { type = "STRING", value = '"abc"' },
        { type = "SYMBOL", value = "," },
        { type = "STRING", value = '"a"' },
        { type = "SYMBOL", value = ")" },
        { type = "SYMBOL", value = "==" },
        { type = "NUMBER", value = "1" },
    }
    if invert then result = wrapInvert(result) end
    return result
end

local function predStringLength(invert)
    -- #tostring(math.random()) > 0 (runtime, not constant-foldable)
    local result = {
        { type = "SYMBOL", value = "#" },
        { type = "IDENTIFIER", value = "tostring" },
        { type = "SYMBOL", value = "(" },
        { type = "IDENTIFIER", value = "math" },
        { type = "SYMBOL", value = "." },
        { type = "IDENTIFIER", value = "random" },
        { type = "SYMBOL", value = "(" },
        { type = "SYMBOL", value = ")" },
        { type = "SYMBOL", value = ")" },
        { type = "SYMBOL", value = ">" },
        { type = "NUMBER", value = "0" },
    }
    if invert then result = wrapInvert(result) end
    return result
end

local predicateBuilders = {
    predGlobalMath,
    predGlobalType,
    predGlobalLen,
    predGlobalString,
}

-- ─── Junk body generators ──────────────────────

local function junkBody1()
    local v = randomVarName()
    return { makeLocalNumStmt(v, math.random(1, 999)) }
end

local function junkBody2()
    local v = randomVarName()
    local v2 = randomVarName()
    return { makeLocalNumStmt(v, math.random(1, 999)), makeAssignStmt(v2, math.random(1, 99999)) }
end

local function junkBody3()
    local v = randomVarName()
    return { makeLocalTableStmt(v), makeAssignStmt(v, math.random(1, 99999)) }
end

local function junkBodyNested()
    local v = randomVarName()
    local v2 = randomVarName()
    return {
        makeLocalNumStmt(v, math.random(1, 999)),
        { type = "IfStatement", clauses = {{
            condition = { type = "Expression", tokens = { { type = "KEYWORD", value = "true" } } },
            body = { makeLocalNumStmt(v2, math.random(1, 999)) }
        }}},
    }
end

local junkBodyBuilders = { junkBody1, junkBody2, junkBody3, junkBodyNested }

-- ─── Dead block pattern generators ────────────

-- Pattern 1: Always-false if (current approach, but with more varied structure)
-- All patterns are wrapped in DoStatement to preserve local scoping across flattening
local function patternAlwaysFalse()
    local varName = randomVarName()
    local declVal = math.random(10000, 99999)
    local builder = predicateBuilders[math.random(1, #predicateBuilders)]
    local cond = builder(varName, declVal, true)
    return {
        { type = "DoStatement", body = {
            makeLocalNumStmt(varName, declVal),
            { type = "IfStatement", clauses = {{
                condition = { type = "Expression", tokens = cond },
                body = junkBodyBuilders[math.random(1, #junkBodyBuilders)]()
            }}},
        }},
    }
end

-- Pattern 2: Always-true if, junk in else branch
local function patternJunkElse()
    local varName = randomVarName()
    local declVal = math.random(10000, 99999)
    local builder = predicateBuilders[math.random(1, #predicateBuilders)]
    local cond = builder(varName, declVal, false)
    return {
        { type = "DoStatement", body = {
            makeLocalNumStmt(varName, declVal),
            { type = "IfStatement", clauses = {{
                condition = { type = "Expression", tokens = cond },
                body = { makeLocalNumStmt(randomVarName(), math.random(1, 999)) }
            }}, elseBody = junkBodyBuilders[math.random(1, #junkBodyBuilders)]() },
        }},
    }
end

-- Pattern 2: Always-true if, junk in else branch
-- NOTE: second definition overrides the first (both kept for variations; this one uses DoStatement wrapper)
local function patternJunkElse()
    local varName = randomVarName()
    local declVal = math.random(10000, 99999)
    local builder = predicateBuilders[math.random(1, #predicateBuilders)]
    local cond = builder(varName, declVal, false)
    return {
        { type = "DoStatement", body = {
            makeLocalNumStmt(varName, declVal),
            { type = "IfStatement", clauses = {{
                condition = { type = "Expression", tokens = cond },
                body = { makeLocalNumStmt(randomVarName(), math.random(1, 999)) }
            }}, elseBody = junkBodyBuilders[math.random(1, #junkBodyBuilders)]() },
        }},
    }
end

-- Pattern 3: do-block with dead code that has no effect
local function patternDeadDo()
    local v = randomVarName()
    return {
        { type = "DoStatement", body = {
            makeLocalNumStmt(v, math.random(1, 99999)),
        }},
    }
end

-- Pattern 4: Always-true while loop (executes exactly once, breaks)
local function patternDeadWhile()
    local v = randomVarName()
    return {
        { type = "WhileStatement",
            condition = { type = "Expression", tokens = { { type = "KEYWORD", value = "true" } } },
            body = {
                makeLocalNumStmt(v, math.random(1, 99999)),
                { type = "BreakStatement" },
            }
        },
    }
end

-- Pattern 5: Nested opaque predicate (if inside if)
local function patternNested()
    local v1 = randomVarName()
    local v2 = randomVarName()
    local dv1 = math.random(10000, 99999)
    local dv2 = math.random(10000, 99999)
    local b1 = predicateBuilders[math.random(1, #predicateBuilders)]
    local b2 = predicateBuilders[math.random(1, #predicateBuilders)]
    return {
        { type = "DoStatement", body = {
            makeLocalNumStmt(v1, dv1),
            makeLocalNumStmt(v2, dv2),
            { type = "IfStatement", clauses = {{
                condition = { type = "Expression", tokens = b1(v1, dv1, true) },
                body = {
                    { type = "IfStatement", clauses = {{
                        condition = { type = "Expression", tokens = b2(v2, dv2, true) },
                        body = junkBodyBuilders[math.random(1, #junkBodyBuilders)]()
                    }}},
                }
            }}},
        }},
    }
end

-- Pattern 6: Combined global predicate (two predicates ANDed together)
local function patternMixed()
    local b1 = predicateBuilders[math.random(1, #predicateBuilders)]
    local b2 = predicateBuilders[math.random(1, #predicateBuilders)]
    local cond1 = b1(nil, nil, true)
    local cond2 = b2(nil, nil, false)
    local combined = {}
    for _, t in ipairs(cond1) do table.insert(combined, t) end
    table.insert(combined, { type = "KEYWORD", value = "and" })
    for _, t in ipairs(cond2) do table.insert(combined, t) end
    return {
        { type = "DoStatement", body = {
            { type = "IfStatement", clauses = {{
                condition = { type = "Expression", tokens = combined },
                body = junkBodyBuilders[math.random(1, #junkBodyBuilders)]()
            }}},
        }},
    }
end

local deadPatterns = {
    patternAlwaysFalse,
    patternJunkElse,
    patternDeadDo,
    patternDeadWhile,
    patternNested,
    patternMixed,
}

function InjectDeadCode(statements)
    local result = {}

    -- Check if this block contains goto/label statements; if so, skip injection
    -- to avoid creating local variables that break goto scope rules
    local hasUnsafe = false
    for _, stmt in ipairs(statements) do
        if stmt.type == "GotoStatement" or stmt.type == "LabelStatement" then
            hasUnsafe = true
            break
        end
    end

    for _, stmt in ipairs(statements) do
        if not hasUnsafe and deadLocalCount < MAX_DEAD_LOCALS_PER_FUNCTION and math.random() < INJECT_PROBABILITY then
            local pattern = deadPatterns[math.random(1, #deadPatterns)]
            local blocks = pattern()
            for _, block in ipairs(blocks) do
                table.insert(result, block)
            end
            -- ~30% chance: inject a SECOND block after the statement too
            if deadLocalCount < MAX_DEAD_LOCALS_PER_FUNCTION and math.random() < 0.3 then
                local pattern2 = deadPatterns[math.random(1, #deadPatterns)]
                local blocks2 = pattern2()
                for _, block in ipairs(blocks2) do
                    table.insert(result, block)
                end
            end
        end

        local t = stmt.type
        if t == "WhileStatement" then
            stmt.body = InjectDeadCode(stmt.body)
        elseif t == "ForStatement" then
            stmt.body = InjectDeadCode(stmt.body)
        elseif t == "ForInStatement" then
            stmt.body = InjectDeadCode(stmt.body)
        elseif t == "RepeatStatement" then
            stmt.body = InjectDeadCode(stmt.body)
        elseif t == "IfStatement" then
            for _, clause in ipairs(stmt.clauses) do
                clause.body = InjectDeadCode(clause.body)
            end
            if stmt.elseBody then
                stmt.elseBody = InjectDeadCode(stmt.elseBody)
            end
        elseif t == "FunctionStatement" then
            -- Reset local count for each function entry
            local prevCount = deadLocalCount
            deadLocalCount = 0
            stmt.body = InjectDeadCode(stmt.body)
            deadLocalCount = prevCount
        elseif t == "DoStatement" then
            stmt.body = InjectDeadCode(stmt.body)
        end

        table.insert(result, stmt)
    end

    return result
end
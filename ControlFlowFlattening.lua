function Shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

local MAX_HOISTED_PER_DECL = 190 -- Lua register limit is ~200; stay safe

function HoistVariables(statements)
    local hoisted = {}
    local newStatements = {}

    for _, stmt in ipairs(statements) do
        if stmt.type == "GenericStatement" then
            if stmt.tokens[1] and stmt.tokens[1].value == "local" then
                local varName = stmt.tokens[2].value
                table.insert(hoisted, varName)
                local assignmentTokens = {}
                for i = 2, #stmt.tokens do
                    table.insert(assignmentTokens, stmt.tokens[i])
                end
                table.insert(newStatements, { type = "GenericStatement", tokens = assignmentTokens })
            else
                table.insert(newStatements, stmt)
            end
        elseif stmt.type == "LocalStatement" then
            local varNames = {}
            for _, tok in ipairs((stmt.vars and stmt.vars.tokens) or {}) do
                if tok.type == "IDENTIFIER" then
                    table.insert(varNames, tok.value)
                end
            end
            for _, name in ipairs(varNames) do
                table.insert(hoisted, name)
            end
            if stmt.values then
                local assignTokens = {}
                -- vars + = + values
                for _, tok in ipairs((stmt.vars and stmt.vars.tokens) or {}) do
                    table.insert(assignTokens, tok)
                end
                table.insert(assignTokens, { type = "SYMBOL", value = "=" })
                for _, tok in ipairs((stmt.values and stmt.values.tokens) or {}) do
                    table.insert(assignTokens, tok)
                end
                table.insert(newStatements, { type = "GenericStatement", tokens = assignTokens })
            end
        elseif stmt.type == "FunctionStatement" and stmt.isLocal then
            -- `local function f(...) ... end` binds f in the enclosing block, so f must
            -- stay visible to sibling statements once they are split into separate
            -- dispatch scopes. Hoist the name and re-emit the definition as a plain
            -- assignment `function f(...) ... end` targeting the hoisted local. This is
            -- exactly how Lua itself desugars `local function` (local f; f = function...),
            -- so recursive references to f keep working.
            local name
            for _, tok in ipairs(stmt.head or {}) do
                if tok.type == "IDENTIFIER" then name = tok.value; break end
            end
            if name then
                table.insert(hoisted, name)
                table.insert(newStatements, {
                    type = "FunctionStatement",
                    isLocal = false,
                    head = stmt.head,
                    body = stmt.body,
                })
            else
                table.insert(newStatements, stmt)
            end
        else
            table.insert(newStatements, stmt)
        end
    end

    -- Cap the number of variables in the hoisted declaration
    -- Lua limits registers to ~200; exceeding this causes "needs too many registers"
    if #hoisted > MAX_HOISTED_PER_DECL then
        -- Split into groups, emit individual local declarations for overflow
        local extra = {}
        for i = MAX_HOISTED_PER_DECL + 1, #hoisted do
            table.insert(extra, hoisted[i])
        end
        for i = #hoisted, MAX_HOISTED_PER_DECL + 1, -1 do
            hoisted[i] = nil
        end
        -- Emit extra hoisted variables as separate local decls (without initial values)
        for _, name in ipairs(extra) do
            table.insert(newStatements, {
                type = "GenericStatement",
                tokens = { { type = "KEYWORD", value = "local" }, { type = "IDENTIFIER", value = name } }
            })
        end
    end

    return hoisted, newStatements
end

local function IsTerminalStatement(stmt)
    if stmt.type == "ReturnStatement" or stmt.type == "BreakStatement" then
        return true
    end
    if stmt.type == "GenericStatement" then
        local depth = 0
        for _, tok in ipairs(stmt.tokens) do
            if tok.type == "KEYWORD" then
                if tok.value == "function" then
                    depth = depth + 1
                elseif tok.value == "end" then
                    depth = depth - 1
                elseif depth == 0 and (tok.value == "break" or tok.value == "return") then
                    return true
                end
            end
        end
    end
    return false
end

local function randomName()
    return GenerateRandomName(VariableLength or 12)
end

local function randomStateID(exclude)
    local id
    repeat
        id = math.random(1, 99999999)
    until not exclude or not exclude[id]
    return id
end

local OPS = {"+", "-", "*"}
local function randomOp()
    return OPS[math.random(1, #OPS)]
end

local function GetStateBody(stmt)
    return { stmt }
end

-- ============================================================
--  PATTERN 1: While-If chain with 2 state variables
-- ============================================================
local function FlattenBlockWhileIf(cleanStatements, hoisted)
    local s1Var = randomName()
    local s2Var = randomName()
    local guardVar = randomName()

    local useAdd = math.random(0, 1) == 1
    local opSym = useAdd and "+" or "-"

    local stateIDs = {}
    local stateIDSet = {}
    for i = 1, #cleanStatements do
        local id = randomStateID(stateIDSet)
        stateIDs[i] = id
        stateIDSet[id] = true
    end
    stateIDs[#cleanStatements + 1] = 0
    stateIDSet[0] = true

    local seed = math.random(1, 999999)

    -- Build clauses with per-clause next-state assignment
    local clauses = {}
    for i, stmt in ipairs(cleanStatements) do
        local currentID = stateIDs[i]
        local nextID
        if IsTerminalStatement(stmt) then
            nextID = 0
        else
            nextID = stateIDs[i + 1]
        end
        local d1val = math.random(10000, 99999999)
        local d2val
        if useAdd then
            d2val = nextID - d1val
        else
            d2val = d1val - nextID
        end

        local stateBody = {}
        local stmts = GetStateBody(stmt)
        for _, s in ipairs(stmts) do table.insert(stateBody, s) end

        -- Per-clause next-state assignment (replaces shared d1/d2 dispatch)
        table.insert(stateBody, {
            type = "GenericStatement",
            tokens = {
                { type = "IDENTIFIER", value = s1Var },
                { type = "SYMBOL", value = "," },
                { type = "IDENTIFIER", value = s2Var },
                { type = "SYMBOL", value = "=" },
                { type = "NUMBER", value = tostring(d1val) },
                { type = "SYMBOL", value = "," },
                { type = "NUMBER", value = tostring(d2val) },
            }
        })

        local condOp
        if useAdd then
            condOp = math.random(1, 3)
        else
            condOp = math.random(1, 2)
            if condOp == 2 then condOp = 3 end
        end
        local condition
        if condOp == 1 then
            condition = { type = "Expression",
                tokens = {
                    { type = "IDENTIFIER", value = s1Var },
                    { type = "SYMBOL", value = opSym },
                    { type = "IDENTIFIER", value = s2Var },
                    { type = "SYMBOL", value = "==" },
                    { type = "NUMBER", value = tostring(currentID) },
                }
            }
        elseif condOp == 2 then
            condition = { type = "Expression",
                tokens = {
                    { type = "IDENTIFIER", value = s2Var },
                    { type = "SYMBOL", value = opSym },
                    { type = "IDENTIFIER", value = s1Var },
                    { type = "SYMBOL", value = "==" },
                    { type = "NUMBER", value = tostring(currentID) },
                }
            }
        else
            condition = { type = "Expression",
                tokens = {
                    { type = "SYMBOL", value = "(" },
                    { type = "IDENTIFIER", value = s1Var },
                    { type = "SYMBOL", value = opSym },
                    { type = "IDENTIFIER", value = s2Var },
                    { type = "SYMBOL", value = ")" },
                    { type = "SYMBOL", value = "%" },
                    { type = "NUMBER", value = tostring(currentID + math.random(10000, 99999999)) },
                    { type = "SYMBOL", value = "==" },
                    { type = "NUMBER", value = tostring(currentID) },
                }
            }
        end

        table.insert(clauses, { condition = condition, body = stateBody })
    end

    Shuffle(clauses)

    -- Add junk clauses with unreachable conditions
    local junkClauseCount = math.random(1, 3)
    for _ = 1, junkClauseCount do
        local junkKey = randomStateID(stateIDSet)
        local junkCond
        if math.random(0, 1) == 0 then
            junkCond = { type = "Expression", tokens = {
                { type = "IDENTIFIER", value = s1Var },
                { type = "SYMBOL", value = opSym },
                { type = "IDENTIFIER", value = s2Var },
                { type = "SYMBOL", value = "==" },
                { type = "NUMBER", value = tostring(junkKey) },
            }}
        else
            junkCond = { type = "Expression", tokens = {
                { type = "IDENTIFIER", value = s2Var },
                { type = "SYMBOL", value = opSym },
                { type = "IDENTIFIER", value = s1Var },
                { type = "SYMBOL", value = "==" },
                { type = "NUMBER", value = tostring(junkKey) },
            }}
        end
        local junkBody = {
            { type = "GenericStatement", tokens = {
                { type = "IDENTIFIER", value = s1Var },
                { type = "SYMBOL", value = "," },
                { type = "IDENTIFIER", value = s2Var },
                { type = "SYMBOL", value = "=" },
                { type = "NUMBER", value = tostring(math.random(10000, 99999999)) },
                { type = "SYMBOL", value = "," },
                { type = "NUMBER", value = tostring(math.random(10000, 99999999)) },
            }}
        }
        -- Randomly intersperse junk clauses among real ones
        local insertPos = math.random(1, #clauses + 1)
        table.insert(clauses, insertPos, { condition = junkCond, body = junkBody })
    end

    local finalBody = {}
    if #hoisted > 0 then
        local hoistTokens = { { type = "KEYWORD", value = "local" } }
        for i, name in ipairs(hoisted) do
            table.insert(hoistTokens, { type = "IDENTIFIER", value = name })
            if i < #hoisted then table.insert(hoistTokens, { type = "SYMBOL", value = "," }) end
        end
        table.insert(finalBody, { type = "GenericStatement", tokens = hoistTokens })
    end

    local guardVal = math.random(10000, 99999999)
    local guardKey = math.random(1, 100)
    table.insert(finalBody, {
        type = "GenericStatement",
        tokens = {
            { type = "KEYWORD", value = "local" },
            { type = "IDENTIFIER", value = guardVar },
            { type = "SYMBOL", value = "=" },
            { type = "SYMBOL", value = "{" },
            { type = "SYMBOL", value = "[" },
            { type = "NUMBER", value = tostring(guardKey) },
            { type = "SYMBOL", value = "]" },
            { type = "SYMBOL", value = "=" },
            { type = "NUMBER", value = tostring(guardVal) },
            { type = "SYMBOL", value = "}" },
        }
    })

    local initS1, initS2
    if useAdd then
        initS1 = stateIDs[1] - seed
        initS2 = seed
    else
        initS1 = stateIDs[1] + seed
        initS2 = seed
    end

    table.insert(finalBody, {
        type = "GenericStatement",
        tokens = {
            { type = "KEYWORD", value = "local" },
            { type = "IDENTIFIER", value = s1Var },
            { type = "SYMBOL", value = "," },
            { type = "IDENTIFIER", value = s2Var },
            { type = "SYMBOL", value = "=" },
            { type = "NUMBER", value = tostring(initS1) },
            { type = "SYMBOL", value = "," },
            { type = "NUMBER", value = tostring(initS2) },
        }
    })

    local guardCheck = math.random(1, 3)
    local whileCond
    if guardCheck == 1 then
        whileCond = { type = "Expression",
            tokens = {
                { type = "IDENTIFIER", value = s1Var },
                { type = "SYMBOL", value = opSym },
                { type = "IDENTIFIER", value = s2Var },
                { type = "SYMBOL", value = "~=" },
                { type = "NUMBER", value = "0" },
                { type = "KEYWORD", value = "and" },
                { type = "IDENTIFIER", value = guardVar },
                { type = "SYMBOL", value = "[" },
                { type = "NUMBER", value = tostring(guardKey) },
                { type = "SYMBOL", value = "]" },
                { type = "SYMBOL", value = "~=" },
                { type = "NUMBER", value = "nil" },
            }
        }
    elseif guardCheck == 2 then
        local r = math.random(10000, 99999)
        whileCond = { type = "Expression",
            tokens = {
                { type = "IDENTIFIER", value = s1Var },
                { type = "SYMBOL", value = opSym },
                { type = "IDENTIFIER", value = s2Var },
                { type = "SYMBOL", value = "~=" },
                { type = "NUMBER", value = "0" },
                { type = "KEYWORD", value = "and" },
                { type = "SYMBOL", value = "(" },
                { type = "IDENTIFIER", value = s1Var },
                { type = "SYMBOL", value = "+" },
                { type = "NUMBER", value = tostring(r) },
                { type = "SYMBOL", value = "-" },
                { type = "NUMBER", value = tostring(r) },
                { type = "SYMBOL", value = "==" },
                { type = "IDENTIFIER", value = s1Var },
                { type = "SYMBOL", value = ")" },
            }
        }
    else
        whileCond = { type = "Expression",
            tokens = {
                { type = "IDENTIFIER", value = s1Var },
                { type = "SYMBOL", value = opSym },
                { type = "IDENTIFIER", value = s2Var },
                { type = "SYMBOL", value = "~=" },
                { type = "NUMBER", value = "0" },
                { type = "KEYWORD", value = "and" },
                { type = "IDENTIFIER", value = guardVar },
                { type = "SYMBOL", value = "[" },
                { type = "NUMBER", value = tostring(guardKey) },
                { type = "SYMBOL", value = "]" },
            }
        }
    end

    table.insert(finalBody, {
        type = "WhileStatement",
        condition = whileCond,
        body = {
            { type = "IfStatement", clauses = clauses },
        }
    })

    return finalBody
end

-- ============================================================
--  Nested-return rewriting (C1b-1)
-- ============================================================
-- A nested `return E` inside a statement that is moved into a dispatch state
-- function would return from that state function, not the enclosing function.
-- Rewrite each such return to `return <retName>, table.pack(E)`; the dispatch
-- loop recognizes the sentinel and performs the real return. Returns inside a
-- nested function definition are left alone (they belong to that function).
local function makeRetSig(valuesExpr, retName)
    local toks = {
        { type = "KEYWORD", value = "return" },
        { type = "IDENTIFIER", value = retName },
        { type = "SYMBOL", value = "," },
        { type = "IDENTIFIER", value = "table" },
        { type = "SYMBOL", value = "." },
        { type = "IDENTIFIER", value = "pack" },
        { type = "SYMBOL", value = "(" },
    }
    if valuesExpr and valuesExpr.tokens then
        for _, t in ipairs(valuesExpr.tokens) do table.insert(toks, t) end
    end
    table.insert(toks, { type = "SYMBOL", value = ")" })
    return { type = "GenericStatement", tokens = toks }
end

local function rewriteReturnsInList(stmts, retName)
    for i, s in ipairs(stmts) do
        if s.type == "ReturnStatement" then
            stmts[i] = makeRetSig(s.values, retName)
        elseif s.type == "FunctionStatement" then
            -- do not descend: an inner function's returns are its own
        else
            if s.body then rewriteReturnsInList(s.body, retName) end
            if s.clauses then
                for _, c in ipairs(s.clauses) do
                    if c.body then rewriteReturnsInList(c.body, retName) end
                end
            end
            if s.elseBody then rewriteReturnsInList(s.elseBody, retName) end
        end
    end
end

-- ============================================================
--  PATTERN 2: Function dispatch table
-- ============================================================
-- retName (optional): when set, nested returns in cleanStatements are rewritten
-- to the RETSIG protocol and the dispatch loop checks for the sentinel. When nil,
-- behavior is exactly as before (no return handling).
local function FlattenBlockFunctionDispatch(cleanStatements, hoisted, retName)
    local dispatchVar = randomName()
    local stateVar = randomName()
    local guardVar = randomName()

    if retName then rewriteReturnsInList(cleanStatements, retName) end

    local stateIDs = {}
    local stateIDSet = {}
    for i = 1, #cleanStatements do
        local id = randomStateID(stateIDSet)
        stateIDs[i] = id
        stateIDSet[id] = true
    end
    stateIDs[#cleanStatements + 1] = 0
    stateIDSet[0] = true

    local finalBody = {}

    -- RETSIG sentinel: a fresh table so a numeric next-state can never equal it.
    if retName then
        table.insert(finalBody, {
            type = "GenericStatement",
            tokens = {
                { type = "KEYWORD", value = "local" },
                { type = "IDENTIFIER", value = retName },
                { type = "SYMBOL", value = "=" },
                { type = "SYMBOL", value = "{" },
                { type = "SYMBOL", value = "}" },
            }
        })
    end

    if #hoisted > 0 then
        local hoistTokens = { { type = "KEYWORD", value = "local" } }
        for i, name in ipairs(hoisted) do
            table.insert(hoistTokens, { type = "IDENTIFIER", value = name })
            if i < #hoisted then table.insert(hoistTokens, { type = "SYMBOL", value = "," }) end
        end
        table.insert(finalBody, { type = "GenericStatement", tokens = hoistTokens })
    end

    table.insert(finalBody, {
        type = "GenericStatement",
        tokens = {
            { type = "KEYWORD", value = "local" },
            { type = "IDENTIFIER", value = dispatchVar },
            { type = "SYMBOL", value = "=" },
            { type = "SYMBOL", value = "{" },
            { type = "SYMBOL", value = "}" },
        }
    })

    for i, stmt in ipairs(cleanStatements) do
        local funcName = randomName()
        local currentID = stateIDs[i]
        local stmts = GetStateBody(stmt)
        local nextID
        if IsTerminalStatement(stmt) then
            nextID = 0
        else
            nextID = stateIDs[i + 1]
        end

        local funcBody = {}
        if stmt.type == "ReturnStatement" then
            -- Replace a return statement with the dispatch return
            -- (original return would make the dispatch return unreachable)
            if nextID ~= 0 then
                table.insert(funcBody, {
                    type = "GenericStatement",
                    tokens = {
                        { type = "KEYWORD", value = "return" },
                        { type = "NUMBER", value = tostring(nextID) },
                    }
                })
            else
                table.insert(funcBody, {
                    type = "GenericStatement",
                    tokens = {
                        { type = "KEYWORD", value = "return" },
                        { type = "NUMBER", value = "0" },
                    }
                })
            end
        else
            for _, s in ipairs(stmts) do table.insert(funcBody, s) end
            if nextID ~= 0 then
                table.insert(funcBody, {
                    type = "GenericStatement",
                    tokens = {
                        { type = "KEYWORD", value = "return" },
                        { type = "NUMBER", value = tostring(nextID) },
                    }
                })
            else
                table.insert(funcBody, {
                    type = "GenericStatement",
                    tokens = {
                        { type = "KEYWORD", value = "return" },
                        { type = "NUMBER", value = "0" },
                    }
                })
            end
        end

        table.insert(finalBody, {
            type = "FunctionStatement",
            isLocal = true,
            head = {
                { type = "IDENTIFIER", value = funcName },
                { type = "SYMBOL", value = "(" },
                { type = "SYMBOL", value = "..." },
                { type = "SYMBOL", value = ")" },
            },
            body = funcBody,
        })

        table.insert(finalBody, {
            type = "GenericStatement",
            tokens = {
                { type = "IDENTIFIER", value = dispatchVar },
                { type = "SYMBOL", value = "[" },
                { type = "NUMBER", value = tostring(currentID) },
                { type = "SYMBOL", value = "]" },
                { type = "SYMBOL", value = "=" },
                { type = "IDENTIFIER", value = funcName },
            }
        })
    end

    local junkCount = math.random(1, 3)
    for _ = 1, junkCount do
        local junkID = randomStateID(stateIDSet)
        local junkName = randomName()
        local junkNext = randomStateID(stateIDSet)

        table.insert(finalBody, {
            type = "FunctionStatement",
            isLocal = true,
            head = {
                { type = "IDENTIFIER", value = junkName },
                { type = "SYMBOL", value = "(" },
                { type = "SYMBOL", value = "..." },
                { type = "SYMBOL", value = ")" },
            },
            body = {
                { type = "GenericStatement", tokens = {
                    { type = "KEYWORD", value = "local" },
                    { type = "IDENTIFIER", value = randomName() },
                    { type = "SYMBOL", value = "=" },
                    { type = "NUMBER", value = tostring(math.random(1, 99999)) },
                }},
                { type = "GenericStatement", tokens = {
                    { type = "KEYWORD", value = "return" },
                    { type = "NUMBER", value = tostring(junkNext) },
                }},
            }
        })

        table.insert(finalBody, {
            type = "GenericStatement",
            tokens = {
                { type = "IDENTIFIER", value = dispatchVar },
                { type = "SYMBOL", value = "[" },
                { type = "NUMBER", value = tostring(junkID) },
                { type = "SYMBOL", value = "]" },
                { type = "SYMBOL", value = "=" },
                { type = "IDENTIFIER", value = junkName },
            }
        })
    end

    local guardKey = math.random(1, 99999)
    table.insert(finalBody, {
        type = "GenericStatement",
        tokens = {
            { type = "KEYWORD", value = "local" },
            { type = "IDENTIFIER", value = guardVar },
            { type = "SYMBOL", value = "=" },
            { type = "SYMBOL", value = "{" },
            { type = "SYMBOL", value = "[" },
            { type = "NUMBER", value = tostring(guardKey) },
            { type = "SYMBOL", value = "]" },
            { type = "SYMBOL", value = "=" },
            { type = "KEYWORD", value = "true" },
            { type = "SYMBOL", value = "}" },
        }
    })

    local stateInit = stateIDs[1]
    table.insert(finalBody, {
        type = "GenericStatement",
        tokens = {
            { type = "KEYWORD", value = "local" },
            { type = "IDENTIFIER", value = stateVar },
            { type = "SYMBOL", value = "=" },
            { type = "NUMBER", value = tostring(stateInit) },
        }
    })

    local guardCheck = math.random(1, 2)
    local whileCond
    if guardCheck == 1 then
        whileCond = { type = "Expression",
            tokens = {
                { type = "IDENTIFIER", value = stateVar },
                { type = "SYMBOL", value = "~=" },
                { type = "NUMBER", value = "0" },
                { type = "KEYWORD", value = "and" },
                { type = "IDENTIFIER", value = guardVar },
                { type = "SYMBOL", value = "[" },
                { type = "NUMBER", value = tostring(guardKey) },
                { type = "SYMBOL", value = "]" },
            }
        }
    else
        local r = math.random(10000, 99999)
        whileCond = { type = "Expression",
            tokens = {
                { type = "IDENTIFIER", value = stateVar },
                { type = "SYMBOL", value = "~=" },
                { type = "NUMBER", value = "0" },
                { type = "KEYWORD", value = "and" },
                { type = "SYMBOL", value = "(" },
                { type = "IDENTIFIER", value = stateVar },
                { type = "SYMBOL", value = "+" },
                { type = "NUMBER", value = tostring(r) },
                { type = "SYMBOL", value = "-" },
                { type = "NUMBER", value = tostring(r) },
                { type = "SYMBOL", value = "==" },
                { type = "IDENTIFIER", value = stateVar },
                { type = "SYMBOL", value = ")" },
            }
        }
    end

    local loopBody
    if retName then
        -- local _a,_b = D[s]() ; if _a == retName then return table.unpack(_b,1,_b.n) end ; s = _a
        local av = randomName()
        local bv = randomName()
        loopBody = {
            { type = "GenericStatement", tokens = {
                { type = "KEYWORD", value = "local" },
                { type = "IDENTIFIER", value = av }, { type = "SYMBOL", value = "," }, { type = "IDENTIFIER", value = bv },
                { type = "SYMBOL", value = "=" },
                { type = "IDENTIFIER", value = dispatchVar }, { type = "SYMBOL", value = "[" },
                { type = "IDENTIFIER", value = stateVar }, { type = "SYMBOL", value = "]" },
                { type = "SYMBOL", value = "(" }, { type = "SYMBOL", value = ")" },
            } },
            { type = "IfStatement", clauses = { {
                condition = { type = "Expression", tokens = {
                    { type = "IDENTIFIER", value = av }, { type = "SYMBOL", value = "==" }, { type = "IDENTIFIER", value = retName },
                } },
                body = { { type = "GenericStatement", tokens = {
                    { type = "KEYWORD", value = "return" },
                    { type = "IDENTIFIER", value = "table" }, { type = "SYMBOL", value = "." }, { type = "IDENTIFIER", value = "unpack" },
                    { type = "SYMBOL", value = "(" },
                    { type = "IDENTIFIER", value = bv }, { type = "SYMBOL", value = "," }, { type = "NUMBER", value = "1" },
                    { type = "SYMBOL", value = "," },
                    { type = "IDENTIFIER", value = bv }, { type = "SYMBOL", value = "." }, { type = "IDENTIFIER", value = "n" },
                    { type = "SYMBOL", value = ")" },
                } } },
            } } },
            { type = "GenericStatement", tokens = {
                { type = "IDENTIFIER", value = stateVar }, { type = "SYMBOL", value = "=" }, { type = "IDENTIFIER", value = av },
            } },
        }
    else
        loopBody = {
            {
                type = "GenericStatement",
                tokens = {
                    { type = "IDENTIFIER", value = stateVar },
                    { type = "SYMBOL", value = "=" },
                    { type = "IDENTIFIER", value = dispatchVar },
                    { type = "SYMBOL", value = "[" },
                    { type = "IDENTIFIER", value = stateVar },
                    { type = "SYMBOL", value = "]" },
                    { type = "SYMBOL", value = "(" },
                    { type = "SYMBOL", value = ")" },
                }
            },
        }
    end

    table.insert(finalBody, {
        type = "WhileStatement",
        condition = whileCond,
        body = loopBody,
    })

    return finalBody
end

-- ============================================================
--  ENTRY POINTS
-- ============================================================
function FlattenBlock(statements)
    if #statements < 2 then return statements end

    -- Generic recursive predicate over a statement's own sub-blocks. Does NOT
    -- descend into nested FunctionStatement bodies — their break/goto/return
    -- belong to that inner function, not to the block being flattened.
    local function anyStmt(stmt, pred)
        if pred(stmt) then return true end
        if stmt.type == "FunctionStatement" then return false end
        if stmt.body then
            for _, s in ipairs(stmt.body) do if anyStmt(s, pred) then return true end end
        end
        if stmt.clauses then
            for _, c in ipairs(stmt.clauses) do
                if c.body then for _, s in ipairs(c.body) do if anyStmt(s, pred) then return true end end end
            end
        end
        if stmt.elseBody then
            for _, s in ipairs(stmt.elseBody) do if anyStmt(s, pred) then return true end end
        end
        return false
    end
    -- goto/label always bail (C1b-3 territory).
    local function hasGotoLabel(stmt)
        return anyStmt(stmt, function(s)
            return s.type == "GotoStatement" or s.type == "LabelStatement"
        end)
    end
    -- A `break` enclosed by a loop WITHIN this statement is internal — it stays
    -- inside its dispatch state function and works unchanged (C1b-2). Only an
    -- "escaping" break (targeting a loop that encloses the flattened block) is
    -- unsafe; we still bail on those (C1b-3). Nested functions aren't descended.
    local function hasEscapingBreak(stmt, insideLoop)
        if stmt.type == "BreakStatement" then return not insideLoop end
        if stmt.type == "FunctionStatement" then return false end
        local nowLoop = insideLoop
            or stmt.type == "WhileStatement" or stmt.type == "ForStatement"
            or stmt.type == "ForInStatement" or stmt.type == "RepeatStatement"
        if stmt.body then
            for _, s in ipairs(stmt.body) do if hasEscapingBreak(s, nowLoop) then return true end end
        end
        if stmt.clauses then
            for _, c in ipairs(stmt.clauses) do
                if c.body then for _, s in ipairs(c.body) do if hasEscapingBreak(s, nowLoop) then return true end end end
            end
        end
        if stmt.elseBody then
            for _, s in ipairs(stmt.elseBody) do if hasEscapingBreak(s, nowLoop) then return true end end
        end
        return false
    end
    -- a nested return is now supported via the RETSIG protocol (C1b-1).
    local function hasReturn(stmt)
        return anyStmt(stmt, function(s) return s.type == "ReturnStatement" end)
    end

    -- Flattening moves statements into dispatch state functions `function _s(...)`,
    -- so a vararg `...` referring to the ENCLOSING function would be rebound to the
    -- (empty) wrapper's varargs. Conservatively bail if any statement uses `...`
    -- (this over-bails on `...` inside nested function literals, which is safe).
    local function toksVararg(toks)
        if not toks then return false end
        for _, t in ipairs(toks) do
            if t.type == "SYMBOL" and t.value == "..." then return true end
        end
        return false
    end
    local function stmtHasVararg(stmt)
        if toksVararg(stmt.tokens) or toksVararg(stmt.head) then return true end
        for _, fld in ipairs({ "vars", "values", "condition", "exps", "call" }) do
            if stmt[fld] and stmt[fld].tokens and toksVararg(stmt[fld].tokens) then return true end
        end
        if stmt.body then
            for _, s in ipairs(stmt.body) do if stmtHasVararg(s) then return true end end
        end
        if stmt.clauses then
            for _, c in ipairs(stmt.clauses) do
                if c.condition and c.condition.tokens and toksVararg(c.condition.tokens) then return true end
                if c.body then for _, s in ipairs(c.body) do if stmtHasVararg(s) then return true end end end
            end
        end
        if stmt.elseBody then
            for _, s in ipairs(stmt.elseBody) do if stmtHasVararg(s) then return true end end
        end
        return false
    end

    -- Lua guarantees a `return` is the LAST statement of its block, so split off a
    -- trailing return and flatten only the statements before it; the return is
    -- re-appended after the dispatch loop and executes in the enclosing function
    -- unchanged. This needs no return-propagation protocol in the state machine.
    local tail = nil
    local flattenTo = #statements
    if statements[#statements].type == "ReturnStatement" then
        tail = statements[#statements]
        flattenTo = #statements - 1
    end
    if flattenTo < 2 then return statements end

    local toFlatten = {}
    local needRet = false
    for i = 1, flattenTo do
        local s = statements[i]
        if hasGotoLabel(s) or hasEscapingBreak(s, false) or stmtHasVararg(s) then return statements end
        if hasReturn(s) then needRet = true end
        toFlatten[i] = s
    end

    local hoisted, cleanStatements = HoistVariables(toFlatten)

    local finalBody
    if needRet then
        -- nested returns present: only the function-dispatch variant implements
        -- the RETSIG protocol, so force it with a fresh sentinel name.
        finalBody = FlattenBlockFunctionDispatch(cleanStatements, hoisted, randomName())
    elseif math.random() < 0.5 then
        finalBody = FlattenBlockWhileIf(cleanStatements, hoisted)
    else
        finalBody = FlattenBlockFunctionDispatch(cleanStatements, hoisted)
    end
    if tail then finalBody[#finalBody + 1] = tail end
    return finalBody
end

function FlattenAST(statements)
    for _, stmt in ipairs(statements) do
        local t = stmt.type
        if t == "WhileStatement" then
            stmt.body = FlattenAST(stmt.body)
        elseif t == "ForStatement" then
            stmt.body = FlattenAST(stmt.body)
        elseif t == "ForInStatement" then
            stmt.body = FlattenAST(stmt.body)
        elseif t == "RepeatStatement" then
            stmt.body = FlattenAST(stmt.body)
        elseif t == "IfStatement" then
            for _, clause in ipairs(stmt.clauses) do
                clause.body = FlattenAST(clause.body)
            end
            if stmt.elseBody then
                stmt.elseBody = FlattenAST(stmt.elseBody)
            end
        elseif t == "FunctionStatement" then
            stmt.body = FlattenAST(stmt.body)
        elseif t == "DoStatement" then
            stmt.body = FlattenAST(stmt.body)
        end
    end

    return FlattenBlock(statements)
end
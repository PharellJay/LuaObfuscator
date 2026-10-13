local function isWordToken(t)
    return t.type == "IDENTIFIER" or t.type == "KEYWORD" or t.type == "NUMBER" or t.type == "STRING"
end

local function joinTokens(tokens)
    local parts = {}
    for i, t in ipairs(tokens) do
        if i > 1 then
            local prev = tokens[i - 1]
            if isWordToken(prev) and isWordToken(t) then
                table.insert(parts, " ")
            elseif prev.type == "NUMBER" and t.type == "SYMBOL" and t.value == ".." then
                table.insert(parts, " ")
            elseif prev.type == "SYMBOL" and prev.value == ".." and t.type == "NUMBER" then
                table.insert(parts, " ")
            elseif prev.value and t.value and prev.value:sub(-1) == "-" and t.value:sub(1, 1) == "-" then
                -- prevent two adjacent '-' from merging into '--' (a comment),
                -- e.g. unary minus of a negative: `- -5` must not become `--5`.
                table.insert(parts, " ")
            end
        end
        table.insert(parts, t.value)
    end
    return table.concat(parts)
end

local function emitExpr(expr)
    if not expr then return "" end
    local toks = (expr.type == "Expression") and expr.tokens or expr
    -- Opt-in: emit through the real expression IR (ExprAST) instead of just
    -- re-joining tokens. Used to validate the IR against the test harness; the
    -- token path remains the default so behavior is unchanged when the flag is off.
    if USE_EXPR_AST and type(toks) == "table" then
        local nodes = BuildExprList(toks)
        local parts = {}
        for _, n in ipairs(nodes) do parts[#parts + 1] = EmitExprAST(n) end
        return table.concat(parts, ",")
    end
    return joinTokens(toks)
end

local function emitExprList(list)
    if not list then return "" end
    if type(list) == "table" and list.type == "Expression" then
        return emitExpr(list)
    end
    if type(list) == "table" and list[1] and type(list[1]) == "table" then
        local parts = {}
        for _, ex in ipairs(list) do
            table.insert(parts, emitExpr(ex))
        end
        return table.concat(parts, ",")
    end
    return ""
end

function Emit(node)
    if not node then return "" end

    if type(node) == "table" and not node.type then
        local code = ""
        for _, stmt in ipairs(node) do
            code = code .. Emit(stmt) .. ";\n"
        end
        return code
    end

    local t = node.type

    if t == "Chunk" then
        return Emit(node.body)

    elseif t == "RawStatement" then
        return node.code

    elseif t == "GenericStatement" then
        return joinTokens(node.tokens)

    elseif t == "ReturnStatement" then
        local vals = emitExpr(node.values)
        if vals ~= "" then
            return "return " .. vals
        end
        return "return"

    elseif t == "BreakStatement" then
        return "break"

    elseif t == "LocalStatement" then
        local vars = emitExpr(node.vars)
        if node.values then
            return "local " .. vars .. "=" .. emitExpr(node.values)
        end
        return "local " .. vars

    elseif t == "AssignmentStatement" then
        local vars = emitExprList(node.vars)
        local vals = emitExpr(node.values)
        return vars .. "=" .. vals

    elseif t == "FunctionCallStatement" then
        return emitExpr(node.call)

    elseif t == "WhileStatement" then
        local cond = emitExpr(node.condition)
        return "while " .. cond .. " do\n" .. Emit(node.body) .. "end"

    elseif t == "ForStatement" then
        local head = joinTokens(node.head)
        return "for " .. head .. " do\n" .. Emit(node.body) .. "end"

    elseif t == "ForInStatement" then
        local vars = emitExpr(node.vars)
        local exps = emitExpr(node.exps)
        return "for " .. vars .. " in " .. exps .. " do\n" .. Emit(node.body) .. "end"

    elseif t == "RepeatStatement" then
        local cond = emitExpr(node.condition)
        return "repeat\n" .. Emit(node.body) .. "until " .. cond

    elseif t == "IfStatement" then
        local code = ""
        for i, clause in ipairs(node.clauses) do
            local keyword = (i == 1) and "if " or "elseif "
            code = code .. keyword .. emitExpr(clause.condition) .. " then\n"
            code = code .. Emit(clause.body)
        end
        if node.elseBody then
            code = code .. "else\n" .. Emit(node.elseBody)
        end
        return code .. "end"

    elseif t == "FunctionStatement" then
        local prefix = node.isLocal and "local function " or "function "
        local head = joinTokens(node.head)
        return prefix .. head .. "\n" .. Emit(node.body) .. "end"

    elseif t == "DoStatement" then
        return "do\n" .. Emit(node.body) .. "end"

    elseif t == "LabelStatement" then
        return "::" .. node.name .. "::"

    elseif t == "GotoStatement" then
        return "goto " .. node.label
    end

    return "-- [[ Unknown Node Type: " .. tostring(t) .. " ]]"
end

local tokens = {}
local pos = 1

local function peek()
    return tokens[pos]
end

local function advance()
    local t = tokens[pos]
    pos = pos + 1
    return t
end

local function is_eof()
    return pos > #tokens
end

local function accept(tType, value)
    local t = peek()
    if t and t.type == tType and (not value or t.value == value) then
        return advance()
    end
    return nil
end

local function expect(tType, value)
    local t = accept(tType, value)
    if not t then
        local found = peek() and (peek().type .. " '" .. peek().value .. "'") or "EOF"
        error("Syntax error: Expected " .. (value or tType) .. ", got " .. found)
    end
    return t
end

-- Precedence table: higher number = higher precedence
local PREC = {
    ["or"] = 1,
    ["and"] = 2,
    ["=="] = 3; ["~="] = 3; ["<"] = 3; [">"] = 3; ["<="] = 3; [">="] = 3;
    [".."] = 4;
    ["+"] = 5; ["-"] = 5;
    ["*"] = 6; ["/"] = 6; ["%"] = 6;
    ["not"] = 7; ["#"] = 7; -- unary
    ["^"] = 8;
}

local function getPrec(tok)
    if tok and tok.type == "KEYWORD" and (tok.value == "or" or tok.value == "and" or tok.value == "not") then
        return PREC[tok.value]
    end
    if tok and tok.type == "SYMBOL" and PREC[tok.value] then
        return PREC[tok.value]
    end
    return 0
end

-- Forward declarations
local parseExpr, parsePrefix, parseInfix, parseBlock, parseStatement, parseFunctionName

-- Parse an expression with minimum precedence `minPrec`.
-- Returns an array of tokens.
function parseExpr(minPrec)
    minPrec = minPrec or 0
    if is_eof() then return {} end

    local left = parsePrefix()
    if not left then return {} end

    -- Postfix operators (call, index, field, method) — bind tighter than any binary op
    while not is_eof() do
        local nxt = peek()
        if nxt.type == "SYMBOL" and nxt.value == "." then
            advance()
            local name = peek()
            if name and name.type == "IDENTIFIER" then
                advance()
                local result = {}
                for _, t in ipairs(left) do table.insert(result, t) end
                table.insert(result, { type = "SYMBOL", value = "[" })
                table.insert(result, { type = "STRING", value = '"' .. name.value .. '"' })
                table.insert(result, { type = "SYMBOL", value = "]" })
                left = result
            else break end
        elseif nxt.type == "SYMBOL" and nxt.value == ":" then
            advance()
            local name = peek()
            if name and name.type == "IDENTIFIER" then
                advance()
                local result = {}
                for _, t in ipairs(left) do table.insert(result, t) end
                table.insert(result, nxt)
                table.insert(result, name)
                local args = parseCallArgs()
                for _, t in ipairs(args) do table.insert(result, t) end
                left = result
            else break end
        elseif nxt.type == "SYMBOL" and nxt.value == "[" then
            advance()
            local result = {}
            for _, t in ipairs(left) do table.insert(result, t) end
            table.insert(result, nxt)
            local idx = parseExpr(0)
            for _, t in ipairs(idx) do table.insert(result, t) end
            expect("SYMBOL", "]")
            table.insert(result, { type = "SYMBOL", value = "]" })
            left = result
        elseif nxt.type == "SYMBOL" and nxt.value == "(" then
            local args = parseCallArgs()
            local result = {}
            for _, t in ipairs(left) do table.insert(result, t) end
            for _, t in ipairs(args) do table.insert(result, t) end
            left = result
        elseif nxt.type == "SYMBOL" and nxt.value == "{" then
            local args = parseCallArgs()
            local result = {}
            for _, t in ipairs(left) do table.insert(result, t) end
            for _, t in ipairs(args) do table.insert(result, t) end
            left = result
        elseif nxt.type == "STRING" then
            local args = parseCallArgs()
            local result = {}
            for _, t in ipairs(left) do table.insert(result, t) end
            for _, t in ipairs(args) do table.insert(result, t) end
            left = result
        else break end
    end

    -- Binary operators (precedence-driven)
    while not is_eof() do
        local tok = peek()
        local prec = getPrec(tok)
        if prec == 0 or prec < minPrec then break end

        -- Handle right-associativity for `^`
        local nextMin = prec
        if tok.value == "^" then nextMin = prec end
        if tok.value == ".." then nextMin = prec - 1 end -- .. is actually right-assoc too in Lua
        -- For most binary ops: left-associative: nextMin = prec + 1
        -- But the table above has increasing precedence, so to be left-assoc:
        -- we set nextMin = prec + 1 (meaning next operator must have HIGHER precedence)
        nextMin = prec + 1

        -- Special: `not` is unary, handled in parsePrefix
        if tok.type == "KEYWORD" and tok.value == "not" then break end

        -- Binary operator
        advance()
        local right = parseExpr(nextMin)

        -- Reconstruct: left + op + right
        local result = {}
        for _, t in ipairs(left) do table.insert(result, t) end
        table.insert(result, tok)
        for _, t in ipairs(right) do table.insert(result, t) end
        left = result
    end

    return left
end

-- Parse a prefix expression (primary, unary, function, table constructor)
function parsePrefix()
    if is_eof() then return nil end
    local tok = peek()

    -- Literals (single token)
    if tok.type == "NUMBER" or tok.type == "STRING" then
        return { advance() }
    end

    -- Keywords: nil, true, false
    if tok.type == "KEYWORD" then
        local v = tok.value
        if v == "nil" or v == "true" or v == "false" then
            return { advance() }
        end
        -- unary operators
        if v == "not" or v == "#" then
            advance()
            local right = parseExpr(PREC[v])
            local result = { tok }
            for _, t in ipairs(right) do table.insert(result, t) end
            return result
        end
        if v == "function" then
            return parseFunctionExpr()
        end
        -- Not a valid prefix
        return nil
    end

    -- ... (vararg)
    if tok.type == "SYMBOL" and tok.value == "..." then
        return { advance() }
    end

    -- Unary minus / length operator
    if tok.type == "SYMBOL" and (tok.value == "-" or tok.value == "#") then
        advance()
        local right = parseExpr(PREC[tok.value])
        local result = { tok }
        for _, t in ipairs(right) do table.insert(result, t) end
        return result
    end

    -- Parenthesized expression
    if tok.type == "SYMBOL" and tok.value == "(" then
        advance()
        local inner = parseExpr(0)
        expect("SYMBOL", ")")
        local result = { tok }
        for _, t in ipairs(inner) do table.insert(result, t) end
        table.insert(result, { type = "SYMBOL", value = ")" })
        return result
    end

    -- Table constructor
    if tok.type == "SYMBOL" and tok.value == "{" then
        return parseTableConstructor()
    end

    -- Identifier (variable name)
    if tok.type == "IDENTIFIER" then
        return parseIdentifierExpr()
    end

    return nil
end

function parseIdentifierExpr()
    return { advance() }
end

function parseCallArgs()
    local result = {}
    local tok = peek()

    if not tok then return result end

    if tok.type == "SYMBOL" and tok.value == "(" then
        advance()
        table.insert(result, tok)
        -- Parse expression list (comma-separated)
        while not is_eof() do
            local nxt = peek()
            if nxt.type == "SYMBOL" and nxt.value == ")" then break end
            if nxt.type == "SYMBOL" and nxt.value == ";" then advance() break end

            local prevPos = pos
            local expr = parseExpr(0)
            if #expr == 0 and pos == prevPos then
                -- No progress made; break to avoid infinite loop
                break
            end
            for _, t in ipairs(expr) do table.insert(result, t) end
            if accept("SYMBOL", ",") then
                table.insert(result, { type = "SYMBOL", value = "," })
            end
        end
        expect("SYMBOL", ")")
        table.insert(result, { type = "SYMBOL", value = ")" })

    elseif tok.type == "SYMBOL" and tok.value == "{" then
        local tc = parseTableConstructor()
        for _, t in ipairs(tc) do table.insert(result, t) end

    elseif tok.type == "STRING" then
        table.insert(result, advance())
    end

    return result
end

function parseTableConstructor()
    local result = {}
    expect("SYMBOL", "{")
    table.insert(result, { type = "SYMBOL", value = "{" })

    while not is_eof() do
        local nxt = peek()
        if nxt.type == "SYMBOL" and nxt.value == "}" then break end
        if nxt.type == "SYMBOL" and nxt.value == ";" then advance(); break end

        -- [expr] = expr  (computed key)
        if nxt.type == "SYMBOL" and nxt.value == "[" then
            advance()
            table.insert(result, nxt)
            local key = parseExpr(0)
            for _, t in ipairs(key) do table.insert(result, t) end
            expect("SYMBOL", "]")
            table.insert(result, { type = "SYMBOL", value = "]" })
            expect("SYMBOL", "=")
            table.insert(result, { type = "SYMBOL", value = "=" })
            local val = parseExpr(0)
            for _, t in ipairs(val) do table.insert(result, t) end

        -- Check for name = expr  (record style)
        elseif nxt.type == "IDENTIFIER" and tokens[pos + 1] and tokens[pos + 1].type == "SYMBOL" and tokens[pos + 1].value == "=" then
            -- Convert to ["key"]=value syntax so the renamer doesn't rename the key
            advance()
            table.insert(result, { type = "SYMBOL", value = "[" })
            table.insert(result, { type = "STRING", value = '"' .. nxt.value .. '"' })
            table.insert(result, { type = "SYMBOL", value = "]" })
            advance()
            table.insert(result, { type = "SYMBOL", value = "=" })
            local val = parseExpr(0)
            for _, t in ipairs(val) do table.insert(result, t) end

        -- Expression field (list style)
        else
            local prevPos = pos
            local expr = parseExpr(0)
            if #expr == 0 and pos == prevPos then
                break
            end
            for _, t in ipairs(expr) do table.insert(result, t) end
        end

        if accept("SYMBOL", ",") or accept("SYMBOL", ";") then
            table.insert(result, { type = "SYMBOL", value = "," })
        end
    end

    expect("SYMBOL", "}")
    table.insert(result, { type = "SYMBOL", value = "}" })
    return result
end

function parseFunctionExpr()
    local result = {}
    expect("KEYWORD", "function")
    table.insert(result, { type = "KEYWORD", value = "function" })

    expect("SYMBOL", "(")
    table.insert(result, { type = "SYMBOL", value = "(" })

    -- Parameters
    while not is_eof() do
        local nxt = peek()
        if nxt.type == "SYMBOL" and nxt.value == ")" then break end
        local param = parseExpr(0)
        for _, t in ipairs(param) do table.insert(result, t) end
        if accept("SYMBOL", ",") then
            table.insert(result, { type = "SYMBOL", value = "," })
        end
    end

    expect("SYMBOL", ")")
    table.insert(result, { type = "SYMBOL", value = ")" })

    -- Body: save position, parse block, then extract body tokens from original token stream
    local bodyStart = pos
    local body = parseBlock()
    expect("KEYWORD", "end")
    for i = bodyStart, pos - 2 do
        table.insert(result, tokens[i])
    end
    table.insert(result, { type = "KEYWORD", value = "end" })

    return result
end

local function findTopLevelEq(toks)
    local depth = 0
    local bdepth = 0
    local inRepeat = 0
    local skipDo = false
    for i, t in ipairs(toks) do
        if t.type == "SYMBOL" then
            if t.value == "(" or t.value == "{" or t.value == "[" then depth = depth + 1
            elseif t.value == ")" or t.value == "}" or t.value == "]" then depth = depth - 1 end
        end
        if depth == 0 and bdepth == 0 and t.type == "SYMBOL" and t.value == "=" then
            local prev = toks[i - 1]
            if not (prev and prev.type == "SYMBOL" and (prev.value == "=" or prev.value == "~" or prev.value == "<" or prev.value == ">")) then
                return i
            end
        end
        if t.type == "KEYWORD" then
            local v = t.value
            if v == "function" or v == "if" then
                bdepth = bdepth + 1; skipDo = false
            elseif v == "repeat" then
                bdepth = bdepth + 1; inRepeat = inRepeat + 1; skipDo = false
            elseif v == "while" or v == "for" then
                bdepth = bdepth + 1; skipDo = true
            elseif v == "do" then
                if not skipDo then bdepth = bdepth + 1 end
                skipDo = false
            elseif v == "end" then
                bdepth = math.max(0, bdepth - 1); skipDo = false
            elseif v == "until" then
                bdepth = math.max(0, bdepth - 1); inRepeat = math.max(0, inRepeat - 1); skipDo = false
            end
        end
    end
    return nil
end

local function isCallBalanced(toks)
    if #toks == 0 then return false end
    local last = toks[#toks]
    local closer = last.value
    local opener = (closer == ")") and "(" or "{"
    local depth = 1
    for i = #toks - 1, 1, -1 do
        local t = toks[i]
        if t.type == "SYMBOL" then
            if t.value == closer then depth = depth + 1
            elseif t.value == opener then
                depth = depth - 1
                if depth == 0 then return i > 1 end
            end
        end
    end
    return false
end

local function splitAtCommas(toks)
    local parts = {}
    local start = 1
    local depth = 0
    local bdepth = 0
    local inRepeat = 0
    local skipDo = false
    for i, t in ipairs(toks) do
        if t.type == "SYMBOL" then
            if t.value == "(" or t.value == "{" or t.value == "[" then depth = depth + 1
            elseif t.value == ")" or t.value == "}" or t.value == "]" then depth = depth - 1 end
        end
        if t.type == "KEYWORD" then
            local v = t.value
            if v == "function" or v == "if" then
                bdepth = bdepth + 1; skipDo = false
            elseif v == "repeat" then
                bdepth = bdepth + 1; inRepeat = inRepeat + 1; skipDo = false
            elseif v == "while" or v == "for" then
                bdepth = bdepth + 1; skipDo = true
            elseif v == "do" then
                if not skipDo then bdepth = bdepth + 1 end
                skipDo = false
            elseif v == "end" then
                bdepth = math.max(0, bdepth - 1); skipDo = false
            elseif v == "until" then
                bdepth = math.max(0, bdepth - 1); inRepeat = math.max(0, inRepeat - 1); skipDo = false
            end
        end
        if depth == 0 and bdepth == 0 and t.type == "SYMBOL" and t.value == "," then
            table.insert(parts, { type = "Expression", tokens = copyTokens(toks, start, i - 1) })
            start = i + 1
        end
    end
    table.insert(parts, { type = "Expression", tokens = copyTokens(toks, start, #toks) })
    return parts
end

local function copyTokens(arr, s, e)
    local res = {}
    for i = s, e or #arr do
        table.insert(res, arr[i])
    end
    return res
end

-- Parse a complete expression statement (assignment, function call, or generic)
local function parseExprStatement()
    if is_eof() then return nil end

    -- Parse the first expression (or assignment LHS)
    local first = parseExpr(0)
    if #first == 0 then return nil end
    local lhsTokens = first

    -- Gather comma-separated LHS expressions (e.g., a, b = c, d)
    local hasComma = false
    while accept("SYMBOL", ",") do
        hasComma = true
        local more = parseExpr(0)
        -- Add comma separator
        local combined = {}
        for _, t in ipairs(lhsTokens) do combined[#combined + 1] = t end
        combined[#combined + 1] = { type = "SYMBOL", value = "," }
        for _, t in ipairs(more) do combined[#combined + 1] = t end
        lhsTokens = combined
    end

    -- Check for `=` (assignment)
    if peek() and peek().type == "SYMBOL" and peek().value == "=" then
        -- Check it's not == (but == is a single SYMBOL token)
        advance() -- consume =
        local valTokens = parseExpr(0)
        while accept("SYMBOL", ",") do
            local more = parseExpr(0)
            local combined = {}
            for _, t in ipairs(valTokens) do combined[#combined + 1] = t end
            combined[#combined + 1] = { type = "SYMBOL", value = "," }
            for _, t in ipairs(more) do combined[#combined + 1] = t end
            valTokens = combined
        end
        return {
            type = "AssignmentStatement",
            vars = { type = "Expression", tokens = lhsTokens },
            values = { type = "Expression", tokens = valTokens }
        }
    end

    -- Check for function call: tokens end with balanced ), }, or string
    if #lhsTokens > 0 then
        local last = lhsTokens[#lhsTokens]
        if last.type == "STRING" then
            return { type = "FunctionCallStatement", call = { type = "Expression", tokens = lhsTokens } }
        end
        if last.type == "SYMBOL" and (last.value == ")" or last.value == "}") then
            if isCallBalanced(lhsTokens) then
                return { type = "FunctionCallStatement", call = { type = "Expression", tokens = lhsTokens } }
            end
        end
    end

    -- Generic fallback
    -- If commas were parsed but it's not an assignment or function call,
    -- keep only the first expression (comma-separated expr lists are not valid Lua statements)
    if hasComma then
        return { type = "GenericStatement", tokens = first }
    end
    return { type = "GenericStatement", tokens = lhsTokens }
end

-- ─── Statement parsers ─────────────────────────

local function parseReturn()
    advance()
    local t = peek()
    if t and t.type == "KEYWORD" and (t.value == "end" or t.value == "else" or
        t.value == "elseif" or t.value == "until") then
        return { type = "ReturnStatement", values = nil }
    end
    local expr = parseExpr(0)
    -- Handle comma-separated return values: return a, b, c
    while accept("SYMBOL", ",") do
        local more = parseExpr(0)
        local combined = {}
        for _, t in ipairs(expr) do table.insert(combined, t) end
        table.insert(combined, { type = "SYMBOL", value = "," })
        for _, t in ipairs(more) do table.insert(combined, t) end
        expr = combined
    end
    return { type = "ReturnStatement", values = { type = "Expression", tokens = expr } }
end

local function parseBreak()
    advance()
    return { type = "BreakStatement" }
end

local function parseDo()
    advance()
    local body = parseBlock()
    expect("KEYWORD", "end")
    return { type = "DoStatement", body = body }
end

local function parseWhile()
    advance()
    local cond = parseExpr(0)
    expect("KEYWORD", "do")
    local body = parseBlock()
    expect("KEYWORD", "end")
    return { type = "WhileStatement", condition = { type = "Expression", tokens = cond }, body = body }
end

local function parseFor()
    advance()
    local headTokens = {}
    local isForIn = false

    while not is_eof() do
        local t = peek()
        if t.type == "KEYWORD" and t.value == "do" then break end
        if t.type == "KEYWORD" and t.value == "in" then isForIn = true end
        table.insert(headTokens, advance())
    end

    expect("KEYWORD", "do")
    local body = parseBlock()
    expect("KEYWORD", "end")

    if isForIn then
        local inPos
        for i, ht in ipairs(headTokens) do
            if ht.type == "KEYWORD" and ht.value == "in" then inPos = i; break end
        end
        local vars = inPos and copyTokens(headTokens, 1, inPos - 1) or headTokens
        local exps = inPos and copyTokens(headTokens, inPos + 1, #headTokens) or {}
        return {
            type = "ForInStatement",
            vars = { type = "Expression", tokens = vars },
            exps = { type = "Expression", tokens = exps },
            body = body
        }
    end

    return { type = "ForStatement", head = headTokens, body = body }
end

local function parseRepeat()
    advance()
    local body = parseBlock()
    expect("KEYWORD", "until")
    local cond = parseExpr(0)
    return { type = "RepeatStatement", condition = { type = "Expression", tokens = cond }, body = body }
end

local function parseIf()
    advance()
    local cond = parseExpr(0)
    expect("KEYWORD", "then")
    local body = parseBlock()

    local clauses = { { condition = { type = "Expression", tokens = cond }, body = body } }

    while accept("KEYWORD", "elseif") do
        local elifCond = parseExpr(0)
        expect("KEYWORD", "then")
        local elifBody = parseBlock()
        table.insert(clauses, { condition = { type = "Expression", tokens = elifCond }, body = elifBody })
    end

    local elseBody = nil
    if accept("KEYWORD", "else") then elseBody = parseBlock() end

    expect("KEYWORD", "end")
    return { type = "IfStatement", clauses = clauses, elseBody = elseBody }
end

function parseFunctionName()
    local toks = {}
    local t = peek()
    if not t or t.type ~= "IDENTIFIER" then return toks end
    table.insert(toks, advance())

    while not is_eof() do
        local nxt = peek()
        if nxt.type == "SYMBOL" and nxt.value == "." then
            table.insert(toks, advance())
            local name = peek()
            if name and name.type == "IDENTIFIER" then
                table.insert(toks, advance())
            else break end
        elseif nxt.type == "SYMBOL" and nxt.value == ":" then
            table.insert(toks, advance())
            local name = peek()
            if name and name.type == "IDENTIFIER" then
                table.insert(toks, advance())
            else break end
            break
        else break end
    end
    return toks
end

local function parseFunction(isLocal)
    -- The 'function' keyword has already been consumed by the caller
    local headTokens = parseFunctionName()

    expect("SYMBOL", "(")
    table.insert(headTokens, { type = "SYMBOL", value = "(" })
    while not is_eof() do
        local nxt = peek()
        if nxt.type == "SYMBOL" and nxt.value == ")" then break end
        local param = parseExpr(0)
        for _, t in ipairs(param) do table.insert(headTokens, t) end
        if accept("SYMBOL", ",") then
            table.insert(headTokens, { type = "SYMBOL", value = "," })
        end
    end
    expect("SYMBOL", ")")
    table.insert(headTokens, { type = "SYMBOL", value = ")" })

    local body = parseBlock()
    expect("KEYWORD", "end")
    return { type = "FunctionStatement", isLocal = isLocal, head = headTokens, body = body }
end

local function parseLocal()
    advance()

    if peek() and peek().type == "KEYWORD" and peek().value == "function" then
        advance()
        return parseFunction(true)
    end

    -- Parse variable names until = or end
    local varTokens = {}
    while not is_eof() do
        local t = peek()
        if t.type == "SYMBOL" and t.value == "=" then break end
        if t.type == "SYMBOL" and t.value == ";" then break end
        if t.type == "KEYWORD" then
            local v = t.value
            if v == "end" or v == "else" or v == "elseif" or v == "until" or
               v == "while" or v == "for" or v == "if" or v == "repeat" or
               v == "do" or v == "function" or v == "return" or v == "break" or
               v == "local" then
                break
            end
        end
        table.insert(varTokens, advance())
    end

    if accept("SYMBOL", "=") then
        local valTokens = parseExpr(0)
        while accept("SYMBOL", ",") do
            local more = parseExpr(0)
            local combined = {}
            for _, t in ipairs(valTokens) do table.insert(combined, t) end
            table.insert(combined, { type = "SYMBOL", value = "," })
            for _, t in ipairs(more) do table.insert(combined, t) end
            valTokens = combined
        end
        return {
            type = "LocalStatement",
            vars = { type = "Expression", tokens = varTokens },
            values = { type = "Expression", tokens = valTokens }
        }
    end

    return {
        type = "LocalStatement",
        vars = { type = "Expression", tokens = varTokens },
        values = nil
    }
end

function parseStatement()
    local t = peek()
    if not t then return nil end

    if t.type == "SYMBOL" and t.value == ";" then
        advance()
        return nil
    end

    if t.type == "SYMBOL" and t.value == "::" then
        return parseLabel()
    end

    if t.type == "KEYWORD" then
        local v = t.value
        if v == "while" then return parseWhile() end
        if v == "for" then return parseFor() end
        if v == "repeat" then return parseRepeat() end
        if v == "if" then return parseIf() end
        if v == "function" then advance(); return parseFunction(false) end
        if v == "do" then return parseDo() end
        if v == "return" then return parseReturn() end
        if v == "break" then return parseBreak() end
        if v == "goto" then return parseGoto() end
        if v == "local" then return parseLocal() end
    end

    return parseExprStatement()
end

function parseLabel()
    advance()
    local name = expect("IDENTIFIER")
    expect("SYMBOL", "::")
    return { type = "LabelStatement", name = name.value }
end

function parseGoto()
    advance()
    local name = expect("IDENTIFIER")
    return { type = "GotoStatement", label = name.value }
end

function parseBlock()
    local stmts = {}
    while not is_eof() do
        local t = peek()
        if t.type == "KEYWORD" and (t.value == "end" or t.value == "else" or
            t.value == "elseif" or t.value == "until") then
            break
        end
        local stmt = parseStatement()
        if stmt then
            table.insert(stmts, stmt)
        else
            advance()
        end
        while accept("SYMBOL", ";") do end
    end
    return stmts
end

function Parse(tokenList)
    tokens = tokenList
    pos = 1
    return { type = "Chunk", body = parseBlock() }
end

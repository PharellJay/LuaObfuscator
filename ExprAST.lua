-- ExprAST.lua
--
-- A real expression IR for the obfuscator. The parser (Parser.lua) stores every
-- expression as a flat token list ({type="Expression", tokens={...}}). That is
-- enough to emit source but gives later passes (string/number rewriting, MBA,
-- constant folding, and ultimately the bytecode VM compiler) no structure to
-- work with.
--
-- This module closes that gap WITHOUT disturbing the existing pipeline:
--   * BuildExprAST(tokens)  -> a single expression node (tree)
--   * BuildExprList(tokens) -> an array of expression nodes (comma-separated)
--   * EmitExprAST(node)     -> source string, parenthesized by precedence
--
-- It reconstructs the tree from the already-flattened token stream, so nothing
-- upstream changes. Emitter.lua can opt into emitting through this path (guarded
-- by the global USE_EXPR_AST) to validate the IR end to end against the test
-- harness; with the flag off, behavior is exactly as before.
--
-- Node kinds:
--   Nil / True / False / Vararg          (no fields)
--   Number {value}  String {value}       (raw lexeme, as tokenized)
--   Name   {name}
--   Index  {obj, index}                  -- obj[index]  (field access is normalized to this)
--   Call   {fn, args}                    -- fn(args...)  (f{..} and f"s" normalized to this)
--   Method {obj, name, args}             -- obj:name(args...)
--   Paren  {expr}                        -- (expr)  (kept: it truncates multi-values)
--   Unary  {op, operand}                 -- op in {-, #, not, ~}
--   Binary {op, left, right}
--   Table  {fields = { {key=node|nil, value=node}, ... }}
--   Function {tokens}                    -- opaque verbatim span (nested bodies handled later)

-- Binary operator precedence, mirroring Parser.lua's PREC so the rebuilt tree
-- matches the grouping the rest of the pipeline assumes. Higher binds tighter.
local BIN_PREC = {
    ["or"] = 1,
    ["and"] = 2,
    ["=="] = 3, ["~="] = 3, ["<"] = 3, [">"] = 3, ["<="] = 3, [">="] = 3,
    ["|"] = 4,
    ["~"] = 5, -- binary bitwise xor (unary ~ handled in parsePrimary)
    ["&"] = 6,
    ["<<"] = 7, [">>"] = 7,
    [".."] = 8,
    ["+"] = 9, ["-"] = 9,
    ["*"] = 10, ["/"] = 10, ["%"] = 10, ["//"] = 10,
    ["^"] = 12,
}
local UNARY_PREC = 11
-- Right-associative binary operators.
local RIGHT_ASSOC = { [".."] = true, ["^"] = true }

local function isBinOp(tok)
    if not tok then return nil end
    if tok.type == "SYMBOL" and BIN_PREC[tok.value] then return tok.value end
    if tok.type == "KEYWORD" and (tok.value == "or" or tok.value == "and") then return tok.value end
    return nil
end

-- ─── Builder (flat tokens -> tree) ─────────────────────────────────────────

-- Find the index of the `end` that closes a function expression whose `function`
-- keyword is at `tokens[startIdx]`. Tracks only end-terminated blocks; repeat
-- closes with `until`, so it never adds to the end-depth.
local function findFunctionEnd(tokens, startIdx)
    local depth = 0
    for i = startIdx, #tokens do
        local t = tokens[i]
        if t.type == "KEYWORD" then
            local v = t.value
            if v == "function" or v == "if" or v == "do" then
                depth = depth + 1
            elseif v == "end" then
                depth = depth - 1
                if depth == 0 then return i end
            end
        end
    end
    return nil
end

-- Recover params + a statement-AST body from a `function ( p... ) body end`
-- token span, attaching them to `node`. Leaves node unstructured if the span is
-- malformed (the VM compiler then rejects it and the function stays native).
function structureFunction(node, span)
    if not (span[2] and span[2].value == "(") then return end
    local params, vararg = {}, false
    local i = 3
    while span[i] and span[i].value ~= ")" do
        local t = span[i]
        if t.type == "IDENTIFIER" then
            params[#params + 1] = t.value
        elseif t.value == "..." then
            vararg = true
        end
        i = i + 1
    end
    if not (span[i] and span[i].value == ")") then return end
    local bodyTokens = {}
    for j = i + 1, #span - 1 do bodyTokens[#bodyTokens + 1] = span[j] end
    node.params = params
    node.isVararg = vararg
    node.body = Parse(bodyTokens).body
end

local function newBuilder(tokens)
    return { toks = tokens, pos = 1 }
end

local function bPeek(b) return b.toks[b.pos] end
local function bNext(b) local t = b.toks[b.pos]; b.pos = b.pos + 1; return t end
local function bExpect(b, value)
    local t = bNext(b)
    if not t or t.value ~= value then
        error("ExprAST: expected '" .. value .. "', got '" ..
            (t and tostring(t.value) or "<eof>") .. "'")
    end
    return t
end

local parseBin, parsePostfix, parsePrimary, parseArgs, parseTable

-- Parse a comma-separated argument/expression list until a closer value (or end
-- of tokens). Leaves the cursor on the closer (does not consume it).
local function parseExprSeqUntil(b, closer)
    local list = {}
    local t = bPeek(b)
    if not t or t.value == closer then return list end
    while true do
        list[#list + 1] = parseBin(b, 0)
        local nxt = bPeek(b)
        if nxt and nxt.type == "SYMBOL" and nxt.value == "," then
            bNext(b)
        else
            break
        end
    end
    return list
end

function parseArgs(b)
    local t = bPeek(b)
    if not t then return {} end
    if t.type == "SYMBOL" and t.value == "(" then
        bNext(b)
        local args = parseExprSeqUntil(b, ")")
        bExpect(b, ")")
        return args
    elseif t.type == "SYMBOL" and t.value == "{" then
        return { parseTable(b) }
    elseif t.type == "STRING" then
        return { { kind = "String", value = bNext(b).value } }
    end
    return {}
end

function parseTable(b)
    bExpect(b, "{")
    local fields = {}
    while true do
        local t = bPeek(b)
        if not t or (t.type == "SYMBOL" and t.value == "}") then break end
        if t.type == "SYMBOL" and t.value == "[" then
            bNext(b)
            local key = parseBin(b, 0)
            bExpect(b, "]")
            bExpect(b, "=")
            local value = parseBin(b, 0)
            fields[#fields + 1] = { key = key, value = value }
        else
            -- list-style field (record fields were normalized to ["k"]=v by the parser)
            fields[#fields + 1] = { key = nil, value = parseBin(b, 0) }
        end
        local sep = bPeek(b)
        if sep and sep.type == "SYMBOL" and (sep.value == "," or sep.value == ";") then
            bNext(b)
        else
            break
        end
    end
    bExpect(b, "}")
    return { kind = "Table", fields = fields }
end

function parsePrimary(b)
    local t = bPeek(b)
    if not t then error("ExprAST: unexpected end of expression") end

    if t.type == "NUMBER" then bNext(b); return { kind = "Number", value = t.value } end
    if t.type == "STRING" then bNext(b); return { kind = "String", value = t.value } end

    if t.type == "KEYWORD" then
        local v = t.value
        if v == "nil" then bNext(b); return { kind = "Nil" } end
        if v == "true" then bNext(b); return { kind = "True" } end
        if v == "false" then bNext(b); return { kind = "False" } end
        if v == "not" then
            bNext(b)
            return { kind = "Unary", op = "not", operand = parseBin(b, UNARY_PREC) }
        end
        if v == "function" then
            local endIdx = findFunctionEnd(b.toks, b.pos)
            if not endIdx then error("ExprAST: unterminated function expression") end
            local span = {}
            for i = b.pos, endIdx do span[#span + 1] = b.toks[i] end
            b.pos = endIdx + 1
            -- Also recover a structured view (params + body statement AST) so the
            -- VM compiler can compile nested functions. `tokens` is kept so the
            -- emitter can still print the function verbatim.
            local node = { kind = "Function", tokens = span }
            structureFunction(node, span)
            return node
        end
        error("ExprAST: unexpected keyword '" .. v .. "' in expression")
    end

    if t.type == "SYMBOL" then
        local v = t.value
        if v == "..." then bNext(b); return { kind = "Vararg" } end
        if v == "-" or v == "#" or v == "~" then
            bNext(b)
            return { kind = "Unary", op = v, operand = parseBin(b, UNARY_PREC) }
        end
        if v == "(" then
            bNext(b)
            local inner = parseBin(b, 0)
            bExpect(b, ")")
            return { kind = "Paren", expr = inner }
        end
        if v == "{" then
            return parseTable(b)
        end
    end

    if t.type == "IDENTIFIER" then
        bNext(b)
        return { kind = "Name", name = t.value }
    end

    error("ExprAST: cannot start expression at '" .. tostring(t.value) .. "'")
end

function parsePostfix(b)
    local node = parsePrimary(b)
    while true do
        local t = bPeek(b)
        if not t or t.type ~= "SYMBOL" then break end
        local v = t.value
        if v == "[" then
            bNext(b)
            local index = parseBin(b, 0)
            bExpect(b, "]")
            node = { kind = "Index", obj = node, index = index }
        elseif v == "." then
            -- defensive: parser normally rewrites .field to ["field"], but handle it
            bNext(b)
            local name = bNext(b)
            node = { kind = "Index", obj = node,
                index = { kind = "String", value = '"' .. name.value .. '"' } }
        elseif v == ":" then
            bNext(b)
            local name = bNext(b)
            local args = parseArgs(b)
            node = { kind = "Method", obj = node, name = name.value, args = args }
        elseif v == "(" or v == "{" then
            node = { kind = "Call", fn = node, args = parseArgs(b) }
        else
            break
        end
        -- a string literal immediately after is also a call: f"s"
        local after = bPeek(b)
        if after and after.type == "STRING" then
            node = { kind = "Call", fn = node, args = { { kind = "String", value = bNext(b).value } } }
        end
    end
    -- handle call-by-string / call-by-table directly on a primary (e.g. require"x")
    local t = bPeek(b)
    if t and t.type == "STRING" then
        node = { kind = "Call", fn = node, args = { { kind = "String", value = bNext(b).value } } }
    end
    return node
end

-- Precedence-climbing for binary operators.
function parseBin(b, minPrec)
    local left = parsePostfix(b)
    while true do
        local tok = bPeek(b)
        local op = isBinOp(tok)
        if not op then break end
        local prec = BIN_PREC[op]
        if prec < minPrec then break end
        bNext(b)
        local nextMin = RIGHT_ASSOC[op] and prec or (prec + 1)
        local right = parseBin(b, nextMin)
        left = { kind = "Binary", op = op, left = left, right = right }
    end
    return left
end

-- Split a token list at top-level commas (respecting (), {}, [] and
-- function/if/do ... end nesting), returning one token sub-list per element.
local function splitTopLevelCommas(tokens)
    local parts, cur = {}, {}
    local depth, blockDepth = 0, 0
    for _, t in ipairs(tokens) do
        if t.type == "SYMBOL" then
            local v = t.value
            if v == "(" or v == "{" or v == "[" then depth = depth + 1
            elseif v == ")" or v == "}" or v == "]" then depth = depth - 1 end
        elseif t.type == "KEYWORD" then
            local v = t.value
            if v == "function" or v == "if" or v == "do" then blockDepth = blockDepth + 1
            elseif v == "end" then blockDepth = blockDepth - 1 end
        end
        if depth == 0 and blockDepth == 0 and t.type == "SYMBOL" and t.value == "," then
            parts[#parts + 1] = cur
            cur = {}
        else
            cur[#cur + 1] = t
        end
    end
    parts[#parts + 1] = cur
    return parts
end

function BuildExprAST(tokens)
    local b = newBuilder(tokens)
    local node = parseBin(b, 0)
    if b.pos <= #tokens then
        local leftover = {}
        for i = b.pos, #tokens do leftover[#leftover + 1] = tostring(tokens[i].value) end
        error("ExprAST: trailing tokens not consumed: " .. table.concat(leftover, " "))
    end
    return node
end

function BuildExprList(tokens)
    if not tokens or #tokens == 0 then return {} end
    local parts = splitTopLevelCommas(tokens)
    local nodes = {}
    for _, part in ipairs(parts) do
        if #part > 0 then
            nodes[#nodes + 1] = BuildExprAST(part)
        end
    end
    return nodes
end

-- ─── Emitter (tree -> source) ──────────────────────────────────────────────

-- Verbatim joiner for opaque Function spans; mirrors Emitter.lua's joinTokens
-- spacing rules so round-tripping is exact.
local function isWord(t)
    return t.type == "IDENTIFIER" or t.type == "KEYWORD" or t.type == "NUMBER" or t.type == "STRING"
end
local function joinTokensVerbatim(toks)
    local parts = {}
    for i, t in ipairs(toks) do
        if i > 1 then
            local prev = toks[i - 1]
            if isWord(prev) and isWord(t) then
                parts[#parts + 1] = " "
            elseif prev.type == "NUMBER" and t.type == "SYMBOL" and t.value == ".." then
                parts[#parts + 1] = " "
            elseif prev.type == "SYMBOL" and prev.value == ".." and t.type == "NUMBER" then
                parts[#parts + 1] = " "
            elseif prev.value and t.value and prev.value:sub(-1) == "-" and t.value:sub(1, 1) == "-" then
                parts[#parts + 1] = " " -- avoid '-' '-' merging into '--' (comment)
            end
        end
        parts[#parts + 1] = t.value
    end
    return table.concat(parts)
end

local emit

-- Precedence of a node for deciding whether a child needs parentheses.
local function nodePrec(node)
    if node.kind == "Binary" then return BIN_PREC[node.op] end
    if node.kind == "Unary" then return UNARY_PREC end
    return 100 -- primaries bind tighter than any operator
end

-- Emit a binary operand, wrapping in parens when precedence/associativity require.
local function emitOperand(node, parentPrec, side, parentOp)
    local s = emit(node)
    local p = nodePrec(node)
    local needs = false
    if p < parentPrec then
        needs = true
    elseif p == parentPrec and node.kind == "Binary" then
        -- same precedence: the side matching associativity may stay unparenthesized
        local rightAssoc = RIGHT_ASSOC[parentOp]
        if rightAssoc and side == "left" then needs = true end
        if not rightAssoc and side == "right" then needs = true end
    end
    if needs then return "(" .. s .. ")" end
    return s
end

local function emitArgs(args)
    local parts = {}
    for _, a in ipairs(args) do parts[#parts + 1] = emit(a) end
    return table.concat(parts, ",")
end

function emit(node)
    local k = node.kind
    if k == "Nil" then return "nil" end
    if k == "True" then return "true" end
    if k == "False" then return "false" end
    if k == "Vararg" then return "..." end
    if k == "Number" then return node.value end
    if k == "String" then return node.value end
    if k == "Name" then return node.name end
    if k == "Paren" then return "(" .. emit(node.expr) .. ")" end
    if k == "Index" then
        return emitBase(node.obj) .. "[" .. emit(node.index) .. "]"
    end
    if k == "Call" then
        return emitBase(node.fn) .. "(" .. emitArgs(node.args) .. ")"
    end
    if k == "Method" then
        return emitBase(node.obj) .. ":" .. node.name .. "(" .. emitArgs(node.args) .. ")"
    end
    if k == "Unary" then
        local operand = emitOperand(node.operand, UNARY_PREC, "right", node.op)
        if node.op == "not" then return "not " .. operand end
        -- space guard so '-' / '#' never merge with a leading '-' or into '--'
        local sep = operand:sub(1, 1) == "-" and " " or ""
        return node.op .. sep .. operand
    end
    if k == "Binary" then
        local prec = BIN_PREC[node.op]
        local l = emitOperand(node.left, prec, "left", node.op)
        local r = emitOperand(node.right, prec, "right", node.op)
        local op = node.op
        -- word operators and '..' need surrounding spaces; others are safe tight
        -- but we space everything to avoid accidental token merges (minifier tightens later).
        if op == "and" or op == "or" then
            return l .. " " .. op .. " " .. r
        end
        return l .. " " .. op .. " " .. r
    end
    if k == "Table" then
        local parts = {}
        for _, f in ipairs(node.fields) do
            if f.key then
                parts[#parts + 1] = "[" .. emit(f.key) .. "]=" .. emit(f.value)
            else
                parts[#parts + 1] = emit(f.value)
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    if k == "Function" then
        return joinTokensVerbatim(node.tokens)
    end
    error("ExprAST: cannot emit node kind '" .. tostring(k) .. "'")
end

-- A base position (callee/indexee) must be parenthesized if it is an operator
-- expression or a function/table/literal that isn't a valid prefix on its own.
function emitBase(node)
    local k = node.kind
    if k == "Name" or k == "Index" or k == "Call" or k == "Method" or k == "Paren" then
        return emit(node)
    end
    -- anything else (Binary, Unary, Table, Function, literals, Vararg) needs parens
    -- to be used as a prefix for indexing/calling.
    return "(" .. emit(node) .. ")"
end

function EmitExprAST(node)
    return emit(node)
end

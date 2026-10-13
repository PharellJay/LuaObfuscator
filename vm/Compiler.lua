-- vm/Compiler.lua
--
-- Compiles a (leaf) Lua function's AST into bytecode for the obfuscation VM.
-- Input is a FunctionStatement node from Parser.lua; expressions inside it are
-- flat token lists that we turn into trees with BuildExprAST/BuildExprList
-- (ExprAST.lua). Output is a "proto" table:
--
--   { np = <#params>, code = { <ints> }, k = { <constant values> } }
--
-- `code` is a flat array: an opcode integer followed by its operands
-- (VM_OPARITY). Jump operands are absolute indices into `code` (1-based pc).
--
-- Scope: step 1 supports leaf functions only — no nested functions, no varargs,
-- no goto/labels, no generic-for/repeat. CanCompileFunction() enforces this so
-- ineligible functions are left native rather than miscompiled.

local BINOP = {
    ["+"] = "ADD", ["-"] = "SUB", ["*"] = "MUL", ["/"] = "DIV",
    ["%"] = "MOD", ["^"] = "POW", [".."] = "CONCAT",
    ["=="] = "EQ", ["~="] = "NE", ["<"] = "LT", ["<="] = "LE",
    [">"] = "GT", [">="] = "GE",
    ["|"] = "BOR", ["~"] = "BXOR", ["&"] = "BAND",
    ["<<"] = "SHL", [">>"] = "SHR", ["//"] = "IDIV",
}
local UNOP = { ["-"] = "UNM", ["not"] = "NOT", ["#"] = "LEN", ["~"] = "BNOT" }

-- ─── Eligibility ───────────────────────────────────────────────────────────
-- Conservative token scan over a function body: reject anything the step-1 VM
-- cannot yet compile correctly.
-- Light structural pre-filter. The authoritative check is attempting the
-- compile under pcall (VirtualizeAST): anything the compiler cannot handle
-- throws, and the function is left native. So this only needs to reject
-- statement forms the compiler has no case for (goto/labels/repeat), to avoid
-- wasted work; nested functions and vararg/function tokens are now allowed.
local function stmtListEligible(stmts)
    for _, s in ipairs(stmts) do
        local t = s.type
        if s.body and not stmtListEligible(s.body) then return false end
        if s.clauses then
            for _, c in ipairs(s.clauses) do
                if c.body and not stmtListEligible(c.body) then return false end
            end
        end
        if s.elseBody and not stmtListEligible(s.elseBody) then return false end
    end
    return true
end

-- Extract parameter names from a FunctionStatement head: NAME ( p1 , p2 ... )
-- Returns {names}, or nil if the head is not a plain `name(params)` (e.g. has
-- `.`/`:` or a vararg), which step 1 does not virtualize.
local function parseHead(head)
    local names = {}
    local isVararg = false
    local i = 1
    -- function name token(s)
    if not (head[i] and head[i].type == "IDENTIFIER") then return nil end
    i = i + 1
    if head[i] and head[i].type == "SYMBOL" and (head[i].value == "." or head[i].value == ":") then
        return nil -- method/field function, not a simple global name
    end
    if not (head[i] and head[i].value == "(") then return nil end
    i = i + 1
    while head[i] and head[i].value ~= ")" do
        local t = head[i]
        if t.type == "IDENTIFIER" then
            names[#names + 1] = t.value
        elseif t.value == "..." then
            isVararg = true
        end
        i = i + 1
    end
    return names, head[1].value, isVararg
end

function CanCompileFunction(funcNode)
    if funcNode.type ~= "FunctionStatement" then return false end
    if funcNode.isLocal then return false end -- step 1: global-name functions only
    local params, name = parseHead(funcNode.head)
    if not params or not name then return false end
    return stmtListEligible(funcNode.body)
end

-- ─── Compiler core ─────────────────────────────────────────────────────────
local function newCompiler(parent)
    local C = {
        code = {},
        k = {},            -- constant list
        kmap = {},         -- dedup for hashable constants
        scopes = {},       -- stack of name->cell-id maps
        ncells = 0,        -- user-local cell count (cells are boxed, capturable)
        nslots = 0,        -- raw temp/control slot count (never captured)
        breakStack = {},   -- stack of lists of jump-operand slots to patch to loop exit
        protos = {},       -- child function protos (for CLOSURE)
        parent = parent,   -- enclosing compiler, for upvalue resolution
        up = {},           -- this function's upvalue capture descriptors
        upmap = {},        -- name -> upvalue index (dedup)
        labels = {},       -- label name -> code pc (goto targets)
        pendingGotos = {}, -- forward gotos to patch once labels are known
    }
    return C
end

-- Opcode value to emit: permuted this build when VM_ACTIVE_PERM is set.
local function opcodeValue(op)
    local c = VM_OP[op]
    if VM_ACTIVE_PERM then return VM_ACTIVE_PERM[c] end
    return c
end

local function emit(C, op, ...)
    C.code[#C.code + 1] = opcodeValue(op)
    for _, v in ipairs({ ... }) do C.code[#C.code + 1] = v end
end
-- emit an opcode with a single to-be-patched operand; returns the operand's index
local function emitJmp(C, op)
    C.code[#C.code + 1] = opcodeValue(op)
    C.code[#C.code + 1] = 0
    return #C.code
end
local function here(C) return #C.code + 1 end
local function patch(C, slot, target) C.code[slot] = target end

local function addConst(C, value)
    local tv = type(value)
    if tv == "number" or tv == "string" or tv == "boolean" then
        local key = tv .. "\0" .. tostring(value)
        local idx = C.kmap[key]
        if idx then return idx end
        C.k[#C.k + 1] = value
        C.kmap[key] = #C.k
        return #C.k
    end
    C.k[#C.k + 1] = value
    return #C.k
end

local function enterScope(C) C.scopes[#C.scopes + 1] = {} end
local function leaveScope(C) C.scopes[#C.scopes] = nil end

-- A user local/param lives in a CELL (box), referenced by a cell id. Closures
-- capture the cell by reference, so mutations are shared. declareLocal allocates
-- the id and records it in the current scope; the caller emits NEWCELL where the
-- binding actually comes into existence (so loop bodies get a fresh cell each
-- iteration).
local function declareLocal(C, name)
    local id = C.ncells
    C.ncells = C.ncells + 1
    C.scopes[#C.scopes][name] = id
    return id
end
-- A raw slot holds compiler temporaries and loop control values (never captured).
local function allocTemp(C)
    local slot = C.nslots
    C.nslots = C.nslots + 1
    return slot
end
-- Resolve a name to a cell id in THIS function's own scopes (not enclosing).
local function resolveCell(C, name)
    for i = #C.scopes, 1, -1 do
        local s = C.scopes[i][name]
        if s ~= nil then return s end
    end
    return nil
end

-- Resolve `name` as an upvalue of C: returns C's upvalue index, adding a capture
-- descriptor if needed. A descriptor is {l=<parent cell id>} when the immediate
-- parent owns the variable, or {u=<parent upvalue index>} for transitive capture
-- through multiple nesting levels. Returns nil if `name` is not an enclosing local.
local function resolveUpvalue(C, name)
    if not C.parent then return nil end
    if C.upmap[name] then return C.upmap[name] end
    local pcell = resolveCell(C.parent, name)
    if pcell ~= nil then
        C.up[#C.up + 1] = { l = pcell }
        C.upmap[name] = #C.up
        return #C.up
    end
    local pup = resolveUpvalue(C.parent, name)
    if pup then
        C.up[#C.up + 1] = { u = pup }
        C.upmap[name] = #C.up
        return #C.up
    end
    return nil
end

-- Evaluate a literal lexeme (as produced by the lexer) to its runtime value.
local function literalValue(lexeme)
    local f = load("return " .. lexeme)
    if not f then error("VM compiler: bad literal " .. tostring(lexeme)) end
    return f()
end

local compileExpr, compileExprMulti, compileStmtList

local function isMultiNode(node)
    local k = node.kind
    return k == "Call" or k == "Method" or k == "Vararg"
end

-- Compile an expression leaving exactly ONE value on the stack.
function compileExpr(C, node)
    local k = node.kind
    if k == "Number" or k == "String" then
        emit(C, "PUSHK", addConst(C, literalValue(node.value)))
    elseif k == "Nil" then
        emit(C, "PUSHNIL")
    elseif k == "True" then
        emit(C, "PUSHBOOL", 1)
    elseif k == "False" then
        emit(C, "PUSHBOOL", 0)
    elseif k == "Name" then
        local cell = resolveCell(C, node.name)
        if cell ~= nil then
            emit(C, "GETCELL", cell)
        else
            local up = resolveUpvalue(C, node.name)
            if up then
                emit(C, "GETUPVAL", up)
            else
                emit(C, "GETGLOBAL", addConst(C, node.name))
            end
        end
    elseif k == "Paren" then
        compileExpr(C, node.expr) -- truncates to 1 value, which compileExpr already guarantees
    elseif k == "Index" then
        compileExpr(C, node.obj)
        compileExpr(C, node.index)
        emit(C, "GETINDEX")
    elseif k == "Call" then
        compileCall(C, node, 1)
    elseif k == "Method" then
        compileMethod(C, node, 1)
    elseif k == "Unary" then
        compileExpr(C, node.operand)
        emit(C, UNOP[node.op])
    elseif k == "Binary" then
        if node.op == "and" or node.op == "or" then
            compileExpr(C, node.left)
            emit(C, "DUP")
            local j = emitJmp(C, node.op == "and" and "JMPIFFALSE" or "JMPIFTRUE")
            emit(C, "POP")
            compileExpr(C, node.right)
            patch(C, j, here(C))
        else
            compileExpr(C, node.left)
            compileExpr(C, node.right)
            emit(C, BINOP[node.op])
        end
    elseif k == "Table" then
        emit(C, "NEWTABLE")
        local arrayIndex = 1
        local n = #node.fields
        for idx, f in ipairs(node.fields) do
            if f.key then
                emit(C, "DUP")
                compileExpr(C, f.key)
                compileExpr(C, f.value)
                emit(C, "SETINDEX")
            elseif idx == n and isMultiNode(f.value) then
                -- trailing array field that may expand to multiple values
                emit(C, "DUP")
                emit(C, "MARK")
                compileExprMulti(C, f.value)
                emit(C, "SETLIST", arrayIndex)
            else
                emit(C, "DUP")
                emit(C, "PUSHK", addConst(C, arrayIndex))
                arrayIndex = arrayIndex + 1
                compileExpr(C, f.value)
                emit(C, "SETINDEX")
            end
        end
    elseif k == "Vararg" then
        emit(C, "VARARG1")
    elseif k == "Function" then
        if not node.body then error("VM compiler: unstructured function expression") end
        local proto = compileProtoCore(node.params, node.isVararg, node.body, C)
        C.protos[#C.protos + 1] = proto
        emit(C, "CLOSURE", #C.protos)
    else
        error("VM compiler: cannot compile expression kind " .. tostring(k))
    end
end

-- Compile an expression in "tail" position, pushing all its values (calls/methods
-- expand; everything else is a single value).
function compileExprMulti(C, node)
    if node.kind == "Call" then
        compileCall(C, node, 255)
    elseif node.kind == "Method" then
        compileMethod(C, node, 255)
    elseif node.kind == "Vararg" then
        emit(C, "VARARG_ALL")
    else
        compileExpr(C, node)
    end
end

-- Compile a comma-separated expression list; the final element expands.
local function compileExprList(C, nodes)
    if #nodes == 0 then return end
    for i = 1, #nodes - 1 do compileExpr(C, nodes[i]) end
    compileExprMulti(C, nodes[#nodes])
end

function compileCall(C, node, nres)
    compileExpr(C, node.fn)
    emit(C, "MARK")
    compileExprList(C, node.args)
    emit(C, "CALL", nres)
end

function compileMethod(C, node, nres)
    local t = allocTemp(C)
    compileExpr(C, node.obj)
    emit(C, "SETLOCAL", t)          -- evaluate receiver once
    emit(C, "GETLOCAL", t)
    emit(C, "PUSHK", addConst(C, node.name))
    emit(C, "GETINDEX")             -- fn = obj[name]
    emit(C, "MARK")
    emit(C, "GETLOCAL", t)          -- self is first argument
    compileExprList(C, node.args)
    emit(C, "CALL", nres)
end

-- assign the single value on top of stack to a target node (Name or Index).
-- For Index targets the obj/key must already have been pushed *below* the value;
-- we handle that by compiling here instead (used only by single assignment).

local function compileStmt(C, s)
    local t = s.type
    if t == "LocalStatement" then
        local names = {}
        for _, tok in ipairs((s.vars and s.vars.tokens) or {}) do
            if tok.type == "IDENTIFIER" then names[#names + 1] = tok.value end
        end
        local valNodes = s.values and BuildExprList(s.values.tokens) or {}
        -- evaluate RHS to exactly #names values via a mark + ADJUST-by-assignment
        emit(C, "MARK")
        compileExprList(C, valNodes)
        -- declare after RHS is evaluated (Lua scoping)
        local slots = {}
        for _, name in ipairs(names) do slots[#slots + 1] = declareLocal(C, name) end
        -- normalize stack to exactly #names values, then assign in reverse
        adjustAndAssign(C, slots, nil)
    elseif t == "AssignmentStatement" then
        local targets = BuildExprList(s.vars.tokens)
        local valNodes = BuildExprList(s.values.tokens)
        if #targets == 1 and targets[1].kind == "Index" then
            -- fast path: obj, key, value then SETINDEX
            compileExpr(C, targets[1].obj)
            compileExpr(C, targets[1].index)
            compileExpr(C, valNodes[1] or { kind = "Nil" })
            emit(C, "SETINDEX")
        else
            -- general multi-assign (Name and/or Index targets). Pre-evaluate each
            -- Index target's obj/key into raw temps (left to right) BEFORE the RHS,
            -- then adjust the RHS to exactly #targets values and store in reverse.
            local pre = {}
            for _, tnode in ipairs(targets) do
                if tnode.kind == "Index" then
                    local os = allocTemp(C); compileExpr(C, tnode.obj); emit(C, "SETLOCAL", os)
                    local ks = allocTemp(C); compileExpr(C, tnode.index); emit(C, "SETLOCAL", ks)
                    pre[#pre + 1] = { o = os, k = ks }
                elseif tnode.kind == "Name" then
                    pre[#pre + 1] = false
                else
                    error("VM compiler: unsupported assignment target")
                end
            end
            emit(C, "MARK")
            compileExprList(C, valNodes)
            emit(C, "ADJUST", #targets)
            for i = #targets, 1, -1 do
                if targets[i].kind == "Name" then
                    emitStoreName(C, targets[i].name)
                else
                    local vs = allocTemp(C); emit(C, "SETLOCAL", vs)
                    emit(C, "GETLOCAL", pre[i].o); emit(C, "GETLOCAL", pre[i].k)
                    emit(C, "GETLOCAL", vs); emit(C, "SETINDEX")
                end
            end
        end
    elseif t == "FunctionCallStatement" then
        local node = BuildExprAST(s.call.tokens)
        if node.kind == "Call" then
            compileCall(C, node, 0)
        elseif node.kind == "Method" then
            compileMethod(C, node, 0)
        else
            error("VM compiler: call statement is not a call")
        end
    elseif t == "ReturnStatement" then
        emit(C, "MARK")
        if s.values then compileExprList(C, BuildExprList(s.values.tokens)) end
        emit(C, "RET")
    elseif t == "IfStatement" then
        local endJumps = {}
        for _, clause in ipairs(s.clauses) do
            compileExpr(C, BuildExprAST(clause.condition.tokens))
            local toNext = emitJmp(C, "JMPIFFALSE")
            enterScope(C); compileStmtList(C, clause.body); leaveScope(C)
            endJumps[#endJumps + 1] = emitJmp(C, "JMP")
            patch(C, toNext, here(C))
        end
        if s.elseBody then
            enterScope(C); compileStmtList(C, s.elseBody); leaveScope(C)
        end
        for _, j in ipairs(endJumps) do patch(C, j, here(C)) end
    elseif t == "WhileStatement" then
        local top = here(C)
        compileExpr(C, BuildExprAST(s.condition.tokens))
        local exit = emitJmp(C, "JMPIFFALSE")
        C.breakStack[#C.breakStack + 1] = {}
        enterScope(C); compileStmtList(C, s.body); leaveScope(C)
        emit(C, "JMP", top)
        patch(C, exit, here(C))
        for _, bj in ipairs(C.breakStack[#C.breakStack]) do patch(C, bj, here(C)) end
        C.breakStack[#C.breakStack] = nil
    elseif t == "RepeatStatement" then
        -- repeat body until cond : the condition shares the body's scope, so
        -- compile it before leaving scope. Loop back while cond is false.
        local top = here(C)
        C.breakStack[#C.breakStack + 1] = {}
        enterScope(C)
        compileStmtList(C, s.body)
        compileExpr(C, BuildExprAST(s.condition.tokens))
        emit(C, "JMPIFFALSE", top)
        leaveScope(C)
        for _, bj in ipairs(C.breakStack[#C.breakStack]) do patch(C, bj, here(C)) end
        C.breakStack[#C.breakStack] = nil
    elseif t == "ForStatement" then
        compileNumericFor(C, s)
    elseif t == "ForInStatement" then
        compileGenericFor(C, s)
    elseif t == "BreakStatement" then
        local lst = C.breakStack[#C.breakStack]
        if not lst then error("VM compiler: break outside loop") end
        lst[#lst + 1] = emitJmp(C, "JMP")
    elseif t == "DoStatement" then
        enterScope(C); compileStmtList(C, s.body); leaveScope(C)
    elseif t == "LabelStatement" then
        C.labels[s.name] = here(C)
    elseif t == "GotoStatement" then
        local known = C.labels[s.label]
        if known then
            emit(C, "JMP", known) -- backward goto: target already known
        else
            local slot = emitJmp(C, "JMP") -- forward goto: patch at end of function
            C.pendingGotos[#C.pendingGotos + 1] = { slot = slot, name = s.label }
        end
    elseif t == "FunctionStatement" then
        compileNestedFunction(C, s)
    else
        error("VM compiler: cannot compile statement " .. tostring(t))
    end
end

-- A nested `local function f(...)` or `function f(...)` definition. Only a
-- simple single-name target is supported (no `a.b` / `a:b`); anything else
-- throws, so the whole outer function falls back to native.
function compileNestedFunction(C, s)
    local head = s.head
    local hi = 1
    local nameToks = {}
    while head[hi] and head[hi].value ~= "(" do nameToks[#nameToks + 1] = head[hi]; hi = hi + 1 end
    if #nameToks ~= 1 or nameToks[1].type ~= "IDENTIFIER" then
        error("VM compiler: only simple-name nested functions supported")
    end
    local name = nameToks[1].value
    local params, va = {}, false
    hi = hi + 1 -- skip '('
    while head[hi] and head[hi].value ~= ")" do
        local tk = head[hi]
        if tk.type == "IDENTIFIER" then params[#params + 1] = tk.value
        elseif tk.value == "..." then va = true end
        hi = hi + 1
    end
    if s.isLocal then
        local id = declareLocal(C, name) -- declare before body for recursion visibility
        emit(C, "NEWCELL", id)           -- cell must exist before CLOSURE captures it
        local proto = compileProtoCore(params, va, s.body, C)
        C.protos[#C.protos + 1] = proto
        emit(C, "CLOSURE", #C.protos)
        emit(C, "SETCELL", id)
    else
        local proto = compileProtoCore(params, va, s.body, C)
        C.protos[#C.protos + 1] = proto
        emit(C, "CLOSURE", #C.protos)
        emit(C, "SETGLOBAL", addConst(C, name))
    end
end

-- Store the value on top of stack into a named variable (local cell, captured
-- upvalue, or global), resolving where it lives.
function emitStoreName(C, name)
    local cell = resolveCell(C, name)
    if cell ~= nil then
        emit(C, "SETCELL", cell)
    else
        local up = resolveUpvalue(C, name)
        if up then emit(C, "SETUPVAL", up) else emit(C, "SETGLOBAL", addConst(C, name)) end
    end
end

-- Normalize the values pushed since the last MARK to exactly n values, then
-- assign them (reverse order). `declCells` = freshly declared cell ids (a
-- `local` statement: box each then store). `targets` = existing assignment
-- targets (Name or Index).
function adjustAndAssign(C, declCells, targets)
    local n = declCells and #declCells or #targets
    emit(C, "ADJUST", n)
    if declCells then
        for _, id in ipairs(declCells) do emit(C, "NEWCELL", id) end
        for i = n, 1, -1 do emit(C, "SETCELL", declCells[i]) end
    else
        for i = n, 1, -1 do
            local tnode = targets[i]
            if tnode.kind == "Name" then
                emitStoreName(C, tnode.name)
            else
                error("VM compiler: unsupported multi-assign target")
            end
        end
    end
end

function compileNumericFor(C, s)
    -- head tokens: VAR = e1 , e2 [ , e3 ]
    local head = s.head
    local varName = head[1].value
    -- split head after '=' into e1,e2,e3 by top-level commas
    local rest = {}
    for i = 3, #head do rest[#rest + 1] = head[i] end -- skip VAR and '='
    local exprLists = BuildExprList(rest)
    local base = allocTemp(C)      -- i (raw)
    allocTemp(C)                   -- limit (base+1, raw)
    allocTemp(C)                   -- step  (base+2, raw)
    allocTemp(C)                   -- current i written by FORPREP/FORLOOP (base+3, raw)
    compileExpr(C, exprLists[1]); emit(C, "SETLOCAL", base)
    compileExpr(C, exprLists[2]); emit(C, "SETLOCAL", base + 1)
    if exprLists[3] then compileExpr(C, exprLists[3]) else emit(C, "PUSHK", addConst(C, 1)) end
    emit(C, "SETLOCAL", base + 2)
    emit(C, "FORPREP", base, 0); local prepExitSlot = #C.code
    local body = here(C)
    enterScope(C)
    -- visible loop var is a fresh cell each iteration (copied from the raw slot),
    -- so closures created in the body capture distinct values.
    local varCell = declareLocal(C, varName)
    emit(C, "NEWCELL", varCell)
    emit(C, "GETLOCAL", base + 3)
    emit(C, "SETCELL", varCell)
    C.breakStack[#C.breakStack + 1] = {}
    compileStmtList(C, s.body)
    leaveScope(C)
    emit(C, "FORLOOP", base, body)
    local exit = here(C)
    patch(C, prepExitSlot, exit)
    for _, bj in ipairs(C.breakStack[#C.breakStack]) do patch(C, bj, exit) end
    C.breakStack[#C.breakStack] = nil
end

function compileGenericFor(C, s)
    -- for v1, ..., vn in explist do body end
    local varNames = {}
    for _, tok in ipairs((s.vars and s.vars.tokens) or {}) do
        if tok.type == "IDENTIFIER" then varNames[#varNames + 1] = tok.value end
    end
    local expNodes = BuildExprList((s.exps and s.exps.tokens) or {})

    -- control slots: base=iterator fn, base+1=state, base+2=control var
    local base = allocTemp(C)
    allocTemp(C) -- state
    allocTemp(C) -- control
    local varSlots = {}
    for i = 1, #varNames do varSlots[i] = allocTemp(C) end -- base+3 ..

    -- evaluate the explist to exactly 3 values, then store into fn/state/control
    emit(C, "MARK")
    compileExprList(C, expNodes)
    emit(C, "ADJUST", 3)
    emit(C, "SETLOCAL", base + 2) -- control (top)
    emit(C, "SETLOCAL", base + 1) -- state
    emit(C, "SETLOCAL", base)     -- iterator fn

    local top = here(C)
    emit(C, "TFORCALL", base, #varNames, 0)
    local exitSlot = #C.code
    enterScope(C)
    -- copy the raw iteration results into fresh per-iteration cells
    for i = 1, #varNames do
        local cell = declareLocal(C, varNames[i])
        emit(C, "NEWCELL", cell)
        emit(C, "GETLOCAL", varSlots[i])
        emit(C, "SETCELL", cell)
    end
    C.breakStack[#C.breakStack + 1] = {}
    compileStmtList(C, s.body)
    leaveScope(C)
    emit(C, "JMP", top)
    local exit = here(C)
    patch(C, exitSlot, exit)
    for _, bj in ipairs(C.breakStack[#C.breakStack]) do patch(C, bj, exit) end
    C.breakStack[#C.breakStack] = nil
end

function compileStmtList(C, stmts)
    for _, s in ipairs(stmts) do compileStmt(C, s) end
end

-- Compile params+body into a proto. `parent` is the enclosing compiler (nil at
-- top level) and drives upvalue detection. Child function protos are collected
-- in C.protos and referenced by CLOSURE operands.
function compileProtoCore(params, isVararg, body, parent)
    local C = newCompiler(parent)
    enterScope(C)
    for _, p in ipairs(params) do declareLocal(C, p) end
    compileStmtList(C, body)
    -- resolve forward gotos now that all labels in this function are known
    for _, g in ipairs(C.pendingGotos) do
        local target = C.labels[g.name]
        if not target then error("VM compiler: goto to undefined label '" .. g.name .. "'") end
        patch(C, g.slot, target)
    end
    -- implicit `return` at the end
    emit(C, "MARK")
    emit(C, "RET")
    leaveScope(C)
    return { np = #params, va = isVararg and 1 or 0, code = C.code, k = C.k, p = C.protos, up = C.up }
end

function CompileFunction(funcNode)
    local params, _, isVararg = parseHead(funcNode.head)
    return compileProtoCore(params, isVararg, funcNode.body, nil)
end

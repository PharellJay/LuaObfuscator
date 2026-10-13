-- vm/Virtualize.lua
--
-- The VM obfuscation pass. Scans the top-level chunk for eligible global
-- functions whose name begins with Config.VirtualizePrefix, compiles each to
-- bytecode, and replaces the function definition with an assignment of the form
--   NAME = <vm>(<serialized proto>)
-- A single interpreter definition is prepended to the chunk. Replacements and
-- the interpreter are emitted as RawStatement nodes (opaque Lua source), so the
-- later AST passes don't descend into them; the subsequent text passes
-- (numbers/strings/pool/minify) still obfuscate the emitted source.
--
-- Returns the (possibly) rewritten statement list. If nothing is virtualized,
-- the input is returned unchanged.

-- A top-level virtualized function has no enclosing proto, so the VM resolves
-- every free variable as a GLOBAL. That is wrong if the name is actually a
-- chunk-level local (an upvalue) — it would read nil. Detect any reference to a
-- chunk-local name anywhere in the function (conservatively, over a token scan
-- that also covers nested function bodies) so such functions stay native.
local function toksRefSet(toks, set)
    for _, t in ipairs(toks or {}) do
        if t.type == "IDENTIFIER" and set[t.value] then return true end
    end
    return false
end
local function stmtRefsSet(s, set)
    if toksRefSet(s.tokens, set) or toksRefSet(s.head, set) then return true end
    for _, fld in ipairs({ "vars", "values", "condition", "exps", "call" }) do
        if s[fld] and s[fld].tokens and toksRefSet(s[fld].tokens, set) then return true end
    end
    if s.body then for _, x in ipairs(s.body) do if stmtRefsSet(x, set) then return true end end end
    if s.clauses then
        for _, c in ipairs(s.clauses) do
            if c.condition and c.condition.tokens and toksRefSet(c.condition.tokens, set) then return true end
            if c.body then for _, x in ipairs(c.body) do if stmtRefsSet(x, set) then return true end end end
        end
    end
    if s.elseBody then for _, x in ipairs(s.elseBody) do if stmtRefsSet(x, set) then return true end end end
    return false
end
local function refsChunkLocal(funcNode, set)
    for _, s in ipairs(funcNode.body) do if stmtRefsSet(s, set) then return true end end
    return false
end

-- The assignment target for a function head, as source text, with `:` -> `.`
-- (so `function M:m(...)` assigns `M.m`). Names only (stops at `(`).
local function assignTargetFromHead(head)
    local parts = {}
    for _, t in ipairs(head) do
        if t.value == "(" then break end
        if t.type == "IDENTIFIER" then parts[#parts + 1] = t.value
        elseif t.type == "SYMBOL" and (t.value == "." or t.value == ":") then parts[#parts + 1] = "." end
    end
    return table.concat(parts)
end

function VirtualizeAST(body)
    local prefix = Config and Config.VirtualizePrefix or VirtualizePrefix
    local all = Config and Config.VirtualizeAll
    -- Nothing to do unless we have a prefix to match or all-mode is on.
    if not all and (not prefix or prefix == "") then return body end

    -- names declared `local` at the chunk's top level; a dotted/colon function
    -- whose base object is one of these can't be safely virtualized (the renamer
    -- would rewrite the base in the AST but not in our opaque replacement, and
    -- recursion would hit a nil global), so those stay native.
    local chunkLocals = {}
    for _, stmt in ipairs(body) do
        if stmt.type == "LocalStatement" and stmt.vars then
            for _, tok in ipairs(stmt.vars.tokens or {}) do
                if tok.type == "IDENTIFIER" then chunkLocals[tok.value] = true end
            end
        elseif stmt.type == "FunctionStatement" and stmt.isLocal and stmt.head[1] then
            chunkLocals[stmt.head[1].value] = true
        end
    end

    local vmName = GenerateRandomName(VariableLength or 12)
    local perm = MakeOpcodePermutation()
    local keySeed = math.random(1, 255) -- per-build constant-encryption key
    VM_ACTIVE_PERM = perm -- compiler emits permuted opcodes while this is set
    local newBody = {}
    local count = 0

    for _, stmt in ipairs(body) do
        local h = stmt.type == "FunctionStatement" and analyzeHead(stmt.head) or nil
        local eligible = h
            and CanCompileFunction(stmt)
            -- all-mode virtualizes every eligible function; otherwise match the prefix
            and (all or (prefix and prefix ~= "" and h.name:sub(1, #prefix) == prefix))
            -- dotted/colon only when the base object is a global (not a chunk local)
            and (not h.isDotted or not chunkLocals[h.base])
            -- must not reference a chunk-level local (the VM would read it as a
            -- nil global); such functions stay native
            and not refsChunkLocal(stmt, chunkLocals)
        if eligible then
            -- Compile under pcall: any unsupported construct throws and we keep
            -- the original (native) function rather than emitting broken output.
            local ok, proto = pcall(CompileFunction, stmt)
            if ok then
                local blob = SerializeProto(proto, keySeed)
                local target
                if h.isDotted then
                    target = assignTargetFromHead(stmt.head) -- e.g. M.a.vm_foo
                elseif stmt.isLocal then
                    target = "local " .. h.name               -- local function f
                else
                    target = h.name                           -- global function f
                end
                newBody[#newBody + 1] = {
                    type = "RawStatement",
                    code = target .. "=" .. vmName .. "(" .. blob .. ")",
                }
                count = count + 1
            else
                newBody[#newBody + 1] = stmt
            end
        else
            newBody[#newBody + 1] = stmt
        end
    end

    VM_ACTIVE_PERM = nil

    if count > 0 then
        local interpSrc = GenerateInterpreter(vmName, perm, keySeed)
        -- Splice the interpreter in as real AST so the later AST passes (variable
        -- renaming, dead-code injection) obfuscate its internals too — not just
        -- the text passes. Falls back to an opaque RawStatement if the project
        -- parser cannot round-trip it, so this can never break the pipeline.
        local ok, interpAst = pcall(function() return Parse(Tokenize(interpSrc)) end)
        if ok and interpAst and interpAst.body and #interpAst.body > 0 then
            for i = #interpAst.body, 1, -1 do
                table.insert(newBody, 1, interpAst.body[i])
            end
        else
            table.insert(newBody, 1, { type = "RawStatement", code = interpSrc })
        end
    end
    return newBody
end

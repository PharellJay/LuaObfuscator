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

local function functionName(funcNode)
    return funcNode.head[1] and funcNode.head[1].value
end

function VirtualizeAST(body)
    local prefix = Config and Config.VirtualizePrefix or VirtualizePrefix
    if not prefix or prefix == "" then return body end

    local vmName = GenerateRandomName(VariableLength or 12)
    local perm = MakeOpcodePermutation()
    local keySeed = math.random(1, 255) -- per-build constant-encryption key
    VM_ACTIVE_PERM = perm -- compiler emits permuted opcodes while this is set
    local newBody = {}
    local count = 0

    for _, stmt in ipairs(body) do
        if stmt.type == "FunctionStatement" and not stmt.isLocal
            and CanCompileFunction(stmt)
            and type(functionName(stmt)) == "string"
            and functionName(stmt):sub(1, #prefix) == prefix then
            local name = functionName(stmt)
            -- Compile under pcall: any unsupported construct throws and we keep
            -- the original (native) function rather than emitting broken output.
            local ok, proto = pcall(CompileFunction, stmt)
            if ok then
                local blob = SerializeProto(proto, keySeed)
                newBody[#newBody + 1] = {
                    type = "RawStatement",
                    code = name .. "=" .. vmName .. "(" .. blob .. ")",
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

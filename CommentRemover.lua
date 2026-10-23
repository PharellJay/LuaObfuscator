-- Remove Lua comments while preserving string literals verbatim. Handles both
-- line comments (`-- ...`) and LEVELED long comments (`--[==[ ... ]==]`), the
-- latter of which the old level-0 regex silently left in the stream. Long and
-- short STRING literals are copied through untouched (a `--` inside a string is
-- not a comment). Newlines are preserved so line structure (and downstream
-- line-based passes) stay intact.
function RemoveAllComments(code)
    local out = {}
    local pos = 1
    local len = #code
    while pos <= len do
        local c = code:sub(pos, pos)
        if c == '"' or c == "'" then
            -- Short string literal: copy verbatim.
            local quote = c
            local start = pos
            pos = pos + 1
            while pos <= len do
                local cc = code:sub(pos, pos)
                if cc == '\\' then
                    pos = pos + 2
                elseif cc == quote then
                    pos = pos + 1
                    break
                else
                    pos = pos + 1
                end
            end
            out[#out + 1] = code:sub(start, pos - 1)

        elseif c == '-' and code:sub(pos, pos + 1) == '--' then
            -- Comment: drop it.
            pos = pos + 2
            local eq = code:match("^%[(=*)%[", pos)
            if eq then
                -- Leveled (or level-0) long comment: skip to the matching close.
                local endPattern = "]" .. eq .. "]"
                local _, endIdx = code:find(endPattern, pos + #eq + 2, true)
                pos = endIdx and (endIdx + 1) or (len + 1)
            else
                -- Line comment: drop to end of line, keep the newline.
                local _, lineEnd = code:find("\n", pos, true)
                if lineEnd then
                    out[#out + 1] = "\n"
                    pos = lineEnd + 1
                else
                    pos = len + 1
                end
            end

        elseif c == '[' then
            -- Possible long string literal: copy verbatim if it is one.
            local eq = code:match("^%[(=*)%[", pos)
            if eq then
                local endPattern = "]" .. eq .. "]"
                local start = pos
                local _, endIdx = code:find(endPattern, pos + #eq + 2, true)
                if endIdx then
                    out[#out + 1] = code:sub(start, endIdx)
                    pos = endIdx + 1
                else
                    out[#out + 1] = code:sub(start)
                    pos = len + 1
                end
            else
                out[#out + 1] = c
                pos = pos + 1
            end

        else
            out[#out + 1] = c
            pos = pos + 1
        end
    end
    return table.concat(out)
end

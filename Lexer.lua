local KEYWORDS = {
    ["and"] = true,
    ["break"] = true,
    ["do"] = true,
    ["else"] = true,
    ["elseif"] = true,
    ["end"] = true,
    ["false"] = true,
    ["for"] = true,
    ["function"] = true,
    ["if"] = true,
    ["in"] = true,
    ["local"] = true,
    ["nil"] = true,
    ["not"] = true,
    ["or"] = true,
    ["repeat"] = true,
    ["return"] = true,
    ["then"] = true,
    ["true"] = true,
    ["until"] = true,
    ["while"] = true,
    ["goto"] = true
}

function Tokenize(code)
    local tokens = {}
    local pos = 1
    local len = #code

    while pos <= len do
        local char = code:sub(pos, pos)

        if char:match("%s") then
            local ws = code:match("^%s+", pos)
            pos = pos + #ws
        elseif char:match("[%a_]") then
            local value = code:match("^[%a_][%w_]*", pos)
            table.insert(tokens, {
                type = KEYWORDS[value] and "KEYWORD" or "IDENTIFIER",
                value = value
            })
            pos = pos + #value
        elseif char:match("%d") or (char == "." and code:sub(pos + 1, pos + 1):match("%d")) then
            -- Hexadecimal numbers, including hex FLOATS (Lua 5.2+): an optional
            -- hex fraction and/or a binary exponent `p`/`P` with a DECIMAL exponent,
            -- e.g. 0x1p4, 0x1.8p-2, 0xA.8, 0x.8, 0x1. — matched most-specific first.
            local hexValue =
                   code:match("^0[xX]%x*%.%x*[pP][%+%-]?%d+", pos) -- frac + exponent
                or code:match("^0[xX]%x+[pP][%+%-]?%d+", pos)      -- integer part + exponent
                or code:match("^0[xX]%x+%.%x*", pos)               -- 0x1. / 0x1.8
                or code:match("^0[xX]%.%x+", pos)                  -- 0x.8
                or code:match("^0[xX]%x+", pos)                    -- plain hex integer
            if hexValue then
                table.insert(tokens, { type = "NUMBER", value = hexValue })
                pos = pos + #hexValue
            else
                local value = code:match("^%d+%.%d*[eE][%+%-]?%d+", pos)
                    or code:match("^%d+[eE][%+%-]?%d+", pos)
                    or code:match("^%.%d+[eE][%+%-]?%d+", pos)
                    or code:match("^%d+%.%d*", pos)
                    or code:match("^%d+", pos)
                    or code:match("^%.%d+", pos)
                table.insert(tokens, { type = "NUMBER", value = value })
                pos = pos + #value
            end
        elseif char == '"' or char == "'" then
            local quote = char
            local endPos = pos + 1
            local isEscaped = false

            while endPos <= len do
                local c = code:sub(endPos, endPos)
                if isEscaped then
                    isEscaped = false
                elseif c == '\\' then
                    isEscaped = true
                elseif c == quote then
                    break
                end
                endPos = endPos + 1
            end

            local value = code:sub(pos, endPos)
            table.insert(tokens, { type = "STRING", value = value })
            pos = endPos + 1
        elseif char == "[" and (code:sub(pos + 1, pos + 1) == "[" or code:sub(pos + 1, pos + 1) == "=") then
            local eqMatch = code:match("^%[(=*)%[", pos)
            if eqMatch then
                local endPattern = "]" .. eqMatch .. "]"
                local startIdx, endIdx = code:find(endPattern, pos + #eqMatch + 2, true)

                if endIdx then
                    local value = code:sub(pos, endIdx)
                    table.insert(tokens, { type = "STRING", value = value })
                    pos = endIdx + 1
                else
                    table.insert(tokens, { type = "STRING", value = code:sub(pos) })
                    pos = len + 1
                end
            else
                table.insert(tokens, { type = "SYMBOL", value = "[" })
                pos = pos + 1
            end
        else
            local threeChars = code:sub(pos, pos + 2)
            local twoChars = code:sub(pos, pos + 1)

            if threeChars == "..." then
                table.insert(tokens, { type = "SYMBOL", value = threeChars })
                pos = pos + 3
            elseif twoChars == "==" or twoChars == "~=" or twoChars == "<=" or twoChars == ">=" or twoChars == ".." or twoChars == "::" or twoChars == "<<" or twoChars == ">>" or twoChars == "//" then
                table.insert(tokens, { type = "SYMBOL", value = twoChars })
                pos = pos + 2
            else
                table.insert(tokens, { type = "SYMBOL", value = char })
                pos = pos + 1
            end
        end
    end

    return tokens
end

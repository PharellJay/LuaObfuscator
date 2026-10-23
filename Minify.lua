function Minify(fullCode)
    -- Protect STRING LITERALS from the token-unaware whitespace stripping below.
    -- Minify works on raw text (collapsing newlines, stripping spaces around
    -- operators), which would otherwise mangle the CONTENTS of string literals:
    -- print("a  ==  b") -> print("a==b"), and a newline inside a [[long]] string
    -- -> a space. Swap each literal for a whitespace-free control-char
    -- placeholder, minify, then restore the literal verbatim.
    local segments = SplitCodeSegments(fullCode)
    local strings = {}
    local buf = {}
    for _, seg in ipairs(segments) do
        if seg.isString then
            strings[#strings + 1] = seg.text
            buf[#buf + 1] = "\4" .. #strings .. "\4"
        else
            buf[#buf + 1] = seg.text
        end
    end
    fullCode = table.concat(buf)

    -- Protect Lua 5.4 local attributes from the token-unaware whitespace stripping
    -- below (which would fuse the attribute's closing `>` with a following `=` into
    -- a `>=` operator). The emitter writes attributes uniquely as ` <const> ` /
    -- ` <close> ` (spaces on BOTH sides — a comparison `a<const>b` has none), so the
    -- spaced form unambiguously identifies an attribute. Swap it for a control-char
    -- placeholder that no minify rule touches, then restore it (re-spaced) at the end.
    fullCode = fullCode:gsub("%s<(const)>%s", "\1\1%1\1\1"):gsub("%s<(close)>%s", "\1\1%1\1\1")

    local lines = {}
    for line in fullCode:gmatch("[^\r\n]+") do
        local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" then
            table.insert(lines, trimmed)
        end
    end

    local result = table.concat(lines, " ")

    local operators = {"~=", "<=", ">=", "=", "%+", "%*", "/", ",", "%(", "%)", "{", "}", "%[", "%]", ";", "%."}
    for _, op in ipairs(operators) do
        result = result:gsub("%s*(" .. op .. ")%s*", "%1")
    end

    result = result:gsub("%s+", " ")

    result = result:gsub("(%d)(%.%.)", "%1 %2")
    result = result:gsub("(%.%.)(%d)", "%1 %2")

    -- Restore protected 5.4 attributes, re-spaced so `>` cannot fuse with a `=`.
    result = result:gsub("\1\1(%w+)\1\1", " <%1> ")

    -- Restore string literals verbatim.
    result = result:gsub("\4(%d+)\4", function(i) return strings[tonumber(i)] end)

    return result:gsub("^%s+", ""):gsub("%s+$", "")
end
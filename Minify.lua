function Minify(fullCode)
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

    return result:gsub("^%s+", ""):gsub("%s+$", "")
end
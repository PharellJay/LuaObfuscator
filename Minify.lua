function Minify(fullCode)
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

    return result:gsub("^%s+", ""):gsub("%s+$", "")
end
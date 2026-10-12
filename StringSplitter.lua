local function scanEscape(content, i)
    local nxt = content:sub(i + 1, i + 1)
    if nxt == 'x' then
        return i + 4
    elseif nxt == 'u' then
        local close = content:find('}', i + 2)
        return close + 1
    elseif nxt:match('%d') then
        local j = i + 2
        while j <= i + 3 and content:sub(j, j):match('%d') do j = j + 1 end
        return j
    else
        return i + 2
    end
end

local function findSafeSplit(content)
    local safe = {}
    local i = 1
    while i <= #content do
        safe[#safe + 1] = i
        if content:sub(i, i) == '\\' then
            i = scanEscape(content, i)
        else
            i = i + 1
        end
    end
    safe[#safe + 1] = #content + 1
    return safe
end

local function pickSplit(safe, contentLen)
    if #safe < 3 then return nil end
    local lo = math.max(2, math.ceil(#safe * 0.3))
    local hi = math.min(#safe - 1, math.floor(#safe * 0.7))
    if lo > hi then return nil end
    local idx = math.random(lo, hi)
    local splitAt = safe[idx] - 1
    if splitAt < 1 then splitAt = 1 end
    if splitAt >= contentLen then splitAt = contentLen - 1 end
    return splitAt
end

function SplitStrings(fullCode)
    local result = {}
    local pos = 1
    while pos <= #fullCode do
        local c = fullCode:sub(pos, pos)
        if c == '"' or c == "'" then
            local quote = c
            local strStart = pos
            pos = pos + 1
            while pos <= #fullCode do
                c = fullCode:sub(pos, pos)
                if c == '\\' then
                    pos = scanEscape(fullCode, pos)
                elseif c == quote then
                    pos = pos + 1
                    break
                else
                    pos = pos + 1
                end
            end
            local str = fullCode:sub(strStart, pos - 1)
            local content = str:sub(2, -2)
            local ok, actualStr = pcall(load("return " .. str))
            local actualLen = ok and actualStr and #actualStr or #content
            if actualLen > 40 then
                local safe = findSafeSplit(content)
                local splitAt = pickSplit(safe, #content)
                if splitAt then
                    local left = content:sub(1, splitAt)
                    local right = content:sub(splitAt + 1)
                    local replacement = '"' .. left .. '".."' .. right .. '"'
                    local idx = strStart - 1
                    while idx >= 1 and fullCode:sub(idx, idx):match('%s') do idx = idx - 1 end
                    if idx >= 1 and fullCode:sub(idx, idx) == '#' then
                        replacement = "(" .. replacement .. ")"
                    end
                    table.insert(result, replacement)
                else
                    table.insert(result, str)
                end
            else
                table.insert(result, str)
            end
        else
            table.insert(result, c)
            pos = pos + 1
        end
    end
    return table.concat(result)
end

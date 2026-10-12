-- Simulate XOR for Lua 5.1 (no bit32)
local function xor(a, b)
    local r, p = 0, 1
    while a > 0 or b > 0 do
        if a % 2 ~= b % 2 then r = r + p end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        p = p * 2
    end
    return r
end

function ToXor(bytes)
    local key = math.random(100000, 999999999)
    local enc = {}
    for _, b in ipairs(bytes) do
        table.insert(enc, xor(b, key))
    end
    local encStr = table.concat(enc, ",")
    local src = '(function(k'
    for i = 1, #bytes do
        src = src .. ',e' .. i
    end
    src = src .. ')local function x(a,b)local r,p=0,1 while a>0 or b>0 do if a%2~=b%2 then r=r+p end a=math.floor(a/2)b=math.floor(b/2)p=p*2 end return r end;return string.char(x(e1,k)'
    for i = 2, #bytes do
        src = src .. ',x(e' .. i .. ',k)'
    end
    src = src .. ')end)(' .. key .. ',' .. encStr .. ')'
    return src
end

local function EmptyString()
    if math.random(0, 1) == 1 then
        return '""'
    else
        return "''"
    end
end

local strategies = {
    { name = "xor", fn = ToXor },
}

function ObfuscateAllStrings(fullCode)
    local segments = SplitCodeSegments(fullCode)
    local result = {}

    for _, seg in ipairs(segments) do
        if seg.isString then
            local text = seg.text
            local first = text:sub(1, 1)

            if first == '"' or first == "'" then
                local content = text:sub(2, -2)
                if #content == 0 then
                    table.insert(result, EmptyString())
                else
                    local actualStr = load("return " .. text)()
                    local bytes = {}
                    for i = 1, #actualStr do
                        table.insert(bytes, actualStr:byte(i))
                    end
                    local strategy = strategies[math.random(1, #strategies)]
                    table.insert(result, strategy.fn(bytes))
                end

            else
                local content = text:match("%[=*%[(.-)%]=*%]")
                if content then
                    if #content == 0 then
                        table.insert(result, EmptyString())
                    else
                        local bytes = {}
                        for i = 1, #content do
                            table.insert(bytes, content:byte(i))
                        end
                        local strategy = strategies[math.random(1, #strategies)]
                        table.insert(result, strategy.fn(bytes))
                    end
                else
                    table.insert(result, text)
                end
            end
        else
            table.insert(result, seg.text)
        end
    end

    return table.concat(result)
end
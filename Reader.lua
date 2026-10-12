function ReadFile(path)
    local file, err = io.open(path, "rb")
    if not file then
        error("[-] Could not open file: " .. tostring(err))
    end

    local content = file:read("*all")
    file:close()
    return content
end
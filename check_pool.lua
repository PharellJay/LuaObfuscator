-- Load the preminify file and evaluate just the pool table
local code = io.open("Output/debug_preminify.lua", "rb"):read("*a")

-- Find the pool table definition: local POOLNAME = { ... };
-- It should be after the two decoder functions
local _, e1 = code:find("end;local _0x%x+=")
if not e1 then
    print("Could not find pool table start")
    return
end

-- Find the end of the pool table: }};
local poolStart = e1 + 1
local poolEnd = code:find("};", poolStart)
if not poolEnd then
    print("Could not find pool table end")
    return
end

local poolDef = code:sub(poolStart, poolEnd + 1)
-- poolDef looks like: "local _0x... = { entry1, entry2, ..., entryN };"

-- Extract pool name
local poolName = poolDef:match("local (%w+)=")

-- Build a script that evaluates the pool and checks types
local checkScript = [[
local function checkPool()
]] .. code:sub(1, e1) .. [[
]] .. poolDef .. [[

  print("Pool name: ]] .. poolName .. [[")
  print("Pool size: #" .. poolName .. " = " .. tostring(#]] .. poolName .. [[))
  
  local issueCount = 0
  for i = 1, math.min(#]] .. poolName .. [[, 5000) do
    local val = ]] .. poolName .. [[[i]
    if type(val) == "number" then
      local mt = math.type(val)
      if mt == "float" and val >= -10 and val <= 10 and val == math.floor(val) then
        print("Entry " .. i .. ": FLOAT " .. tostring(val) .. " (should be integer)")
        issueCount = issueCount + 1
        if issueCount >= 20 then break end
      end
    end
  end
  
  if issueCount == 0 then
    print("No small integer entries are float - OK")
  else
    print("Total issues found: " .. issueCount)
  end
end

local ok, err = pcall(checkPool)
if not ok then
  print("Error: " .. tostring(err))
end
]]

-- Write and run the check
local f = io.open("Output/_check_pool.lua", "w")
f:write(checkScript)
f:close()

print("Check script written, running...")
dofile("Output/_check_pool.lua")

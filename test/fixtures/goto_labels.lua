-- goto / labels
local out = {}
local i = 1
::top::
if i <= 5 then
  if i == 3 then i = i + 1; goto top end  -- skip 3
  out[#out + 1] = i
  i = i + 1
  goto top
end
print(table.concat(out, ","))

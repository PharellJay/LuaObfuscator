-- §1d: special float constants inside a virtualized function must round-trip
-- through the VM constant (de)serializer.
function vm_special()
    local a = 1e400
    local b = -1e400
    local c = 0.0
    return a, b, c
end
local a, b, c = vm_special()
print(a, b, c)
print(a == math.huge, b == -math.huge)

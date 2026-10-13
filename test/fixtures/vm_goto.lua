-- goto / labels in the VM (A3). vm_* compiled to the VM.
local function eq(a, d) print(a and ("PASS " .. d) or ("FAIL " .. d)) end

function vm_skip(n) local r = 0 for i = 1, n do if i % 2 == 0 then goto cont end r = r + i ::cont:: end return r end
function vm_back() local i, s = 0, 0 ::top:: i = i + 1 s = s + i if i < 5 then goto top end return s end
function vm_fwd(x) if x < 0 then goto neg end do return "pos" end ::neg:: return "neg" end

eq(vm_skip(6) == 9, "goto continue (odds 1+3+5)")
eq(vm_back() == 15, "backward goto loop")
eq(vm_fwd(-1) == "neg" and vm_fwd(1) == "pos", "forward goto")

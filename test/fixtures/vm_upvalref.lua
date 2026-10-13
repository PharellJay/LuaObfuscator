-- A virtualized function that references a chunk-level local would read it as a
-- nil global (no enclosing proto), so such functions must stay native. Regression
-- for that bug (surfaced by all-mode on testinput's `check`).
local function eq(a, d) print(a and ("PASS " .. d) or ("FAIL " .. d)) end

local SECRET = 1337
local counter = 0
function vm_reads_local(k) return k == SECRET end                    -- reads chunk-local -> native
function vm_mutates_local() counter = counter + 1 return counter end  -- r/w chunk-local -> native
function vm_pure(a, b) return a * b + 7 end                           -- no chunk-local -> virtualizes

eq(vm_reads_local(1337) == true and vm_reads_local(1) == false, "reads chunk local (stays native, correct)")
eq(vm_mutates_local() == 1 and vm_mutates_local() == 2, "mutates chunk local (stays native, correct)")
eq(vm_pure(6, 7) == 49, "no chunk-local -> virtualizes, correct")

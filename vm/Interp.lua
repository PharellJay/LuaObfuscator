-- vm/Interp.lua
--
-- Generates the Lua SOURCE of the VM interpreter that is emitted into the
-- obfuscated output. GenerateInterpreter(vmName) returns a string defining a
-- local function `vmName(proto)` that returns a closure running `proto`'s
-- bytecode. Opcode numbers are inlined from VM_OP so a later per-build
-- permutation only needs to change that table.
--
-- The value stack S is indexed by an explicit `top` (never #S), so nil values
-- on the stack are fine. `marks` records stack bases for variable-length
-- constructs (calls, returns, multi-assignment).

function GenerateInterpreter(vmName, perm, seed)
    local runName = GenerateRandomName(VariableLength or 12)
    local function op(name)
        local c = assert(VM_OP[name], "unknown opcode " .. name)
        return tostring(perm and perm[c] or c)
    end
    -- Build the dispatch body. Using a long if/elseif chain keyed on the opcode.
    -- Defined as a global (not a local) so that if control-flow flattening later
    -- relocates this definition into a dispatch sub-closure, the virtualized
    -- function assignments in sibling blocks can still reach it. The dispatcher
    -- preserves execution order, so the global is assigned before any use.
    local src = ([==[
function %VMNAME%(proto, upvals)
  if not proto.dec then
    local kk = proto.k
    for ci = 1, #kk do
      if type(kk[ci]) == "string" then
        local s = kk[ci]; local k = %SEED% % 256; local t = {}
        for j = 1, #s do k = (k * 31 + 7) % 256; t[j] = string.char(string.byte(s, j) ~ k) end
        kk[ci] = table.concat(t)
      end
    end
    proto.dec = true
  end
  local function %RUN%(...)
    local args = table.pack(...)
    local nargs = args.n
    local S, top = {}, 0
    local marks, mtop = {}, 0
    local slots = {}
    local cells = {}
    local code, K, np = proto.code, proto.k, proto.np
    for i = 1, np do cells[i - 1] = { args[i] } end
    local pc = 1
    while true do
      local o = code[pc]; pc = pc + 1
      if o == %PUSHK% then top = top + 1; S[top] = K[code[pc]]; pc = pc + 1
      elseif o == %PUSHNIL% then top = top + 1; S[top] = nil
      elseif o == %PUSHBOOL% then top = top + 1; S[top] = (code[pc] ~= 0); pc = pc + 1
      elseif o == %GETLOCAL% then top = top + 1; S[top] = slots[code[pc]]; pc = pc + 1
      elseif o == %SETLOCAL% then slots[code[pc]] = S[top]; S[top] = nil; top = top - 1; pc = pc + 1
      elseif o == %NEWCELL% then cells[code[pc]] = {}; pc = pc + 1
      elseif o == %GETCELL% then top = top + 1; S[top] = cells[code[pc]][1]; pc = pc + 1
      elseif o == %SETCELL% then cells[code[pc]][1] = S[top]; S[top] = nil; top = top - 1; pc = pc + 1
      elseif o == %GETUPVAL% then top = top + 1; S[top] = upvals[code[pc]][1]; pc = pc + 1
      elseif o == %SETUPVAL% then upvals[code[pc]][1] = S[top]; S[top] = nil; top = top - 1; pc = pc + 1
      elseif o == %GETGLOBAL% then top = top + 1; S[top] = _ENV[K[code[pc]]]; pc = pc + 1
      elseif o == %SETGLOBAL% then _ENV[K[code[pc]]] = S[top]; S[top] = nil; top = top - 1; pc = pc + 1
      elseif o == %GETINDEX% then local key = S[top]; local obj = S[top - 1]; S[top] = nil; top = top - 1; S[top] = obj[key]
      elseif o == %SETINDEX% then local val = S[top]; local key = S[top - 1]; local obj = S[top - 2]; S[top] = nil; S[top-1] = nil; S[top-2] = nil; top = top - 3; obj[key] = val
      elseif o == %NEWTABLE% then top = top + 1; S[top] = {}
      elseif o == %ADD% then local b = S[top]; top = top - 1; S[top] = S[top] + b
      elseif o == %SUB% then local b = S[top]; top = top - 1; S[top] = S[top] - b
      elseif o == %MUL% then local b = S[top]; top = top - 1; S[top] = S[top] * b
      elseif o == %DIV% then local b = S[top]; top = top - 1; S[top] = S[top] / b
      elseif o == %MOD% then local b = S[top]; top = top - 1; S[top] = S[top] % b
      elseif o == %POW% then local b = S[top]; top = top - 1; S[top] = S[top] ^ b
      elseif o == %CONCAT% then local b = S[top]; top = top - 1; S[top] = S[top] .. b
      elseif o == %BOR% then local b = S[top]; top = top - 1; S[top] = S[top] | b
      elseif o == %BXOR% then local b = S[top]; top = top - 1; S[top] = S[top] ~ b
      elseif o == %BAND% then local b = S[top]; top = top - 1; S[top] = S[top] & b
      elseif o == %SHL% then local b = S[top]; top = top - 1; S[top] = S[top] << b
      elseif o == %SHR% then local b = S[top]; top = top - 1; S[top] = S[top] >> b
      elseif o == %IDIV% then local b = S[top]; top = top - 1; S[top] = S[top] // b
      elseif o == %EQ% then local b = S[top]; top = top - 1; S[top] = (S[top] == b)
      elseif o == %NE% then local b = S[top]; top = top - 1; S[top] = (S[top] ~= b)
      elseif o == %LT% then local b = S[top]; top = top - 1; S[top] = (S[top] < b)
      elseif o == %LE% then local b = S[top]; top = top - 1; S[top] = (S[top] <= b)
      elseif o == %GT% then local b = S[top]; top = top - 1; S[top] = (S[top] > b)
      elseif o == %GE% then local b = S[top]; top = top - 1; S[top] = (S[top] >= b)
      elseif o == %UNM% then S[top] = -S[top]
      elseif o == %NOT% then S[top] = not S[top]
      elseif o == %LEN% then S[top] = #S[top]
      elseif o == %BNOT% then S[top] = ~S[top]
      elseif o == %MARK% then mtop = mtop + 1; marks[mtop] = top
      elseif o == %ADJUST% then
        local base = marks[mtop]; mtop = mtop - 1; local target = base + code[pc]; pc = pc + 1
        while top < target do top = top + 1; S[top] = nil end
        while top > target do S[top] = nil; top = top - 1 end
      elseif o == %CALL% then
        local nres = code[pc]; pc = pc + 1
        local base = marks[mtop]; mtop = mtop - 1
        local fn = S[base]
        local nargs = top - base
        local a = {}
        for i = 1, nargs do a[i] = S[base + i] end
        for i = base, top do S[i] = nil end
        top = base - 1
        local r = table.pack(fn(table.unpack(a, 1, nargs)))
        if nres == 255 then
          for i = 1, r.n do top = top + 1; S[top] = r[i] end
        else
          for i = 1, nres do top = top + 1; S[top] = r[i] end
        end
      elseif o == %RET% then
        local base = marks[mtop]; mtop = mtop - 1
        local n = top - base
        local r = {}
        for i = 1, n do r[i] = S[base + i] end
        return table.unpack(r, 1, n)
      elseif o == %JMP% then pc = code[pc]
      elseif o == %JMPIFFALSE% then local t = code[pc]; pc = pc + 1; local c = S[top]; S[top] = nil; top = top - 1; if not c then pc = t end
      elseif o == %JMPIFTRUE% then local t = code[pc]; pc = pc + 1; local c = S[top]; S[top] = nil; top = top - 1; if c then pc = t end
      elseif o == %POP% then S[top] = nil; top = top - 1
      elseif o == %DUP% then top = top + 1; S[top] = S[top - 1]
      elseif o == %FORPREP% then
        local base = code[pc]; local exit = code[pc + 1]; pc = pc + 2
        local i = slots[base] + 0; local limit = slots[base + 1] + 0; local step = slots[base + 2] + 0
        slots[base] = i; slots[base + 1] = limit; slots[base + 2] = step
        if (step > 0 and i > limit) or (step <= 0 and i < limit) then pc = exit else slots[base + 3] = i end
      elseif o == %FORLOOP% then
        local base = code[pc]; local target = code[pc + 1]; pc = pc + 2
        local i = slots[base] + slots[base + 2]; local limit = slots[base + 1]; local step = slots[base + 2]
        if (step > 0 and i <= limit) or (step <= 0 and i >= limit) then slots[base] = i; slots[base + 3] = i; pc = target end
      elseif o == %TFORCALL% then
        local base = code[pc]; local nvars = code[pc + 1]; local exit = code[pc + 2]; pc = pc + 3
        local r = table.pack(slots[base](slots[base + 1], slots[base + 2]))
        for i = 1, nvars do slots[base + 3 + i - 1] = r[i] end
        if slots[base + 3] == nil then pc = exit else slots[base + 2] = slots[base + 3] end
      elseif o == %VARARG_ALL% then
        for i = np + 1, nargs do top = top + 1; S[top] = args[i] end
      elseif o == %VARARG1% then
        top = top + 1; S[top] = args[np + 1]
      elseif o == %CLOSURE% then
        local cp = proto.p[code[pc]]; pc = pc + 1
        local ups = {}
        local ud = cp.up
        for i = 1, #ud do local d = ud[i]; if d.l ~= nil then ups[i] = cells[d.l] else ups[i] = upvals[d.u] end end
        top = top + 1; S[top] = %VMNAME%(cp, ups)
      elseif o == %SETLIST% then
        local start = code[pc]; pc = pc + 1
        local base = marks[mtop]; mtop = mtop - 1
        local tbl = S[base]
        for i = 1, top - base do tbl[start + i - 1] = S[base + i] end
        for i = base, top do S[i] = nil end
        top = base - 1
      end
    end
  end
  return %RUN%
end
]==]):gsub("%%([%u_][%w_]*)%%", function(name)
        if name == "VMNAME" then return vmName end
        if name == "RUN" then return runName end
        if name == "SEED" then return tostring(seed or 0) end
        return op(name)
    end)
    return src
end

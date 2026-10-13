-- vm/Opcodes.lua
--
-- Canonical instruction set for the obfuscation VM. Both the compiler
-- (vm/Compiler.lua) and the emitted interpreter (vm/Interp.lua) refer to these
-- names; the numeric values are the *canonical* encoding. Per-build opcode
-- permutation (a later hardening step) will remap these numbers consistently in
-- both the serialized bytecode and the generated interpreter, so nothing else
-- needs to change to add it.
--
-- Operand arity (number of integer operands that follow the opcode in the flat
-- code array) is fixed per opcode and documented in VM_OPARITY below.

VM_OPCODES = {
    "PUSHK",      -- push constants[a]
    "PUSHNIL",    -- push nil
    "PUSHBOOL",   -- push (a ~= 0)
    "GETLOCAL",   -- push slots[a]   (raw slot: compiler temps / loop control)
    "SETLOCAL",   -- slots[a] = pop  (raw slot)
    "NEWCELL",    -- cells[a] = { } (fresh box for a user local/param)
    "GETCELL",    -- push cells[a][1]   (user local read)
    "SETCELL",    -- cells[a][1] = pop  (user local write)
    "GETUPVAL",   -- push upvals[a][1]  (captured variable read)
    "SETUPVAL",   -- upvals[a][1] = pop (captured variable write)
    "GETGLOBAL",  -- push _ENV[constants[a]]
    "SETGLOBAL",  -- _ENV[constants[a]] = pop
    "GETINDEX",   -- key=pop, obj=pop, push obj[key]
    "SETINDEX",   -- val=pop, key=pop, obj=pop, obj[key]=val
    "NEWTABLE",   -- push {}
    "ADD", "SUB", "MUL", "DIV", "MOD", "POW", "CONCAT",
    "BOR", "BXOR", "BAND", "SHL", "SHR", "IDIV", -- bitwise/floor-div (Lua 5.3+)
    "EQ", "NE", "LT", "LE", "GT", "GE",
    "UNM", "NOT", "LEN", "BNOT",
    "MARK",       -- push current stack top onto the marks stack
    "ADJUST",     -- a=n: force exactly n values between last mark and top (pad nil / drop)
    "CALL",       -- a=nres (255 = all); fn/args taken from last mark
    "RET",        -- return values from last mark to top
    "JMP",        -- pc = a
    "JMPIFFALSE", -- cond=pop; if not cond then pc=a
    "JMPIFTRUE",  -- cond=pop; if cond then pc=a
    "POP",        -- discard top
    "DUP",        -- duplicate top
    "FORPREP",    -- a=base,b=exit: init numeric for; may jump to exit
    "FORLOOP",    -- a=base,b=body: step numeric for; jump to body if continuing
    "TFORCALL",   -- a=base,b=nvars,c=exit: generic for; call iterator, write vars, jump to exit when done
    "VARARG_ALL", -- push all of the function's varargs (tail/multi context)
    "VARARG1",    -- push the first vararg (single-value context)
    "SETLIST",    -- a=startIndex: append values from last mark into the table at the mark base, as array entries
    "CLOSURE",    -- a=child proto index: push a closure over proto.p[a] (with captured upvalues)
}

-- name -> canonical integer
VM_OP = {}
for i, name in ipairs(VM_OPCODES) do VM_OP[name] = i end

-- A fresh random bijection over 1..N mapping each canonical opcode value to the
-- value actually emitted this build. Threaded into both the compiler (which
-- emits permuted opcodes) and the interpreter (whose dispatch compares against
-- the same permuted values), so the opcode numbering differs every build.
function MakeOpcodePermutation()
    local n = #VM_OPCODES
    local arr = {}
    for i = 1, n do arr[i] = i end
    for i = n, 2, -1 do
        local j = math.random(i)
        arr[i], arr[j] = arr[j], arr[i]
    end
    return arr
end

-- operand counts
VM_OPARITY = {
    PUSHK = 1, PUSHNIL = 0, PUSHBOOL = 1,
    GETLOCAL = 1, SETLOCAL = 1, GETGLOBAL = 1, SETGLOBAL = 1,
    NEWCELL = 1, GETCELL = 1, SETCELL = 1, GETUPVAL = 1, SETUPVAL = 1,
    GETINDEX = 0, SETINDEX = 0, NEWTABLE = 0,
    ADD = 0, SUB = 0, MUL = 0, DIV = 0, MOD = 0, POW = 0, CONCAT = 0,
    BOR = 0, BXOR = 0, BAND = 0, SHL = 0, SHR = 0, IDIV = 0,
    EQ = 0, NE = 0, LT = 0, LE = 0, GT = 0, GE = 0,
    UNM = 0, NOT = 0, LEN = 0, BNOT = 0,
    MARK = 0, ADJUST = 1, CALL = 1, RET = 0,
    JMP = 1, JMPIFFALSE = 1, JMPIFTRUE = 1,
    POP = 0, DUP = 0,
    FORPREP = 2, FORLOOP = 2, TFORCALL = 3,
    VARARG_ALL = 0, VARARG1 = 0, SETLIST = 1, CLOSURE = 1,
}

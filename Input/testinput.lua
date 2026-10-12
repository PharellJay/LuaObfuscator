--[[
  Comprehensive Lua Obfuscator Test Suite
  Exercises edge cases across all major Lua features.
  Each test prints PASS or FAIL so the runner can verify.
]]

local pass = 0
local fail = 0
local function check(cond, desc)
  if cond then
    pass = pass + 1
    print("PASS: " .. desc)
  else
    fail = fail + 1
    print("FAIL: " .. desc)
  end
end

-- ── 1. Basic types ──────────────────────────────────
check(true == true, "boolean true")
check(false == false, "boolean false")
check(not false, "not false")
check(not not true, "double not")
check(nil == nil, "nil equality")
check(type(nil) == "nil", "type(nil)")
check(type(true) == "boolean", "type(boolean)")
check(type(42) == "number", "type(number)")
check(type("hi") == "string", "type(string)")
check(type({}) == "table", "type(table)")
check(type(print) == "function", "type(function)")

-- ── 2. Numbers ──────────────────────────────────────
check(42 == 42, "integer")
check(3.14 == 3.14, "float")
check(0 == 0, "zero")
check(-1 == -1, "negative")
check(1e3 == 1000, "scientific notation")
check(0xff == 255, "hex literal")
check(0x1A == 26, "hex literal uppercase")
check(0.5 + 0.5 == 1, "float addition")
check(0.1 + 0.2 ~= 0.3, "float imprecision")
check(1 / 2 == 0.5, "division")

-- ── 3. Arithmetic operators ─────────────────────────
check(2 + 3 == 5, "addition")
check(10 - 4 == 6, "subtraction")
check(3 * 7 == 21, "multiplication")
check(15 / 3 == 5, "division")
check(17 % 5 == 2, "modulo")
check(2 ^ 10 == 1024, "exponentiation")
check(-(3) == -3, "unary minus")

-- ── 4. Comparison operators ─────────────────────────
check(5 == 5, "equal")
check(5 ~= 6, "not equal")
check(5 < 10, "less than")
check(10 > 5, "greater than")
check(5 <= 5, "less equal")
check(5 >= 5, "greater equal")

-- ── 5. Logical operators ────────────────────────────
check(true and true, "and true")
check(not (true and false), "and false")
check(true or false, "or true")
check(not (false or false), "or false")
check("a" and "b" == "b", "and returns last")
check(false or "c" == "c", "or returns fallback")
check(nil or "d" == "d", "nil or default")

-- ── 6. String operations ────────────────────────────
check(#"hello" == 5, "string length (double quotes)")
check(#'hello' == 5, "string length (single quotes)")
-- We must be careful about how the obfuscator handles long strings
-- For now, just check basic string operations
local s1 = "Hello"
local s2 = "World"
check(s1 .. " " .. s2 == "Hello World", "concatenation")
check(("  trim  "):match("^%s*(.-)%s*$") == "trim", "string match")
check(("abc"):upper() == "ABC", "string.upper")
check(("ABC"):lower() == "abc", "string.lower")
check(("a,b,c"):find(",") == 2, "string.find")
check(("hello"):sub(1, 2) == "he", "string.sub")
check(("  a  "):match("^%s*(.-)%s*$") == "a", "string.match with captures")
check(tostring(123) == "123", "tostring")

-- ── 7. Variables and scope ─────────────────────────
local a = 1
check(a == 1, "local variable")
do
  local a = 2
  check(a == 2, "local shadowing inner")
end
check(a == 1, "local shadowing outer restored")
local b, c = 10, 20
check(b == 10 and c == 20, "multiple assignment")
b, c = c, b
check(b == 20 and c == 10, "swap")

-- ── 8. if / elseif / else ──────────────────────────
local ifResult
if false then
  ifResult = "wrong"
elseif false then
  ifResult = "also wrong"
else
  ifResult = "correct"
end
check(ifResult == "correct", "if-elseif-else")

if true then
  ifResult = "taken"
end
check(ifResult == "taken", "if true")

local nestedIf
if true then
  if false then
    nestedIf = "bad"
  else
    nestedIf = "good"
  end
end
check(nestedIf == "good", "nested if")

-- ── 9. while loops ─────────────────────────────────
local wc = 0
while wc < 3 do
  wc = wc + 1
end
check(wc == 3, "while loop")

-- while with break
local wb = 0
while true do
  wb = wb + 1
  if wb >= 3 then break end
end
check(wb == 3, "while with break")

-- ── 10. repeat loops ────────────────────────────────
local rc = 0
repeat
  rc = rc + 1
until rc == 3
check(rc == 3, "repeat until")

-- ── 11. numeric for loops ──────────────────────────
local sum = 0
for i = 1, 5 do
  sum = sum + i
end
check(sum == 15, "numeric for 1..5")

sum = 0
for i = 1, 10, 2 do
  sum = sum + i
end
check(sum == 25, "numeric for step 2")

-- for loop with break
local fb = 0
for i = 1, 100 do
  fb = fb + 1
  if i == 5 then break end
end
check(fb == 5, "for with break")

-- ── 12. generic for loops ──────────────────────────
local tbl = { "a", "b", "c" }
local keys = {}
for k in ipairs(tbl) do
  keys[#keys + 1] = k
end
check(keys[1] == 1 and keys[2] == 2 and keys[3] == 3, "ipairs")

local map = { x = 1, y = 2 }
local found = {}
for k, v in pairs(map) do
  found[k] = v
end
check(found.x == 1 and found.y == 2, "pairs")

-- ── 13. Tables ──────────────────────────────────────
local t1 = {}
check(t1[1] == nil, "empty table index")
t1[1] = 10
t1[2] = 20
check(t1[1] == 10 and t1[2] == 20, "table assignment")
local t2 = { 1, 2, 3, 4, 5 }
check(#t2 == 5, "table length")
local t3 = { a = 1, b = 2 }
check(t3.a == 1 and t3.b == 2, "table map syntax")
check(t3["a"] == 1, "table bracket index")
local t4 = { [1] = "one", [2] = "two" }
check(t4[2] == "two", "table computed key")
local t5 = { 1, 2, nil, 4 }
check(#t5 == 4 or #t5 == 2, "table with holes (unspecified behavior)") -- Lua < 5.3: #=2, Lua >= 5.3: #=4
local t6 = { 1, 2, 3 }
t6[#t6 + 1] = 4
check(#t6 == 4, "table append")
local t7 = {}
for i = 1, 100 do t7[i] = i end
check(#t7 == 100, "large sequential table")

-- nested tables
local nested = { { a = { b = "deep" } } }
check(nested[1].a.b == "deep", "nested table access")

-- table as map with mixed keys
local mixed = { [true] = "bool", [42] = "num", ["k"] = "str" }
check(mixed[true] == "bool", "table boolean key")
check(mixed[42] == "num", "table number key")
check(mixed["k"] == "str", "table string key")

-- ── 14. Functions ──────────────────────────────────
function add(a, b) return a + b end
check(add(3, 4) == 7, "global function")

local function sub(a, b) return a - b end
check(sub(10, 3) == 7, "local function")

-- multiple returns
local function multiRet()
  return 1, 2, 3
end
local x, y, z = multiRet()
check(x == 1 and y == 2 and z == 3, "multiple returns")

-- early return
local function earlyRet(n)
  if n < 0 then return -1 end
  return n
end
check(earlyRet(-5) == -1, "early return")
check(earlyRet(5) == 5, "normal return after early")

-- varargs
local function vararg(...)
  local args = { ... }
  return #args
end
check(vararg(1, 2, 3) == 3, "varargs count")
check(vararg() == 0, "varargs empty")

-- anonymous functions
local anon = function(x) return x * 2 end
check(anon(5) == 10, "anonymous function")

-- closures / upvalues
local function makeCounter()
  local count = 0
  return function()
    count = count + 1
    return count
  end
end
local counter = makeCounter()
check(counter() == 1, "closure first call")
check(counter() == 2, "closure second call")
check(counter() == 3, "closure third call")

-- recursion
local function fact(n)
  if n <= 1 then return 1 end
  return n * fact(n - 1)
end
check(fact(5) == 120, "recursion")

-- tail call (indirect)
local function tailRec(n, acc)
  if n == 0 then return acc end
  return tailRec(n - 1, acc * n)
end
check(tailRec(5, 1) == 120, "tail recursion")

-- function as table value (method)
local obj = { value = 42 }
function obj:get()
  return self.value
end
check(obj:get() == 42, "method call colon syntax")
check(obj.get(obj) == 42, "method call dot syntax")

-- ── 15. pcall / xpcall ─────────────────────────────
local ok1, err1 = pcall(function() error("test error") end)
check(not ok1, "pcall catches error")
check(tostring(err1):find("test error") ~= nil, "pcall error message")

local ok2, result2 = pcall(function() return "success" end)
check(ok2 and result2 == "success", "pcall success")

-- ── 16. Goto and labels ────────────────────────────
local gotoResult = 0
do
  goto skip
  gotoResult = 100
  ::skip::
  gotoResult = 200
end
check(gotoResult == 200, "goto forward")

-- goto backward (loop-like)
local gbc = 0
do
  ::loop::
  gbc = gbc + 1
  if gbc < 3 then goto loop end
end
check(gbc == 3, "goto backward (loop)")

-- ── 17. Coercion ───────────────────────────────────
check(10 + "20" == 30, "string to number coercion")
check(10 .. 20 == "1020", "number to string coercion")
check("hello" .. 42 == "hello42", "concat number to string")

-- ── 18. Short-circuit evaluation ───────────────────
local sideEffect = 0
local function effect()
  sideEffect = sideEffect + 1
  return true
end
local _ = false and effect()
check(sideEffect == 0, "short-circuit and (left false)")
_ = true or effect()
check(sideEffect == 0, "short-circuit or (left true)")
_ = true and effect()
check(sideEffect == 1, "short-circuit and evaluates right when needed")

-- ── 19. # on strings ──────────────────────────────
check(#"" == 0, "empty string length")
check(#"a" == 1, "single char string length")
check(#"\000" == 1, "null byte string length")
check(#"hello world" == 11, "multi char string length")

-- ── 20. Complex expressions ────────────────────────
check((1 + 2) * (3 + 4) == 21, "nested arithmetic with parens")
check(2 ^ 3 ^ 2 == 512, "exponentiation associativity (right)")
check(not (false or false) == true, "complex boolean")
check(1 < 2 and 2 < 3 and 3 < 4, "chained comparisons")

-- ── 21. Table library ──────────────────────────────
local tl = { 3, 1, 4, 1, 5, 9 }
table.sort(tl)
check(tl[1] == 1 and tl[#tl] == 9, "table.sort")
local tc = table.concat({ "a", "b", "c" }, ",")
check(tc == "a,b,c", "table.concat")
local ti = { 10, 20, 30 }
table.insert(ti, 40)
check(ti[4] == 40, "table.insert")
table.remove(ti, 1)
check(ti[1] == 20 and #ti == 3, "table.remove")

-- ── 22. Math library ───────────────────────────────
check(math.abs(-5) == 5, "math.abs")
check(math.floor(3.9) == 3, "math.floor")
check(math.ceil(3.1) == 4, "math.ceil")
check(math.max(1, 5, 3) == 5, "math.max")
check(math.min(1, 5, 3) == 1, "math.min")
check(math.sqrt(9) == 3, "math.sqrt")
check(math.sin(0) == 0, "math.sin")
check(math.cos(0) == 1, "math.cos")

-- ── 23. Self-reference in table constructor ────────
local t = { a = 1, b = 2 }
t.c = t.a + t.b
check(t.c == 3, "self-referencing table")

-- ── 24. Deep table nesting ─────────────────────────
local deep = {}
local cur = deep
for i = 1, 20 do
  cur.child = {}
  cur = cur.child
end
cur.value = "found"
cur = deep
for i = 1, 20 do cur = cur.child end
check(cur.value == "found", "deep table nesting (20 levels)")

-- ── 25. Multiple nested loops with break ────────────
local nl = ""
for i = 1, 3 do
  for j = 1, 3 do
    if i == 2 and j == 2 then break end
    nl = nl .. i .. j .. " "
  end
  if i == 2 then break end
end
check(nl == "11 12 13 21 ", "nested loops with break")

-- ── 26. String escapes ─────────────────────────────
check("\n" ~= "a", "newline escape")
check("\t" == "\t", "tab escape")
check("\\" == "\\", "backslash escape")
check("\"" == '"', "double quote escape")
check("'" == "'", "single quote")
check("\101" == "e", "decimal escape")
check(string.char(0x45) == "E", "hex via string.char")
check(("hello\nworld"):find("\n") ~= nil, "newline in string")

-- ── 27. Boolean coercion in conditionals ────────────
check((0 and "zero is truthy") == "zero is truthy", "0 is truthy")
check(("" and "empty string is truthy") == "empty string is truthy", "empty string is truthy")
check((nil or "nil is falsy") == "nil is falsy", "nil is falsy")
check((false or "false is falsy") == "false is falsy", "false is falsy")

-- ── 28. Simultaneous loop variable modification ────
local arr = { 1, 2, 3, 4, 5 }
local sum2 = 0
for _, v in ipairs(arr) do
  sum2 = sum2 + v
end
check(sum2 == 15, "ipairs sum")

-- ── 29. Select usage ──────────────────────────────
check(select("#", 1, 2, 3) == 3, "select #")
check(select(2, "a", "b", "c") == "b", "select index")

-- ── 30. String library edge cases ──────────────────
check(("hello"):rep(0) == "", "string.rep 0")
check(("ab"):rep(3) == "ababab", "string.rep 3")
check(("hello"):byte(1) == 104, "string.byte")
check(string.char(104, 101, 108, 108, 111) == "hello", "string.char")
check(("  hello  "):match("^%s*(.-)%s*$") == "hello", "string.trim via match")

-- ── Summary ────────────────────────────────────────
print("────────────────────────────")
print("Tests: " .. (pass + fail) .. " | PASS: " .. pass .. " | FAIL: " .. fail)
if fail > 0 then
  error("Some tests FAILED")
end

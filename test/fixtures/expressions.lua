-- Expression precedence / associativity torture test.
-- Every print must survive the token->AST->source round trip unchanged.
local function eq(a, b, d) print((a == b) and ("PASS "..d) or ("FAIL "..d.." got "..tostring(a))) end

-- arithmetic precedence
eq(2 + 3 * 4, 14, "mul over add")
eq((2 + 3) * 4, 20, "paren add")
eq(2 ^ 3 ^ 2, 512, "pow right-assoc")        -- 2^(3^2)
eq(-2 ^ 2, -4, "unary minus below pow")      -- -(2^2)
eq(2 - 3 - 4, -5, "sub left-assoc")
eq(2 - -3, 5, "sub of negative")
eq(12 % 5 % 3, 2, "mod left-assoc")
eq(10 / 2 / 5, 1, "div left-assoc")

-- concat right-assoc and mixing with arithmetic
eq("a" .. "b" .. "c", "abc", "concat chain")
eq(1 .. 2 + 3, "15", "add binds tighter than concat")  -- 1 .. (2+3) = "15"
eq("x" .. 1 .. 2, "x12", "concat right assoc")

-- comparison / logical
eq(1 + 1 == 2, true, "add vs eq")
eq(not (1 == 2), true, "not paren")
eq(true and false or true, true, "and/or precedence")
eq(1 < 2 and 2 < 3, true, "chained compares")
eq(2 < 3 == true, true, "compare vs eq")

-- length operator
eq(#"hello", 5, "length string")
eq(#("ab".."cd"), 4, "length of concat")

-- call / index chains
local t = { f = function(x) return { g = function(y) return x + y end } end }
eq(t.f(10).g(5), 15, "method-ish chain")
local a = {1, {2, {3, 4}}}
eq(a[2][2][1], 3, "nested index")

-- mixed unary
eq(- -5, 5, "double negative")
eq(not not true, true, "double not")
eq(#{1,2,3} + 1, 4, "length of table literal")

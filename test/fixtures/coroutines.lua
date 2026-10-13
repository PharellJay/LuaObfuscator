-- coroutines
local co = coroutine.create(function(a, b)
  local c = coroutine.yield(a + b)
  local d = coroutine.yield(c * 2)
  return a, b, c, d
end)
print(coroutine.resume(co, 2, 3))
print(coroutine.resume(co, 10))
print(coroutine.resume(co, 20))
print(coroutine.resume(co))
-- wrap
local gen = coroutine.wrap(function() for i = 1, 3 do coroutine.yield(i * i) end end)
print(gen(), gen(), gen())

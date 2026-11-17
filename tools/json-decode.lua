-- The JSON decoder (Core/Utils.lua), which reads text from outside the game: the site's packages in
-- the companion's inbox, a pasted soft-reserve export, a loot rule. Run against the real file:
--   * what it always read, it still reads;
--   * a number written with an exponent is read (the site's JSON writer gives 1e-7 for a small one);
--   * text that is not JSON answers nil at once. It used to stand still on a character it did not
--     expect inside a list or an object, and the game froze with it.
--
--   luajit -e 'ADDON="."' tools/json-decode.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."

local checks = 0
local function check(cond, what)
  checks = checks + 1
  if not cond then
    io.stderr:write("FAIL: " .. what .. "\n")
    os.exit(1)
  end
end

DEFAULT_CHAT_FRAME = { AddMessage = function() end }
GuildOS = { L = setmetatable({}, { __index = function(_, k) return k end }) }
dofile(ADDON .. "/Core/Utils.lua")
local decode = GuildOS.JsonDecode

-- A read that stands still never returns: each one is given a budget of steps and stopped past it.
-- The count hook only fires in interpreted code, so the compiler is off for this file.
if jit then jit.off() end
local function within(text)
  local co = coroutine.create(function() return decode(text) end)
  debug.sethook(co, function() error("stood still") end, "", 5e6)
  local ok, value = coroutine.resume(co)
  return ok, value
end

local ok, v = within('{"a":[1,{"b":"x\\"y","n":null}],"c":true,"d":false,"e":-2.5,"f":"é"}')
check(ok and v.a[1] == 1 and v.a[2].b == 'x"y' and v.a[2].n == nil and v.c == true and v.d == false and v.e == -2.5
  and v.f == "é", "objects, lists, strings with escapes, numbers, booleans and null, as always")
ok, v = within(" [ ] ")
check(ok and type(v) == "table" and #v == 0, "an empty list")
ok, v = within("{}")
check(ok and type(v) == "table" and next(v) == nil, "an empty object")

ok, v = within('{"a":1e-7,"b":2.5E3,"c":-1e+2,"d":[3e0]}')
check(ok and math.abs(v.a - 1e-7) < 1e-12 and v.b == 2500 and v.c == -100 and v.d[1] == 3, "numbers with an exponent")

for _, text in ipairs({
  '{"a":1 "b":2}', '[1 2]', '[1,,2', '{"a":x}', '{a:1}', '{"a" 1}', '{"a":1e}', '[1,2', '{"a":', "", "x", "]",
  '{"a":[1,2}', "[" .. string.rep("[", 200000),
}) do
  local done, value = within(text)
  check(done, "text that is not JSON never stands still: " .. text:sub(1, 20))
  check(value == nil, "and answers nil: " .. text:sub(1, 20))
end
check(decode(nil) == nil and decode(7) == nil and decode({}) == nil, "nothing that is not text is read")

print(("json-decode: %d checks passed"):format(checks))

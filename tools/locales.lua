-- Every one of the game's ten languages, complete and safe to format (issue #104), read straight
-- from the code and the Locales files.
--
-- The game (TBC Anniversary and WoW: Forever) runs in enUS, deDE, esES, esMX, frFR, ptBR, ruRU,
-- koKR, zhCN and zhTW, by the product config's supported_locales. English is the key itself;
-- esMX reads esES's file. For each other language this loads its file the way the client does
-- (GetLocale answering that language) and checks, for every string the code asks for:
--   * there is a translation, so a string added in English fails here until it is translated;
--   * the translation keeps the format specifiers the code fills, in order, the colour codes and
--     their |r, textures, |n and newlines, and the spaces at either end of a fragment;
-- and that the TOC loads every file.
--
--   luajit -e 'ADDON="."' tools/locales.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."

local checks, fails = 0, {}
local function check(cond, what)
  checks = checks + 1
  if not cond then fails[#fails + 1] = what end
end

-- ── The strings the code asks for ───────────────────────────────────────
local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function luaFiles()
  local list = {}
  local p = io.popen(package.config:sub(1, 1) == "\\" and ('dir /s /b "' .. ADDON .. '\\*.lua" 2>nul')
                     or ('find "' .. ADDON .. '" -name "*.lua"'))
  for line in p:lines() do
    local rel = line:gsub("\\", "/"):gsub("^.-/GuildOS/", ""):gsub("^%./", "")
    if not (rel:find("^Locales/") or rel:find("^tools/") or rel:find("^Libs/") or rel:find("/Locales/")
            or rel:find("/tools/") or rel:find("/Libs/")) then
      list[#list + 1] = line
    end
  end
  p:close()
  return list
end

local used, nUsed = {}, 0
for _, path in ipairs(luaFiles()) do
  local s = read(path) or ""
  local i = 1
  while true do
    local a = s:find('%f[%w_]L%["', i)
    if not a then break end
    local j, body = a + 3, {}
    while j <= #s do
      local c = s:sub(j, j)
      if c == "\\" then body[#body + 1] = s:sub(j, j + 1); j = j + 2
      elseif c == '"' then break
      else body[#body + 1] = c; j = j + 1 end
    end
    if s:sub(j + 1, j + 1) == "]" then
      local ok, key = pcall(function() return assert(loadstring('return "' .. table.concat(body) .. '"'))() end)
      if ok and not used[key] then used[key] = true; nUsed = nUsed + 1 end
    end
    i = j + 1
  end
end
check(nUsed > 1000, "the code's strings were found (" .. nUsed .. ")")

-- And the names WoW: Forever's profession catalog shows through L[name]: its professions and
-- crafting stations, data rather than literals in the code.
do
  BRutus = { Client = { isAnniversary = false } }
  dofile(ADDON .. "/Data/ProfCatalogForever.lua")
  local cat = BRutus.ProfCatalog or {}
  for _, p in pairs(cat.professions or {}) do
    if p.en and not used[p.en] then used[p.en] = true; nUsed = nUsed + 1 end
  end
  for _, name in pairs(cat.stations or {}) do
    if name ~= "" and not used[name] then used[name] = true; nUsed = nUsed + 1 end
  end
end

-- ── Each language as the client loads it ───────────────────────────────
-- What a language's own file says, loaded alone as the client loads it (its guard reads
-- GetLocale). enUS.lua is left out: it holds English values, which are not a translation.
local function strings(locale)
  BRutus = { L = {} }
  function GetLocale() return locale end
  for _, f in ipairs({ "ptBR", "esES", "deDE", "frFR", "ruRU", "koKR", "zhCN", "zhTW" }) do
    local path = ADDON .. "/Locales/" .. f .. ".lua"
    if read(path) then dofile(path) end
  end
  return BRutus.L
end

local function count(s, pat)
  local n = 0
  for _ in s:gmatch(pat) do n = n + 1 end
  return n
end
local function specs(s)
  local out = {}
  -- No space flag: in this addon "50% snapshots" is text, not "% s".
  for spec in s:gmatch("%%[%-+#0]*%d*%.?%d*[sdifgGxXcqoeEu%%]") do out[#out + 1] = spec end
  return table.concat(out, " ")
end
local function sameShape(key, val)
  if type(val) ~= "string" or val == "" then return "empty" end
  if specs(key) ~= specs(val) then return "format specifiers " .. specs(key) .. " became " .. specs(val) end
  if count(key, "|c%x%x%x%x%x%x%x%x") ~= count(val, "|c%x%x%x%x%x%x%x%x") then return "colour codes" end
  if count(key, "|r") ~= count(val, "|r") then return "|r" end
  if count(key, "|T") ~= count(val, "|T") or count(key, "|t") ~= count(val, "|t") then return "textures" end
  if count(key, "|n") ~= count(val, "|n") or count(key, "\n") ~= count(val, "\n") then return "line breaks" end
  -- French typography puts a space before ! ? : ; even when the fragment starts with one.
  local french = key:match("^[!?:;]") and val:sub(1, 2) == " " .. key:sub(1, 1)
  if not french and (key:match("^ +") or "") ~= (val:match("^ +") or "") then return "leading spaces" end
  if (key:match(" +$") or "") ~= (val:match(" +$") or "") then return "trailing spaces" end
  return nil
end

-- A key written twice in one file: the later silently wins, and the earlier is dead.
for _, f in ipairs({ "enUS", "ptBR", "esES", "deDE", "frFR", "ruRU", "koKR", "zhCN", "zhTW" }) do
  local seen, dups = {}, {}
  for key in ("\n" .. (read(ADDON .. "/Locales/" .. f .. ".lua") or "")):gmatch('\nL%["(.-)"%] =') do
    if seen[key] then dups[#dups + 1] = key end
    seen[key] = true
  end
  check(#dups == 0, f .. ": no key written twice (" .. table.concat(dups, ", ") .. ")")
end

local GAME = { "deDE", "esES", "esMX", "frFR", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }
for _, locale in ipairs(GAME) do
  local L = strings(locale)
  local missing, broken = 0, {}
  for key in pairs(used) do
    local val = rawget(L, key)
    if val == nil then
      missing = missing + 1
    else
      local why = sameShape(key, val)
      if why then broken[#broken + 1] = string.format("%q: %s", key, why) end
    end
  end
  check(missing == 0, locale .. ": every string the code shows is translated (" .. missing .. " still in English)")
  table.sort(broken)
  check(#broken == 0, locale .. ": every translation keeps what the code fills in\n    " .. table.concat(broken, "\n    ", 1, math.min(#broken, 8)))
end

-- English is the key, and every other client falls back to it.
BRutus = {}
function GetLocale() return "enUS" end
dofile(ADDON .. "/Locales/Locale.lua")
check(BRutus.L["Something nobody translated"] == "Something nobody translated", "enUS: a string is its own English")
local es, mx = strings("esES"), strings("esMX")
check(next(mx) ~= nil and es["Data collected."] ~= nil and mx["Data collected."] == es["Data collected."],
  "esMX reads the Spanish file")

-- ── The TOC loads every file ───────────────────────────────────────────
local toc = read(ADDON .. "/GuildOS.toc") or ""
for _, f in ipairs({ "Locale", "enUS", "ptBR", "esES", "deDE", "frFR", "ruRU", "koKR", "zhCN", "zhTW" }) do
  check(toc:find("Locales[\\/]" .. f .. "%.lua"), "the TOC loads Locales/" .. f .. ".lua")
end

if #fails > 0 then
  for _, f in ipairs(fails) do io.stderr:write("FAIL: " .. f .. "\n") end
  os.exit(1)
end
print(("locales: %d checks passed, %d strings in every one of the game's ten languages"):format(checks, nUsed))

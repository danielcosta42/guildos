-- No "BRutus" left in the addon (issue #120, spec docs/superpowers/specs/2026-10-07-ui-styles-design.md §3).
--
-- The addon was called BRutus before it was Guild OS, and the name lived on as a global alias, a saved
-- variable, a comm prefix and two slash commands. All of it is gone; this fails if any of it comes back
-- in a file git tracks. CHANGELOG.md keeps the history, Libs/ is third party, the dated specs and plans
-- under docs/superpowers/ are records of what was, and this file has to name what it looks for.
-- It also checks the two renames a typo would break silently: the key binding's method and the
-- Loot Master's addon-message prefix.
--
--   luajit -e 'ADDON="."' tools/no-brutus.lua
--
-- Exits 1 on any failed check.
ADDON = ADDON or "."

local checks, fails = 0, {}
local function check(cond, what)
  checks = checks + 1
  if not cond then fails[#fails + 1] = what end
end
local function read(rel)
  local f = io.open(ADDON .. "/" .. rel, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end
local function excepted(rel)
  return rel == "CHANGELOG.md" or rel == "tools/no-brutus.lua" or rel:find("^Libs/")
      or rel:find("^docs/superpowers/specs/") or rel:find("^docs/superpowers/plans/")
end

local files = {}
local p = io.popen('git -C "' .. ADDON .. '" ls-files')
for line in p:lines() do files[#files + 1] = line end
p:close()
check(#files > 100, "git lists the addon's files (" .. #files .. ")")

local hits = {}
for _, rel in ipairs(files) do
  if not excepted(rel) then
    local s = read(rel)
    if s and s:lower():find("brutus", 1, true) then hits[#hits + 1] = rel end
  end
end
check(#hits == 0, ("no tracked file names BRutus (%d do: %s%s)"):format(#hits,
  table.concat(hits, ", ", 1, math.min(#hits, 12)), #hits > 12 and ", …" or ""))

-- The key binding calls a method that exists.
local bindings = read("Bindings.xml") or ""
local method = bindings:match("GuildOS:(%w+)%(")
local defined = false
for _, rel in ipairs(files) do
  if method and rel:find("%.lua$") and not excepted(rel) then
    local s = read(rel)
    if s and s:find("function GuildOS:" .. method .. "(", 1, true) then defined = true end
  end
end
check(method and defined, "Bindings.xml calls GuildOS:" .. tostring(method) .. "(), which is defined")

-- The Loot Master's prefix is one constant, the same everywhere, and the client takes it.
local lm = read("Modules/LootMaster.lua") or ""
local prefix = lm:match('LootMaster%.PREFIX%s*=%s*"([^"]+)"')
check(prefix == "GuildOSLM", "LootMaster.PREFIX is \"GuildOSLM\" (got " .. tostring(prefix) .. ")")
check(prefix and #prefix <= 16, "and fits the client's 16-byte prefix limit")
local _, literals = lm:gsub('"GuildOSLM"', "")
check(literals == 1, "the prefix is written once, as the constant, and every use reads it (" .. literals .. " literals)")

if #fails > 0 then
  for _, f in ipairs(fails) do io.stderr:write("FAIL: " .. f .. "\n") end
  os.exit(1)
end
print(("no-brutus: %d checks passed"):format(checks))

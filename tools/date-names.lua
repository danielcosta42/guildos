-- Weekdays and months in the client's language (issue #307), against the real Core/Core.lua and Locales.
--
-- The game's date() writes %a %A %b %B in English on every client: a frFR calendar said
-- "Monday, 09 Nov 2026". Every date that names a day or a month goes through GuildOS:LocalDate, which
-- fills those four from the translations. This checks:
--   * no file the TOC loads calls date() (or os.date) with a format that names one, a raw string or
--     an L[] key alike: a new one fails here, naming the file and line;
--   * LocalDate writes each language's names and layout, and English exactly as date() did;
--   * every translated layout handed to LocalDate holds only conversions date() takes everywhere.
--
--   luajit -e 'ADDON="."' tools/date-names.lua
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

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- ── 1. The scan ───────────────────────────────────────────────────────────
-- Each date( call's string literals, comments skipped, with the line the call starts on. A literal
-- names a day or a month when it holds %a %A %b or %B that is not an escaped %%.
local function names(lit) return (lit:gsub("%%%%", "")):find("%%[aAbB]") ~= nil end

local function rawDates(src)
  local hits, open = {}, {}
  local i, n, line, depth = 1, #src, 1, 0
  local function literal(text)
    if #open > 0 and names(text) then hits[#hits + 1] = { line = open[#open].line, text = text } end
    local _, nl = text:gsub("\n", "")
    line = line + nl
  end
  while i <= n do
    local c = src:sub(i, i)
    if c == "\n" then
      line, i = line + 1, i + 1
    elseif c == "-" and src:sub(i, i + 1) == "--" then
      local eq = src:match("^%[(=*)%[", i + 2)
      local stop
      if eq then
        local _, e = src:find("]" .. eq .. "]", i + 2, true)
        stop = e or n
      else
        stop = (src:find("\n", i, true) or (n + 1)) - 1
      end
      local _, nl = src:sub(i, stop):gsub("\n", "")
      line, i = line + nl, stop + 1
    elseif c == "[" and src:match("^%[=*%[", i) then
      local eq = src:match("^%[(=*)%[", i)
      local s = i + #eq + 2
      local e1, e2 = src:find("]" .. eq .. "]", s, true)
      literal(src:sub(s, (e1 or n + 1) - 1))
      i = (e2 or n) + 1
    elseif c == '"' or c == "'" then
      local j, buf = i + 1, {}
      while j <= n do
        local d = src:sub(j, j)
        if d == "\\" then buf[#buf + 1] = src:sub(j, j + 1); j = j + 2
        elseif d == c or d == "\n" then break
        else buf[#buf + 1] = d; j = j + 1 end
      end
      literal(table.concat(buf))
      i = j + 1
    elseif c:match("[%a_]") then
      local word = src:match("^[%w_]+", i)
      i = i + #word
      local paren = word == "date" and src:match("^%s*%(", i)
      if paren then
        depth = depth + 1
        open[#open + 1] = { depth = depth, line = line }
        i = i + #paren
      end
    elseif c == "(" then
      depth, i = depth + 1, i + 1
    elseif c == ")" then
      if #open > 0 and open[#open].depth == depth then open[#open] = nil end
      depth, i = depth - 1, i + 1
    else
      i = i + 1
    end
  end
  return hits
end

check(#rawDates('x = date("%a %H:%M", t)') == 1, "a weekday in a date() format is found")
check(#rawDates("x = os.date('%B', t)") == 1, "os.date and single quotes too")
check(#rawDates('x = date(L["%A, %d %b %Y"], t)') == 1, "a layout from L[] handed to date() raw too")
check(#rawDates('x = date(date("%Y%m%d", t) == today and "%H:%M" or "%a %H:%M", t)') == 1,
  "a format chosen inside the call, past a date() nested in it")
local split = rawDates('\nx = date(\n  "%H:%M",\n  "%b")')
check(#split == 1 and split[1].line == 2, "named on the line the call starts")
check(#rawDates('x = date("%Y-%m-%d %H:%M", t)') == 0, "numbers and times are date()'s own")
check(#rawDates('x = date("100%%a", t)') == 0, "an escaped %% is no name")
check(#rawDates('x = GuildOS:LocalDate("%a %H:%M", t); y = update("%a")') == 0,
  "LocalDate is the way, and a word that ends in date is no call")
check(#rawDates('-- date("%a") in a comment\nx = date("%H", t) .. ("%a"):upper()') == 0,
  "a comment, and a string after the call closed, are not the call's")

-- Every file the TOC loads, outside Libs. ChehulNet is shared verbatim with other addons (issue #280).
local EXEMPT = { ["Modules/ChehulNet.lua"] = true }
local toc = assert(read(ADDON .. "/GuildOS.toc"), "no GuildOS.toc")
local scanned, found = 0, {}
for tocLine in toc:gmatch("[^\r\n]+") do
  local rel = tocLine:match("^%s*([^#]%S*%.lua)%s*$")
  rel = rel and rel:gsub("\\", "/")
  if rel and not rel:find("^Libs/") and not EXEMPT[rel] then
    local src = read(ADDON .. "/" .. rel)
    check(src ~= nil, rel .. " is on disk")
    scanned = scanned + 1
    for _, h in ipairs(rawDates(src)) do
      found[#found + 1] = string.format("%s:%d: date(%q) — use GuildOS:LocalDate", rel, h.line, h.text)
    end
  end
end
check(scanned > 100, "the TOC's files were read (" .. scanned .. ")")
check(#found == 0, "no date() names a weekday or a month in English:\n    " .. table.concat(found, "\n    "))

-- ── 2. LocalDate, in each language as the client loads it ───────────────────
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
function CreateFrame()
  local f = {}
  function f:RegisterEvent() end
  function f:SetScript() end
  return f
end
function hooksecurefunc() end
function GetBuildInfo() return "2.5.6", "60000", "", 20506 end
WOW_PROJECT_BURNING_CRUSADE_CLASSIC, WOW_PROJECT_ID = 5, 5
function GetRealmName() return "Realm" end
function GetServerTime() return os.time() end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
Enum = { SendAddonMessageResult = {} }
StaticPopupDialogs = {}
date = os.date

local LANGS = { "ptBR", "esES", "deDE", "frFR", "ruRU", "koKR", "zhCN", "zhTW", "itIT" }
local function client(locale)
  function GetLocale() return locale end
  GuildOS = { VERSION = "test" }
  dofile(ADDON .. "/Locales/Locale.lua")
  dofile(ADDON .. "/Locales/enUS.lua")
  for _, f in ipairs(LANGS) do dofile(ADDON .. "/Locales/" .. f .. ".lua") end
  dofile(ADDON .. "/Core/Core.lua")
  return GuildOS
end

local MONDAY = os.time({ year = 2026, month = 11, day = 9, hour = 20, min = 30 })
check(os.date("*t", MONDAY).wday == 2, "the fixture is a Monday")
local DETAIL, MONTH, SOON = "%A, %d %b %Y", "%b %Y", "%a %d %b, %H:%M"

local G = client("enUS")
local L = G.L
check(G:LocalDate(L[DETAIL], MONDAY) == "Monday, 09 Nov 2026", "enUS: " .. G:LocalDate(L[DETAIL], MONDAY))
for m = 1, 12 do
  for d = 1, 7 do
    local ts = os.time({ year = 2027, month = m, day = d, hour = 12 })
    local f = "%a %A %b %B %d %H:%M %Y %%a"
    check(G:LocalDate(f, ts) == os.date(f, ts), "enUS writes what date() wrote: " .. G:LocalDate(f, ts))
  end
end

local WANT = {
  frFR = { DETAIL, "Lundi 09 nov. 2026", MONTH, "novembre 2026", SOON, "Lun 09 nov., 20:30" },
  deDE = { DETAIL, "Montag, 09. Nov 2026", MONTH, "November 2026", "%a %H:%M", "Mo 20:30" },
  ptBR = { DETAIL, "Segunda-feira, 09 de nov de 2026", MONTH, "novembro de 2026", SOON, "Seg 09 nov, 20:30" },
  esES = { DETAIL, "Lunes, 09 de nov de 2026", MONTH, "noviembre de 2026" },
  esMX = { MONTH, "noviembre de 2026" },
  itIT = { DETAIL, "Lunedì 09 nov 2026", MONTH, "novembre 2026" },
  ruRU = { DETAIL, "Понедельник, 09 ноя 2026", MONTH, "ноябрь 2026" },
  koKR = { DETAIL, "2026년 11월 09일 월요일", MONTH, "2026년 11월", SOON, "11월 09일 (월) 20:30" },
  zhCN = { DETAIL, "2026年11月09日 星期一", MONTH, "2026年11月", SOON, "11月09日 周一 20:30" },
  zhTW = { DETAIL, "2026年11月09日 星期一", MONTH, "2026年11月", SOON, "11月09日 週一 20:30" },
}
for locale, want in pairs(WANT) do
  G = client(locale)
  for k = 1, #want, 2 do
    local got = G:LocalDate(G.L[want[k]], MONDAY)   -- "%a %H:%M" is no key: L hands it back as it is
    check(got == want[k + 1], locale .. ": " .. want[k] .. " is " .. want[k + 1] .. ", not " .. got)
  end
  check(G:LocalDate("%a", MONDAY) == G.L["Mon"], locale .. ": %a is the calendar grid's own weekday")
end

-- ── 3. The layouts the translations give date() ─────────────────────────────
-- Every L[] key the code hands to LocalDate, in every language: only the conversions date() takes on
-- every client (an unknown one can raise inside the game's date()), and nothing left in English.
local layouts = {}
for tocLine in toc:gmatch("[^\r\n]+") do
  local rel = tocLine:match("^%s*([^#]%S*%.lua)%s*$")
  local src = rel and not rel:find("^Libs") and read(ADDON .. "/" .. rel:gsub("\\", "/")) or ""
  for key in src:gmatch('LocalDate%(%s*L%["(.-)"%]') do layouts[key] = true end
end
check(layouts[DETAIL] and layouts[MONTH] and layouts[SOON], "the calendar's day, its month and the Dashboard's next event")
G = client("enUS")
local english = {}
for key in pairs(layouts) do english[key] = G:LocalDate(key, MONDAY) end
local SAFE = { a = true, A = true, b = true, B = true, d = true, H = true, M = true, Y = true, m = true, y = true, ["%"] = true }
local function unsafe(fmt)
  for c in fmt:gmatch("%%(.)") do if not SAFE[c] then return c end end
end
for _, locale in ipairs(LANGS) do
  G = client(locale)
  for key in pairs(layouts) do
    local val = rawget(G.L, key)
    check(type(val) == "string", locale .. ": " .. key .. " is translated")
    check(not unsafe(val), locale .. ": " .. key .. " -> " .. tostring(val) .. " takes only date()'s safe conversions")
    local out = G:LocalDate(val, MONDAY)
    check(out ~= english[key], locale .. ": " .. out .. " is not the English date")
  end
end

print(string.format("date-names: %d checks passed", checks))

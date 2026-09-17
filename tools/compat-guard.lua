-- Version-sensitive calls go through Core/Compat.lua (Rule 4, issue #10).
--
-- Scans every Lua file the TOC loads (outside Libs) and exits 1, naming each file:line, when one
-- of them reaches a listed API by name (it reads names, not expressions). Comments and string literals are blanked first, so a
-- name in a comment or an error message is not a call. Exempt: Core/Compat.lua (where the calls
-- belong), Core/Probe.lua (it records which of these APIs exist) and Modules/ChehulNet.lua (shared
-- verbatim with other addons; it cannot call into BRutus). A file the TOC lists that is not on disk
-- is a hit too.
--
--   lua5.1 tools/compat-guard.lua            (from the repository root; CI runs it in the lint job)
local ROOT = ROOT or "."
local EXEMPT = { ["Core/Compat.lua"] = true, ["Core/Probe.lua"] = true, ["Modules/ChehulNet.lua"] = true }

-- Old globals: flagged wherever the bare name appears (a call, an existence check, `"x" .. Name(...)`,
-- `_G.Name`), unless it is a field or method of something else (`Compat.GetItemInfo`, `tip:GetSpellInfo`).
local GLOBALS = {
  "GetItemInfo", "GetSpellInfo", "GetSpellTexture", "UnitBuff",
  "GetNumTalentTabs", "GetNumTalents", "GetTalentInfo", "GetNumSkillLines", "GetSkillLineInfo",
  "GetContainerNumSlots", "GetContainerItemLink", "GetContainerItemInfo", "UseContainerItem",
  "GuildRoster", "RegisterAddonMessagePrefix", "SendAddonMessage", "SendAddonMessageLogged",
  -- What a tooltip is showing: the Classic readers, and the data type the retail client
  -- registers by (issue #19). Reading one behind Compat's back is a feature that goes quiet
  -- on the other client, which is the failure this guard exists to make loud.
  "GetItem", "GetSpell", "GetUnit", "TooltipDataType",
}
-- Names only these APIs have: as a field or method of anything but Compat they are flagged too.
local API_ONLY = { GuildRoster = true, RegisterAddonMessagePrefix = true, SendAddonMessage = true,
                   SendAddonMessageLogged = true,
                   GetItem = true, GetSpell = true, GetUnit = true, TooltipDataType = true }
-- What a local named Compat may be.
local COMPAT_SOURCES = { ["BRutus.Compat"] = true, ["GuildOS.Compat"] = true, ["self.Compat"] = true }
-- Namespaces and the library only Compat may touch: flagged wherever the name appears (an alias included).
local NAMESPACES = { "C_Item", "C_Spell", "C_UnitAuras", "C_Container", "ChatThrottleLib",
                     "TooltipUtil", "TooltipDataProcessor" }

-- Blank comments and strings, keeping every newline so line numbers stay true.
local function blank(src)
  local out, i, n = {}, 1, #src
  local function keepLines(s) return (s:gsub("[^\n]", " ")) end
  while i <= n do
    local c = src:sub(i, i)
    if c == "-" and src:sub(i, i + 1) == "--" then
      local eq = src:match("^%[(=*)%[", i + 2)
      local stop
      if eq then
        local _, e = src:find("]" .. eq .. "]", i + 2, true)
        stop = e or n
      else
        stop = (src:find("\n", i, true) or (n + 1)) - 1
      end
      out[#out + 1] = keepLines(src:sub(i, stop))
      i = stop + 1
    elseif c == "[" and src:match("^%[=*%[", i) then
      local eq = src:match("^%[(=*)%[", i)
      local _, e = src:find("]" .. eq .. "]", i, true)
      e = e or n
      out[#out + 1] = keepLines(src:sub(i, e))
      i = e + 1
    elseif c == '"' or c == "'" then
      local j = i + 1
      while j <= n do
        local d = src:sub(j, j)
        if d == "\\" then j = j + 2
        elseif d == c or d == "\n" then break
        else j = j + 1 end
      end
      out[#out + 1] = keepLines(src:sub(i, j))
      i = j + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

local function isListed(name)
  for _, g in ipairs(GLOBALS) do if g == name then return true end end
  for _, ns in ipairs(NAMESPACES) do if ns == name then return true end end
  return false
end

local function scan(rel, src)
  local hits = {}
  local function hit(lineNo, what) hits[#hits + 1] = string.format("%s:%d: %s", rel, lineNo, what) end
  local raws = {}
  for raw in (src .. "\n"):gmatch("([^\n]*)\n") do raws[#raws + 1] = raw end
  local lineNo, prevTail = 0, nil
  for line in (blank(src) .. "\n"):gmatch("([^\n]*)\n") do
    lineNo = lineNo + 1
    -- A field or method is fine unless it hangs off _G, follows `..`, or `strict` names a sender off
    -- anything but Compat. A receiver ending the line above (`BRutus.Compat` then `.SendAddonMessage(`) counts.
    local function each(name, strict)
      local from = 1
      while true do
        local s, e = line:find("%f[%w_]" .. name .. "%f[^%w_]", from)
        if not s then break end
        local before = line:sub(1, s - 1)
        local sep = before:match("([%.:])%s*$")
        local recv = before:match("([%w_]+)%s*[%.:]%s*$")
        if sep and not recv and before:match("^%s*[%.:]%s*$") then recv = prevTail end
        local concat = before:match("%.%.%s*$")
        if not sep or concat or recv == "_G" or (strict and recv ~= "Compat") then hit(lineNo, name) end
        from = e + 1
      end
    end
    for _, name in ipairs(GLOBALS) do each(name, API_ONLY[name]) end
    for _, ns in ipairs(NAMESPACES) do each(ns, false) end
    -- _G or getfenv as a value (an alias, rawget(_G, ...)): lookups the checks above cannot follow.
    local from = 1
    while true do
      local s, e = line:find("%f[%w_]_G%f[^%w_]", from)
      if not s then break end
      local after = line:sub(e + 1):match("^%s*(.?)")
      if after ~= "[" and after ~= "." then hit(lineNo, "_G") end
      from = e + 1
    end
    if line:find("%f[%w_]getfenv%f[^%w_]") then hit(lineNo, "getfenv") end
    -- A Compat that is not BRutus.Compat.
    for rhs in line:gmatch("%f[%w_]Compat%s*=%s*([%w_%.]+)") do
      if not COMPAT_SOURCES[rhs] then hit(lineNo, "Compat") end
    end
    -- String indexes: blanking empties the string, so read the raw line, where the receiver is still code.
    for s, recv, name in (raws[lineNo] or ""):gmatch('()([%w_]+)%s*%[%s*["\']([%w_]+)["\']%s*%]') do
      if line:sub(s, s + #recv - 1) == recv
        and ((recv == "_G" and isListed(name)) or (API_ONLY[name] and recv ~= "Compat")) then
        hit(lineNo, name)
      end
    end
    if line:find("%S") then prevTail = line:match("([%w_]+)%s*$") end
  end
  return hits
end

local M = { scan = scan, blank = blank, EXEMPT = EXEMPT }

local function readFile(path)
  local fh = io.open(path, "rb")
  if not fh then return nil end
  local text = fh:read("*a")
  fh:close()
  return text
end

-- Every Lua file the TOC loads, outside Libs. `read(path)` returns a file's text, or nil when it is
-- not there; it defaults to the disk.
function M.files(root, read)
  read = read or readFile
  local toc = assert(read(root .. "/GuildOS.toc"), "no GuildOS.toc under " .. root)
  local list = {}
  for line in toc:gmatch("[^\r\n]+") do
    local rel = line:match("^%s*([^#]%S*%.lua)%s*$")
    if rel and not rel:find("^Libs") then list[#list + 1] = (rel:gsub("\\", "/")) end
  end
  return list
end

function M.run(root, read)
  read = read or readFile
  local all = {}
  for _, rel in ipairs(M.files(root, read)) do
    if not EXEMPT[rel] then
      local src = read(root .. "/" .. rel)
      if not src then
        all[#all + 1] = rel .. ":0: listed in the TOC but missing"
      else
        for _, h in ipairs(scan(rel, src)) do all[#all + 1] = h end
      end
    end
  end
  return all
end

if COMPAT_GUARD_LIBRARY then return M end
local hits = M.run(ROOT)
for _, h in ipairs(hits) do io.stderr:write(h .. "\n") end
if #hits > 0 then
  io.stderr:write(#hits .. " version-sensitive call(s) outside Core/Compat.lua; route them through BRutus.Compat.\n")
  os.exit(1)
end
print("compat-guard: no version-sensitive call outside Core/Compat.lua")

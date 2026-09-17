-- Index a client's Blizzard_APIDocumentationGenerated: one line per function, event and
-- table, with every Secret* field it declares.
--   luajit index_docs.lua <dir-with-documentation-lua> > index.tsv
-- Columns: kind, qualified name, secret fields (k=v;k=v), system file
local dir = arg[1]
local rows = {}
local current

local function auto()
  return setmetatable({}, { __index = function(t, k)
    local v = setmetatable({}, { __index = function() return 0 end })
    rawset(t, k, v)
    return v
  end })
end
Enum = auto()
Constants = auto()
APIDocumentation = {}
function APIDocumentation:AddDocumentationTable(t)
  local ns = t.Namespace
  local function secrets(entry)
    local out = {}
    for k, v in pairs(entry) do
      if type(k) == "string" and (k:find("Secret") or k:find("Restrict") or k == "RequiresSecureCall") then
        out[#out + 1] = k .. "=" .. tostring(v)
      end
    end
    -- Arguments and returns can carry their own Secret flags too.
    for _, list in ipairs({ entry.Arguments or {}, entry.Returns or {}, entry.Payload or {} }) do
      for _, a in ipairs(list) do
        for k, v in pairs(a) do
          if type(k) == "string" and k:find("Secret") then
            out[#out + 1] = (a.Name or "?") .. "." .. k .. "=" .. tostring(v)
          end
        end
      end
    end
    table.sort(out)
    return table.concat(out, ";")
  end
  for _, f in ipairs(t.Functions or {}) do
    rows[#rows + 1] = { "function", (ns and (ns .. ".") or "") .. f.Name, secrets(f), current }
  end
  for _, e in ipairs(t.Events or {}) do
    rows[#rows + 1] = { "event", e.LiteralName or e.Name, secrets(e), current }
  end
  for _, tb in ipairs(t.Tables or {}) do
    if tb.Type == "Enumeration" then
      for _, field in ipairs(tb.Fields or {}) do
        rows[#rows + 1] = { "enum", "Enum." .. tb.Name .. "." .. field.Name, tostring(field.EnumValue), current }
      end
    end
  end
  local tsecrets = secrets(t)
  if tsecrets ~= "" then rows[#rows + 1] = { "system", t.Name, tsecrets, current } end
end

local p = io.popen('dir /b "' .. dir:gsub("/", "\\") .. '\\*.lua"')
for name in p:lines() do
  current = name
  local chunk, err = loadfile(dir .. "/" .. name)
  if chunk then
    local ok, e = pcall(chunk)
    if not ok then io.stderr:write(name .. ": " .. tostring(e) .. "\n") end
  else
    io.stderr:write(name .. ": " .. tostring(err) .. "\n")
  end
end
p:close()

for _, r in ipairs(rows) do
  io.write(table.concat(r, "\t"), "\n")
end

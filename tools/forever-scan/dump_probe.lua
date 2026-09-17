-- Print the probe's inventory (Core/Probe.lua) as "api<TAB>name" and "event<TAB>name" lines.
--   luajit tools/forever-scan/dump_probe.lua Core/Probe.lua > inventory.tsv
BRutus = { L = setmetatable({}, { __index = function(_, k) return k end }) }
assert(loadfile(arg[1]))()
local P = BRutus.Probe
for _, n in ipairs(P.APIS) do io.write("api\t", n, "\n") end
for _, n in ipairs(P.EVENTS) do io.write("event\t", n, "\n") end

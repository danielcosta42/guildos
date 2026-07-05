-- Wires GuildOS into the shared ChehulNet presence mesh (see ChehulNet.lua).
-- GuildOS works fully standalone; this only adds cross-addon recognition. GuildOS
-- can later advertise guild/officer context here (kept empty for the skeleton).
local CN = _G.ChehulNet
if not CN then
    return
end

CN:Register("gos", function()
    return ""
end, nil)

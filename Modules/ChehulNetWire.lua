-- Wires GuildOS into the shared ChehulNet presence mesh (see ChehulNet.lua).
-- GuildOS works fully standalone; this only adds cross-addon recognition.
-- Kept thin on purpose: the GuildOS-side logic (what to advertise, what to do
-- with peers) lives in GuildOS.Mesh (Modules/Mesh.lua). Both callbacks read the
-- facade lazily, so they are safe even though Mesh.lua loads after this file.
local CN = _G.ChehulNet
if not CN then
    return
end

CN:Register("gos",
    -- caps: advertise our version (tiny + non-sensitive; it rides a public post).
    function()
        return (GuildOS and GuildOS.Mesh and GuildOS.Mesh:BuildCaps()) or ""
    end,
    -- onPeer: hand cross-addon presence to the GuildOS facade for the UI.
    function(short, peer)
        if GuildOS and GuildOS.Mesh then
            GuildOS.Mesh:OnPeer(short, peer)
        end
    end)

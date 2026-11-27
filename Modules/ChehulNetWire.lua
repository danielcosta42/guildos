-- Wires GuildOS into the shared ChehulNet presence mesh (see ChehulNet.lua).
-- GuildOS works fully standalone; this only adds cross-addon recognition.
-- Kept thin on purpose: the GuildOS-side logic (what to advertise, what to do
-- with peers) lives in GuildOS.Mesh (Modules/Mesh.lua). Both callbacks read the
-- facade lazily, so they are safe even though Mesh.lua loads after this file.
local CN = _G.ChehulNet
if not CN then
    return
end

-- Show network alerts in Guild OS's identity (gold). Forever-dismissed ids persist in our
-- SavedVariables (GuildOSDB.alertDismissed), resolved at call time (after SV load).
if CN.EnableAlerts then
    CN:EnableAlerts({
        accent = { 1.0, 0.843, 0.0 },
        title = "Guild OS",
        priority = 2,
        store = function()
            GuildOSDB = GuildOSDB or {}
            GuildOSDB.alertDismissed = GuildOSDB.alertDismissed or {}
            return GuildOSDB.alertDismissed
        end,
    })
end

-- ChehulNet v16: the campfire beacon (chehulnet#13), WoW: Forever only (the camp kits exist nowhere else). The lib
-- decides everything: nothing goes out before the player's yes, the question comes at the first fire they light
-- (never at login), and nothing at all with Warmth loaded. Guild OS keeps the answer (GuildOSDB.camps.consent) and
-- asks in its own window (GuildOS:ShowCampPrompt, UI/GuildMap.lua) through the popup queue; Settings › Profile ›
-- Privacy changes it later (CN:SetCampConsent).
if CN.EnableCamps and GuildOS and GuildOS.Client and not GuildOS.Client.isAnniversary and not GuildOS.Client.isRetail then
    CN:EnableCamps({
        store = function()
            GuildOSDB = GuildOSDB or {}
            GuildOSDB.camps = GuildOSDB.camps or {}
            return GuildOSDB.camps
        end,
        ask = function(callback)
            if GuildOS.ShowCampPrompt then GuildOS:ShowCampPrompt(callback) end
        end,
    })
end

-- LibChehulMesh v7: the Chehul clients the mesh heard outlive a /reload and start the next login's peer exchange
-- (GuildOSDB.meshPeers, name -> time()).
local Mesh = _G.ChehulMesh
if Mesh and Mesh.PeerStore then
    Mesh:PeerStore(function()
        GuildOSDB = GuildOSDB or {}
        GuildOSDB.meshPeers = GuildOSDB.meshPeers or {}
        return GuildOSDB.meshPeers
    end)
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

-- What the backoffice's DIAG (ChehulNet v11, issue #276) is told about Guild OS: the gossip, and the whisper
-- spelling its self-test kept (false: no echo came back), plus the last channel probe's verdict.
if CN.RegisterDiag then
    CN:RegisterDiag("gos", function()
        local parts = { "v=" .. tostring(GuildOS and GuildOS.VERSION or "?") }
        local gossip = GuildOS and GuildOS.ChehulGossip
        if gossip and gossip.Stats then
            local s = gossip:Stats()
            parts[#parts + 1] = string.format("wsp=%s;rounds=%d;adsIn=%d;adsOut=%d;drop=%d;gpeers=%d",
                tostring(s.whisper), s.rounds or 0, s.adsIn or 0, s.adsOut or 0, s.dropped or 0, s.peers or 0)
        end
        local ch = type(GuildOSDB) == "table" and GuildOSDB.probeChannel
        if type(ch) == "table" then
            parts[#parts + 1] = "chTimer=" .. tostring(ch.timer) .. ";chClick=" .. tostring(ch.click)
        end
        return table.concat(parts, ";")
    end)
end

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

-- ChehulNet v17: the campfire beacon (chehulnet#13), WoW: Forever only (the camp kits exist nowhere else), on unless
-- the player turned it off (default = true). The lib decides everything: the named announce goes to guild and group
-- only, the realm bus gets an ownerless sighting (off by default on PvP rulesets), and nothing at all goes with
-- Warmth loaded. At the first kit the player lights, once ever, one chat line says so and how to turn it off. Guild OS
-- keeps the answers (GuildOSDB.camps: consent, realm, noticed); Settings › Profile › Privacy and /gos campfire change
-- them (CN:SetCampConsent, CN:SetCampRealm).
if CN.EnableCamps and GuildOS and GuildOS.Client and not GuildOS.Client.isAnniversary and not GuildOS.Client.isRetail then
    CN:EnableCamps({
        store = function()
            GuildOSDB = GuildOSDB or {}
            GuildOSDB.camps = GuildOSDB.camps or {}
            return GuildOSDB.camps
        end,
        default = true,
        notice = function()
            if GuildOS.Print then
                GuildOS:Print(GuildOS.L["Your campfire shows on the map for guildmates and players with Warmth (anonymous outside your guild and group). To turn it off: /gos campfire off"])
            end
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

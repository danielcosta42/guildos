----------------------------------------------------------------------
-- Guild OS ↔ ChehulNet mesh integration (GuildOS-side facade).
--
-- The shared transport (Libs/LibChehulMesh.lua → _G.ChehulMesh) and the
-- presence protocol (Modules/ChehulNet.lua → _G.ChehulNet) ship BYTE-IDENTICAL
-- across the Chehul addon family (PartyLens, ProfessionHelper, Guild OS) and
-- must NOT carry Guild-OS-specific logic. All Guild-OS-side mesh behaviour
-- lives here and in the thin wire (Modules/ChehulNetWire.lua). This module:
--   * builds the capability string Guild OS advertises in the shared HELLO,
--   * consumes peer presence (which sibling addons a player runs, their live
--     Guild OS version) and exposes it to the UI,
--   * gives the Audit panel an observability read on the otherwise-invisible mesh.
--
-- No :Initialize() — it is a passive facade; ChehulNet drives all traffic and
-- the wire calls into us. Reads _G.ChehulNet / _G.ChehulMesh lazily so it never
-- depends on mesh load order.
----------------------------------------------------------------------
local Mesh = {}
GuildOS.Mesh = Mesh

-- Our tag in the shared mesh (must match ChehulNetWire's CN:Register call).
Mesh.TAG = "gos"

-- Friendly labels for sibling addon tags. Unknown tags fall back to the raw
-- tag, so a newly-added family member still shows up (just unlabelled).
Mesh.ADDON_LABELS = {
    gos = "Guild OS",
    pl  = "PartyLens",
    ph  = "ProfessionHelper",
}

----------------------------------------------------------------------
-- Capability string advertised in every HELLO (see ChehulNet:MergedCaps).
-- Kept tiny and non-sensitive: it rides a realm-wide, publicly-readable chat
-- post. Namespaced key ("gosv=") so it never collides with a sibling's caps.
----------------------------------------------------------------------
function Mesh:BuildCaps()
    return "gosv=" .. (GuildOS.VERSION or "0")
end

-- Pull Guild OS's advertised version out of a peer's merged caps string.
local function ParseGosVersion(caps)
    if type(caps) ~= "string" then return nil end
    return caps:match("gosv=([%d%.]+)")
end

-- Numeric semver-ish compare: -1 if a<b, 0 if equal, 1 if a>b.
local function CompareVersions(a, b)
    local function parts(v)
        local maj, min, pat = strsplit(".", v or "0")
        return tonumber(maj) or 0, tonumber(min) or 0, tonumber(pat) or 0
    end
    local a1, a2, a3 = parts(a)
    local b1, b2, b3 = parts(b)
    if a1 ~= b1 then return a1 < b1 and -1 or 1 end
    if a2 ~= b2 then return a2 < b2 and -1 or 1 end
    if a3 ~= b3 then return a3 < b3 and -1 or 1 end
    return 0
end
Mesh.CompareVersions = CompareVersions

----------------------------------------------------------------------
-- Peer lookup helpers (all read _G.ChehulNet live; safe if it's absent).
----------------------------------------------------------------------
local function ShortName(name)
    return (Ambiguate and Ambiguate(name or "", "short")) or name
end

function Mesh:GetPeer(name)
    local net = _G.ChehulNet
    if not net or not net.Peers then return nil end
    local short = ShortName(name)
    return short and net:Peers()[short] or nil
end

-- Sibling Chehul addons (excluding Guild OS itself) a member is broadcasting,
-- as a display suffix like "  · PartyLens, ProfessionHelper" — or "" if none.
function Mesh:PresenceSuffix(name)
    local p = self:GetPeer(name)
    if not p or not p.addons then return "" end
    local labels = {}
    for tag in pairs(p.addons) do
        if tag ~= self.TAG then
            labels[#labels + 1] = self.ADDON_LABELS[tag] or tag
        end
    end
    if #labels == 0 then return "" end
    table.sort(labels)
    return "  |cff66bbff\226\128\162 " .. table.concat(labels, ", ") .. "|r"
end

-- Live Guild OS version a peer is broadcasting on the mesh (realm-wide, fresher
-- than db.members for out-of-guild players). Returns version string or nil.
function Mesh:GetPeerVersion(name)
    local p = self:GetPeer(name)
    return p and ParseGosVersion(p.caps) or nil
end

----------------------------------------------------------------------
-- Observability: counts + a one-line health string for the Audit panel.
----------------------------------------------------------------------
function Mesh:PeerCount(tag)
    local net = _G.ChehulNet
    return (net and net.Count) and net:Count(tag) or 0
end

function Mesh:HealthLine()
    local mesh = _G.ChehulMesh
    return (mesh and mesh.HealthLine) and mesh:HealthLine() or "n/a"
end

----------------------------------------------------------------------
-- UI refresh listeners. ChehulNet stores every peer as HELLOs arrive; we only
-- need to nudge any open panel. Throttled so a burst of HELLOs rebuilds the UI
-- at most once every few seconds.
----------------------------------------------------------------------
Mesh.listeners = {}
local refreshPending = false

function Mesh:OnRefresh(fn)
    if type(fn) == "function" then
        self.listeners[#self.listeners + 1] = fn
    end
end

function Mesh:OnPeer(_short, _peer)
    if refreshPending then return end
    refreshPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(2, function()
            refreshPending = false
            for _, fn in ipairs(Mesh.listeners) do
                pcall(fn)
            end
        end)
    else
        refreshPending = false
    end
end

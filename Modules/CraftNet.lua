----------------------------------------------------------------------
-- CraftNet — realm-wide "who can craft this?" over the Chehul mesh.
--
-- Guild crafters are already known locally (RecipeTracker syncs the whole
-- guild's recipes), so this only adds REALM-WIDE / out-of-guild reach: a query
-- fans out over the mesh and every recipient answers FOR THEMSELVES if they can
-- craft the item. Guild-OS-side, so it lives here (not in the byte-identical
-- shared mesh files); it rides the shared transport _G.ChehulMesh.
--
-- ── OPEN PROTOCOL (shared contract; any Chehul addon may answer) ─────
--   prefix : "ChehulCraft"
--   query  : "CC1|Q|<itemId>|<queryId>"   broadcast on guild + proximity + realm
--   answer : "CC1|A|<itemId>|<queryId>|<label>"   whispered back to the asker
--            <label> = a short human tag for who/how (we send the profession
--            name); it may contain spaces but never a '|'.
--   <queryId> is opaque to responders — echo it back verbatim so the asker can
--   route the answer to the right in-flight query. Answer only for the LOCAL
--   player. ProfessionHelper (or any sibling) can answer the same queries by
--   registering the same prefix and replying in this format.
--
-- Realm delivery is hardware-click-gated and slow (~1 msg/1.5s), so answers
-- trickle in — the caller gets an onUpdate callback per responder, not a
-- single synchronous result.
----------------------------------------------------------------------
local CraftNet = {}
GuildOS.CraftNet = CraftNet

CraftNet.PREFIX = "ChehulCraft"  -- shared suite-level prefix
CraftNet.PROTO  = "CC1"          -- protocol tag (bump if the wire format changes)
CraftNet.TTL    = 45             -- seconds an in-flight query stays open

-- [queryId] = { itemId, results = { [shortName] = label }, onUpdate, ts }
CraftNet.active = {}
local queryCounter = 0

local function ShortName(name)
    return (Ambiguate and Ambiguate(name or "", "short")) or name
end

----------------------------------------------------------------------
-- Register our receive handler on the shared transport. Safe to call once
-- at login; no-op if the mesh library is absent.
----------------------------------------------------------------------
function CraftNet:Initialize()
    local mesh = _G.ChehulMesh
    if not mesh or self._registered then return end
    self._registered = true
    mesh:Register(self.PREFIX, function(payload, sender, dist)
        CraftNet:OnMessage(payload, sender, dist)
    end)
end

----------------------------------------------------------------------
-- Fire a realm-wide crafter query for itemId.
-- onUpdate(shortName, label, dist, query) fires once per distinct responder.
-- Returns the queryId, or nil if the mesh is unavailable.
----------------------------------------------------------------------
function CraftNet:Query(itemId, onUpdate)
    itemId = tonumber(itemId)
    local mesh = _G.ChehulMesh
    if not itemId or not mesh then return nil end

    queryCounter = queryCounter + 1
    local qid = (UnitName("player") or "?") .. "#" .. queryCounter
    self.active[qid] = { itemId = itemId, results = {}, onUpdate = onUpdate, ts = time() }

    local payload = table.concat({ self.PROTO, "Q", itemId, qid }, "|")
    mesh:Guild(self.PREFIX, payload)                        -- hidden, fast
    mesh:Proximity(self.PREFIX, payload)                    -- hidden, nearby
    mesh:Realm(self.PREFIX, payload, self.PREFIX .. ":" .. qid)  -- slow, coalesced

    if C_Timer and C_Timer.After then
        C_Timer.After(self.TTL, function() CraftNet.active[qid] = nil end)
    end
    return qid
end

----------------------------------------------------------------------
-- Inbound query/answer routing (registered handler).
----------------------------------------------------------------------
function CraftNet:OnMessage(payload, sender, dist)
    if type(payload) ~= "string" or not sender then return end
    local proto, op, itemIdStr, qid, label = strsplit("|", payload)
    if proto ~= self.PROTO then return end

    local itemId = tonumber(itemIdStr)
    local isSelf = ShortName(sender) == UnitName("player")

    if op == "Q" then
        -- Answer only for ourselves, and never answer our own broadcast.
        if isSelf or not itemId or not qid then return end
        local rt = BRutus.RecipeTracker
        local prof = rt and rt.LocalCrafts and rt:LocalCrafts(itemId)
        if prof then
            local reply = table.concat({ self.PROTO, "A", itemId, qid, prof }, "|")
            local mesh = _G.ChehulMesh
            if mesh then mesh:Whisper(self.PREFIX, reply, sender) end
        end

    elseif op == "A" then
        if isSelf then return end
        local q = self.active[qid]
        if not q or q.itemId ~= itemId then return end
        local short = ShortName(sender)
        if q.results[short] then return end  -- already counted this responder
        q.results[short] = label or "?"
        if q.onUpdate then pcall(q.onUpdate, short, label or "?", dist, q) end
    end
end

----------------------------------------------------------------------
-- Guild OS - Feature registry
-- One entry per feature: what it is called, where it shows up, how big
-- its window is and how to build it. Single source of truth for the hub,
-- the expanded-mode tab bar, the minimap menu, the slash commands and the
-- Settings toggles. Frame-free on purpose: this file only holds data and
-- predicates, so it is testable without a live UI.
----------------------------------------------------------------------
local UI = BRutus.UI

UI.features     = {}   -- id -> def
UI.featureOrder = {}   -- ids, kept sorted by def.order

----------------------------------------------------------------------
-- Register a feature. Later duplicates are ignored with a printed
-- warning rather than an error: a bad entry must never take the whole
-- addon down at load time.
----------------------------------------------------------------------
function UI:RegisterFeature(def)
    if type(def) ~= "table" or type(def.id) ~= "string" or def.id == "" then
        BRutus:Print("|cffFF4444Feature registry: entry without an id ignored.|r")
        return nil
    end
    if self.features[def.id] then
        BRutus:Print("|cffFF4444Feature registry: duplicate id '" .. def.id .. "' ignored.|r")
        return nil
    end
    if def.hub == nil then def.hub = true end
    if def.tab == nil then def.tab = true end
    def.order = def.order or (#self.featureOrder + 1) * 10

    self.features[def.id] = def
    self.featureOrder[#self.featureOrder + 1] = def.id
    table.sort(self.featureOrder, function(a, b)
        return self.features[a].order < self.features[b].order
    end)
    return def
end

function UI:GetFeature(id)
    if type(id) ~= "string" then return nil end
    return self.features[id]
end

----------------------------------------------------------------------
-- Ordered defs for a surface, filtered by rank and condition but NOT by
-- the on/off toggle. `scope` narrows to a surface:
--   "hub" -> rows in the hub / floating windows
--   "tab" -> tabs in expanded mode
--   nil   -> every feature, background modules included
--
-- The Settings toggle list and the expanded-mode tab construction both
-- need this rather than VisibleFeatures: a disabled feature must keep
-- its checkbox (or there is no way to switch it back on) and must keep
-- its tab frame (or re-enabling could never show it again).
----------------------------------------------------------------------
function UI:AllFeatures(scope)
    local out = {}
    for _, id in ipairs(self.featureOrder) do
        local def = self.features[id]
        local ok = true
        if def.officerOnly and not BRutus:IsOfficer() then ok = false end
        if ok and def.condition and not def.condition() then ok = false end
        if ok and scope and not def[scope] then ok = false end
        if ok then out[#out + 1] = def end
    end
    return out
end

-- What the user may see AND has switched on: hub rows, minimap menu.
function UI:VisibleFeatures(scope)
    local out = {}
    for _, def in ipairs(self:AllFeatures(scope)) do
        if BRutus:IsFeatureEnabled(def.id) then out[#out + 1] = def end
    end
    return out
end

----------------------------------------------------------------------
-- May this player open this feature right now? The single gate every
-- opener asks: the hub window, the expanded-mode tab, the slash verb.
-- `condition` overrides `officerOnly` when present, matching how
-- CreateTab has always treated the pair.
----------------------------------------------------------------------
function UI:IsFeatureAllowed(def)
    if not def then return false end
    if not BRutus:IsFeatureEnabled(def.id) then return false end
    if def.condition then return def.condition() end
    if def.officerOnly then return BRutus:IsOfficer() end
    return true
end

-- Overridden in UI/Window.lua once windows exist; a no-op until then so
-- SetFeatureEnabled can call it unconditionally.
function UI:OnFeatureToggled(_, _) end

function UI:_RegisterFeatureTests()
    if not BRutus.SelfTest then return end
    local S = BRutus.SelfTest

    S:Register("features.invariants", function()
        for _, id in ipairs(UI.featureOrder) do
            local d = UI.features[id]
            if type(d.label) ~= "string" or d.label == "" then
                return false, id .. ": missing label"
            end
            if d.hub then
                if type(d.build) ~= "function" then return false, id .. ": hub feature needs build()" end
                if type(d.w) ~= "number" or d.w <= 0 then return false, id .. ": bad width" end
                if type(d.h) ~= "number" or d.h <= 0 then return false, id .. ": bad height" end
                -- A resizable window needs a floor its panel can actually
                -- render at, and that floor has to be reachable: a minimum
                -- above the default means the window opens already clamped.
                if d.resizable ~= false then
                    if type(d.minW) ~= "number" or d.minW <= 0 then
                        return false, id .. ": resizable feature needs minW"
                    end
                    if type(d.minH) ~= "number" or d.minH <= 0 then
                        return false, id .. ": resizable feature needs minH"
                    end
                    if d.minW > d.w then
                        return false, string.format("%s: minW %d exceeds default width %d", id, d.minW, d.w)
                    end
                    if d.minH > d.h then
                        return false, string.format("%s: minH %d exceeds default height %d", id, d.minH, d.h)
                    end
                end
            end
            if d.subs ~= nil then
                if type(d.subs) ~= "table" then return false, id .. ": subs must be a list" end
                for _, s in ipairs(d.subs) do
                    if type(s) ~= "string" or s == "" then return false, id .. ": bad sub key" end
                end
            end
        end
        return true
    end)

    S:Register("features.unique_ids", function()
        local seen, n = {}, 0
        for _, id in ipairs(UI.featureOrder) do
            if seen[id] then return false, "duplicate id in order list: " .. id end
            seen[id] = true
            n = n + 1
        end
        local m = 0
        for _ in pairs(UI.features) do m = m + 1 end
        if n ~= m then return false, string.format("order has %d ids, table has %d", n, m) end
        return true
    end)

    S:Register("features.core_cannot_be_disabled", function()
        local mods = BRutus.db and BRutus.db.settings and BRutus.db.settings.modules
        if not mods then return false, "db.settings.modules missing" end
        for _, id in ipairs(UI.featureOrder) do
            if UI.features[id].core then
                local prev = mods[id]
                mods[id] = false
                local ok = BRutus:IsFeatureEnabled(id)
                mods[id] = prev
                if not ok then return false, id .. " is core but reported disabled" end
            end
        end
        return true
    end)

    S:Register("features.toggle_roundtrip", function()
        local id = "__selftest_feature"
        UI:RegisterFeature({ id = id, label = "Self test", hub = false, tab = false })
        BRutus:SetFeatureEnabled(id, false)
        if BRutus:IsFeatureEnabled(id) then return false, "disable did not stick" end
        BRutus:SetFeatureEnabled(id, true)
        if not BRutus:IsFeatureEnabled(id) then return false, "re-enable did not stick" end
        -- clean up so repeated runs stay idempotent
        UI.features[id] = nil
        for i, v in ipairs(UI.featureOrder) do
            if v == id then table.remove(UI.featureOrder, i) break end
        end
        if BRutus.db.settings.modules then BRutus.db.settings.modules[id] = nil end
        return true
    end)

    -- Two open windows used to share one frame-level range: every window is
    -- created by UI:CreatePanel, which pins it to level 1, and its children
    -- take parent + 1 from there. Panels nest to different depths, so a deep
    -- child of the window behind could outrank a shallow frame of the window
    -- in front and the two drew interleaved. Each window needs its own band.
    S:Register("window.raise_gives_each_window_its_own_band", function()
        if not UI.RaiseWindow then return false, "UI:RaiseWindow missing" end

        local function tree(depth)
            local root = CreateFrame("Frame", nil, UIParent)
            local node = root
            for _ = 1, depth do node = CreateFrame("Frame", nil, node) end
            return root
        end

        local function span(frame, lo, hi)
            local lvl = frame:GetFrameLevel()
            lo = math.min(lo or lvl, lvl)
            hi = math.max(hi or lvl, lvl)
            for _, child in ipairs({ frame:GetChildren() }) do
                lo, hi = span(child, lo, hi)
            end
            return lo, hi
        end

        -- Deliberately mismatched depths: that asymmetry is what produced
        -- the interleaving in the first place.
        local a, b = tree(7), tree(2)
        UI:RaiseWindow(a)
        UI:RaiseWindow(b)

        local aLo, aHi = span(a)
        local bLo, bHi = span(b)
        if bLo <= aHi then
            return false, string.format(
                "B occupies %d..%d and A occupies %d..%d: the bands overlap",
                bLo, bHi, aLo, aHi)
        end

        -- Raising A again must put it back in front, whole subtree included.
        UI:RaiseWindow(a)
        aLo, aHi = span(a)
        bLo, bHi = span(b)
        if aLo <= bHi then
            return false, string.format(
                "after re-raising A it occupies %d..%d, still under B's %d..%d",
                aLo, aHi, bLo, bHi)
        end
        return true
    end)

    -- Each raise consumes a band, so the counter climbs all session. Left
    -- unbounded it would eventually pass the client's frame-level cap and
    -- every window would silently clamp to the same level, which is the
    -- interleaving bug again. RaiseWindow renormalises instead; this proves
    -- the ceiling holds without waiting hours for it to happen for real.
    S:Register("window.raise_counter_stays_bounded", function()
        if not UI.RaiseWindow then return false, "UI:RaiseWindow missing" end
        local root = CreateFrame("Frame", nil, UIParent)
        CreateFrame("Frame", nil, CreateFrame("Frame", nil, root))

        local highest = 0
        for _ = 1, 2000 do
            UI:RaiseWindow(root)
            local lvl = root:GetFrameLevel()
            if lvl > highest then highest = lvl end
        end
        -- STACK_CEILING is 4000 in UI/Window.lua; allow one band over it,
        -- since the check runs before the raise that would cross it.
        if highest > 4100 then
            return false, "frame level ran away to " .. highest
        end
        return true
    end)

    -- The Web panel greys a button and prints the reason beside it, while the
    -- slash command refuses with the same words. Both read these predicates,
    -- so a change to the rule reaches the button and the command together.
    S:Register("companion.predicates_exist", function()
        local I = BRutus.CompanionImport
        if not I then return false, "CompanionImport missing" end
        if type(I.CanInvite) ~= "function" then return false, "CanInvite missing" end
        if type(I.CanOrganize) ~= "function" then return false, "CanOrganize missing" end
        return true
    end)

    S:Register("companion.can_invite_needs_roster", function()
        local I = BRutus.CompanionImport
        local saved = BRutus.db.companionRoster
        BRutus.db.companionRoster = nil
        local ok, reason = I:CanInvite()
        BRutus.db.companionRoster = saved
        if ok then return false, "allowed inviting with no roster loaded" end
        if not reason or reason == "" then return false, "refused without saying why" end
        return true
    end)

    S:Register("companion.can_organize_needs_roster", function()
        local I = BRutus.CompanionImport
        local saved = BRutus.db.companionRoster
        BRutus.db.companionRoster = nil
        local ok, reason = I:CanOrganize()
        BRutus.db.companionRoster = saved
        if ok then return false, "allowed organising with no roster loaded" end
        if not reason or reason == "" then return false, "refused without saying why" end
        return true
    end)

    -- A greyed button with no reason under it is the exact failure this
    -- feature exists to remove, so every refusal must carry text.
    S:Register("companion.refusals_always_explain", function()
        local I = BRutus.CompanionImport
        for _, name in ipairs({ "CanInvite", "CanOrganize" }) do
            local ok, reason = I[name](I)
            if not ok and (type(reason) ~= "string" or reason == "") then
                return false, name .. " refused with no reason"
            end
        end
        return true
    end)

    -- InviteAll must not re-implement its own gate: it has to answer with
    -- exactly what the predicate said, or the button and the command disagree.
    S:Register("companion.action_agrees_with_predicate", function()
        local I = BRutus.CompanionImport
        local saved = BRutus.db.companionRoster
        BRutus.db.companionRoster = nil
        local ok, want = I:CanInvite()
        local _, _, got = I:InviteAll()
        BRutus.db.companionRoster = saved
        if ok then return false, "expected the no-roster case to refuse" end
        if got ~= want then
            return false, string.format("InviteAll said [%s], predicate said [%s]",
                tostring(got), tostring(want))
        end
        return true
    end)

    S:Register("window.geometry_roundtrip", function()
        if not UI.SaveWindowGeometry then return false, "SaveWindowGeometry missing" end
        local probe = CreateFrame("Frame", nil, UIParent)
        probe.featureId = "__selftest_geom"
        probe:SetSize(321, 234)
        probe:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -60)
        UI:SaveWindowGeometry(probe)

        local restored = CreateFrame("Frame", nil, UIParent)
        restored.featureId = "__selftest_geom"
        UI:RestoreWindowGeometry(restored, { w = 10, h = 10 })
        local point, _, relPoint, x, y = restored:GetPoint()

        BRutus.db.settings.windows["__selftest_geom"] = nil
        if point ~= "TOPLEFT" or relPoint ~= "TOPLEFT" then
            return false, "point lost: " .. tostring(point) .. "/" .. tostring(relPoint)
        end
        if math.abs(x - 40) > 1 or math.abs(y + 60) > 1 then
            return false, string.format("offset lost: %.1f,%.1f", x, y)
        end
        if math.abs(restored:GetWidth() - 321) > 1 or math.abs(restored:GetHeight() - 234) > 1 then
            return false, "size lost"
        end
        return true
    end)
end

UI:_RegisterFeatureTests()

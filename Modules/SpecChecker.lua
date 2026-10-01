----------------------------------------------------------------------
-- BRutus Guild Manager - Spec Checker
-- Collects talent spec data for the local player and, for group
-- members, via the Inspect API (NotifyInspect + INSPECT_READY).
----------------------------------------------------------------------
local SpecChecker = {}  -- luacheck: ignore 111
BRutus.SpecChecker = SpecChecker
local L = BRutus.L

-- Time between inspect requests to avoid server throttle
local INSPECT_DELAY = 1.5

-- Internal state
local inspectQueue   = {}
local inspectPending = nil

----------------------------------------------------------------------
-- TBC spec names per class, ordered by talent tab index (1-3).
-- GetTalentTabInfo returns a numeric ID as return 1 in the Anniversary
-- client, so we look up names from the class token instead.
----------------------------------------------------------------------
local CLASS_SPEC_NAMES = {
    WARRIOR = { "Arms",         "Fury",          "Protection"    },
    PALADIN = { "Holy",         "Protection",    "Retribution"   },
    HUNTER  = { "Beast Mastery","Marksmanship",  "Survival"      },
    ROGUE   = { "Assassination","Combat",        "Subtlety"      },
    PRIEST  = { "Discipline",   "Holy",          "Shadow"        },
    SHAMAN  = { "Elemental",    "Enhancement",   "Restoration"   },
    MAGE    = { "Arcane",       "Fire",          "Frost"         },
    WARLOCK = { "Affliction",   "Demonology",    "Destruction"   },
    DRUID   = { "Balance",      "Feral Combat",  "Restoration"   },
}

----------------------------------------------------------------------
-- Count points spent per talent tab by summing individual talent ranks.
-- Works for both self (isInspect=false) and inspect (isInspect=true).
----------------------------------------------------------------------
local function CountTabPoints(tabIndex, isInspect)
    local total = 0
    local numTalents = BRutus.Compat.GetNumTalents(tabIndex, isInspect)
    if not numTalents then return 0 end
    for t = 1, numTalents do
        local _, _, _, _, currentRank = BRutus.Compat.GetTalentInfo(tabIndex, t, isInspect)
        total = total + (tonumber(currentRank) or 0)
    end
    return total
end

----------------------------------------------------------------------
-- Collect full talent data for one talent tab.
-- Returns an array of {name, icon, tier, column, currentRank, maxRank}.
----------------------------------------------------------------------
local function CollectTabTalents(tabIndex, isInspect)
    local talents    = {}
    local numTalents = BRutus.Compat.GetNumTalents(tabIndex, isInspect)
    if not numTalents then return talents end
    for t = 1, numTalents do
        local tName, tIcon, tier, col, curRank, maxRank =
            BRutus.Compat.GetTalentInfo(tabIndex, t, isInspect)
        talents[t] = {
            name        = tName   or "",
            icon        = tIcon   or "",
            tier        = tonumber(tier)    or 0,
            column      = tonumber(col)     or 0,
            currentRank = tonumber(curRank) or 0,
            maxRank     = tonumber(maxRank) or 0,
        }
    end
    return talents
end

-- Keep the local player's spec on their own member row.
local function KeepOwnSpec(spec)
    local key = BRutus:GetPlayerKey(BRutus.Compat.PlayerName(), GetRealmName())
    if BRutus.db and BRutus.db.members then
        if not BRutus.db.members[key] then
            BRutus.db.members[key] = {}
        end
        BRutus.db.members[key].spec = spec
    end
    return spec
end

----------------------------------------------------------------------
-- WoW: Forever lays a class's three classic trees side by side in one trait tree, left
-- to right in the classic tab order (issue #41). Read from the 1.60.1.70009 tables: the
-- columns inside one tree are 600 apart and the trees are more than 2200 apart, so a gap
-- over 1200 starts a new tree. The three biggest groups are the trees; a stray node —
-- the Hunter tree carries a stale Lightning Reflexes far off to the right — counts for
-- the nearest one. Takes { {x =, points =}, ... } and returns the points per tree, or nil
-- when the layout is not three trees.
----------------------------------------------------------------------
local TREE_GAP = 1200

function SpecChecker.ColumnPoints(nodes)
    local sorted = {}
    for i, n in ipairs(nodes) do sorted[i] = n end
    table.sort(sorted, function(a, b) return a.x < b.x end)

    local groups = {}
    for _, n in ipairs(sorted) do
        local g = groups[#groups]
        if not g or n.x - g.hi > TREE_GAP then
            g = { lo = n.x, hi = n.x, count = 0, points = 0 }
            groups[#groups + 1] = g
        end
        g.hi, g.count, g.points = n.x, g.count + 1, g.points + n.points
    end
    if #groups < 3 then return nil end

    local bySize = {}
    for i, g in ipairs(groups) do bySize[i] = g end
    table.sort(bySize, function(a, b) return a.count > b.count end)
    for i = 1, 3 do bySize[i].tree = true end

    local trees = {}
    for _, g in ipairs(groups) do
        if g.tree then trees[#trees + 1] = g end
    end
    for _, g in ipairs(groups) do
        if not g.tree then
            local nearest, best
            for _, t in ipairs(trees) do
                local d = math.max(t.lo - g.hi, g.lo - t.hi)
                if not best or d < best then nearest, best = t, d end
            end
            nearest.points = nearest.points + g.points
        end
    end
    return { trees[1].points, trees[2].points, trees[3].points }
end

-- The local player's spec on WoW: Forever, from the trait tree. Nil and why while there
-- is nothing to read yet — the talents not loaded, or no point spent — rather than a tree
-- nobody picked; the periodic collect reads it once there is one.
function SpecChecker:CollectOwnTraitSpec()
    local nodes, why = BRutus.Compat.TraitTreeNodes()
    if not nodes then return nil, why end
    local points = SpecChecker.ColumnPoints(nodes)
    if not points then return nil, "no-trees" end
    if points[1] + points[2] + points[3] == 0 then return nil, "no-points" end

    local _, classToken = UnitClass("player")
    local specNames = CLASS_SPEC_NAMES[classToken] or {}
    local names = {}
    for i = 1, 3 do names[i] = specNames[i] or ("Tree " .. i) end
    return KeepOwnSpec(self:BuildSpecRecord(points, names))
end

----------------------------------------------------------------------
-- Collect the local player's own spec from their talent tabs.
-- Stores result in Guild OS.db.members[key].spec and returns it.
----------------------------------------------------------------------
function SpecChecker:CollectOwnSpec()
    local numTabs, why = BRutus.Compat.GetNumTalentTabs()
    if why == "no-api" then return self:CollectOwnTraitSpec() end
    if why then return nil, why end
    if not numTabs or numTabs == 0 then return nil end

    local _, classToken = UnitClass("player")
    local specNames = CLASS_SPEC_NAMES[classToken] or {}

    local points = {}
    local names  = {}
    for i = 1, numTabs do
        points[i] = CountTabPoints(i, false)
        names[i]  = specNames[i] or ("Tree " .. i)
    end

    local spec = self:BuildSpecRecord(points, names)
    local talentsPerTab = {}
    for i = 1, numTabs do
        talentsPerTab[i] = CollectTabTalents(i, false)
    end
    spec.talents = talentsPerTab
    return KeepOwnSpec(spec)
end

----------------------------------------------------------------------
-- Build a normalised spec record from parallel arrays.
--   points = { 41, 5, 15 }
--   names  = { "Holy", "Protection", "Retribution" }
----------------------------------------------------------------------
function SpecChecker:BuildSpecRecord(points, names)
    local maxPts  = -1
    local specIdx = 1
    for i, pts in ipairs(points) do
        if pts > maxPts then
            maxPts  = pts
            specIdx = i
        end
    end

    return {
        tree      = names[specIdx] or "Unknown",
        treeIndex = specIdx,
        points    = points,
        names     = names,
        scannedAt = GetServerTime(),
    }
end

----------------------------------------------------------------------
-- Returns a display string such as "41/5/15  (Protection)"
-- Returns nil if no spec data is available for that key.
----------------------------------------------------------------------
function SpecChecker:GetSpecLabel(memberKey)
    if not BRutus.db or not BRutus.db.members then return nil end
    local data = BRutus.db.members[memberKey]
    if not data or not data.spec then return nil end

    local s   = data.spec
    local pts = s.points or {}
    local dist = table.concat(pts, "/")
    return dist .. "  (" .. (s.tree or "?") .. ")"
end

----------------------------------------------------------------------
-- Queue a spec scan for all reachable members of the current group.
-- Works for both party (5-man) and raid groups.
----------------------------------------------------------------------
function SpecChecker:ScanGroup()
    if not IsInGroup() and not IsInRaid() then
        BRutus:Print(L["|cffFF4444You must be in a group or raid to scan specs.|r"])
        return
    end

    inspectQueue   = {}
    inspectPending = nil

    local numMembers = GetNumGroupMembers()
    local isRaid = IsInRaid()
    for i = 1, numMembers do
        local unit = isRaid and ("raid" .. i) or ("party" .. i)
        if UnitExists(unit) and UnitIsConnected(unit) then
            local name, realm = BRutus.Compat.UnitIdentity(unit)
            if name then
                realm = (realm and realm ~= "") and realm or GetRealmName()
                local key = BRutus:GetPlayerKey(name, realm)
                table.insert(inspectQueue, { unit = unit, key = key, name = name })
            end
        end
    end

    if #inspectQueue == 0 then
        BRutus:Print(L["No group members available to inspect."])
        return
    end
    BRutus:Print(string.format(L["Scanning specs for %d player(s)…"], #inspectQueue))
    self:ProcessNextInspect()
end

----------------------------------------------------------------------
-- Internal: pop next entry from queue and fire NotifyInspect.
----------------------------------------------------------------------
function SpecChecker:ProcessNextInspect()
    if #inspectQueue == 0 then
        inspectPending = nil
        BRutus:Print(L["|cff00FF00Spec scan complete.|r"])
        return
    end

    local entry = table.remove(inspectQueue, 1)
    if UnitExists(entry.unit) and CanInspect(entry.unit) then
        inspectPending = entry
        NotifyInspect(entry.unit)
    else
        -- Unit out of range or offline — skip and continue
        C_Timer.After(0.1, function() SpecChecker:ProcessNextInspect() end)
    end
end

----------------------------------------------------------------------
-- Called when INSPECT_READY fires. Reads talent tabs for the
-- currently pending inspect and stores the result.
----------------------------------------------------------------------
function SpecChecker:OnInspectReady()
    if not inspectPending then return end

    local numTabs = BRutus.Compat.GetNumTalentTabs(true)   -- true = isInspect
    if not numTabs or numTabs == 0 then
        C_Timer.After(INSPECT_DELAY, function() SpecChecker:ProcessNextInspect() end)
        return
    end

    local _, classToken = UnitClass(inspectPending.unit)
    local specNames = CLASS_SPEC_NAMES[classToken or ""] or {}

    local points = {}
    local names  = {}
    for i = 1, numTabs do
        points[i] = CountTabPoints(i, true)
        names[i]  = specNames[i] or ("Tree " .. i)
    end

    local spec = self:BuildSpecRecord(points, names)
    local talentsPerTab = {}
    for i = 1, numTabs do
        talentsPerTab[i] = CollectTabTalents(i, true)
    end
    spec.talents = talentsPerTab

    if not BRutus.db.members[inspectPending.key] then
        BRutus.db.members[inspectPending.key] = { name = inspectPending.name }
    end
    BRutus.db.members[inspectPending.key].spec = spec

    inspectPending = nil

    -- Wait before next inspect to respect server throttle
    C_Timer.After(INSPECT_DELAY, function() SpecChecker:ProcessNextInspect() end)
end

----------------------------------------------------------------------
-- Module initialisation: register for INSPECT_READY and collect
-- the local player's own spec after talents have loaded.
----------------------------------------------------------------------
function SpecChecker:Initialize()
    local frame = CreateFrame("Frame")
    BRutus.Compat.RegisterEvent(frame, "INSPECT_READY")
    frame:SetScript("OnEvent", function(_, event)
        if event == "INSPECT_READY" then
            SpecChecker:OnInspectReady()
        end
    end)

    -- Talents aren't always available immediately on login
    C_Timer.After(3, function()
        SpecChecker:CollectOwnSpec()
    end)
end

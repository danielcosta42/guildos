-- WoW: Forever only (issue #37): the character's appearance, read in the barber's chair.
--
-- The game tells an addon nothing about how a character looks, except in a barber's chair:
-- there C_BarberShop.GetAvailableCustomizations() lists every option with the choice the
-- character has (a probe on the beta, 2026-09-28: nil at login, every option in the chair).
-- Those are the ids guildos.me's model viewer draws, so the look is kept as {option, choice}
-- pairs on the player's own member record, travels with the broadcast like race and sex, and
-- goes out in the companion export (payload v8, the site's specs/038).
if BRutus.Client.isAnniversary then return end

local Look = {}
BRutus.Look = Look

local Compat = BRutus.Compat
local L = BRutus.L
local MAX = 32          -- the site keeps at most this many; a body has about ten
local SETTLE = 1        -- seconds: the chair's options fill in just after its events

-- The chair's current choices as {optionID, choiceID}, one per option, by option; nil when
-- the chair is not open (or offers nothing).
function Look.Read()
    local B = C_BarberShop
    local cats = B and B.GetAvailableCustomizations and B.GetAvailableCustomizations()
    if type(cats) ~= "table" then return nil end
    local out, seen = {}, {}
    for _, cat in ipairs(cats) do
        for _, o in ipairs(type(cat) == "table" and type(cat.options) == "table" and cat.options or {}) do
            local c = o.currentChoiceIndex and type(o.choices) == "table" and o.choices[o.currentChoiceIndex]
            local id, choice = o.id, type(c) == "table" and c.id
            if type(id) == "number" and type(choice) == "number" and not seen[id] and #out < MAX then
                seen[id] = true
                out[#out + 1] = { id, choice }
            end
        end
    end
    if #out == 0 then return nil end
    table.sort(out, function(a, b) return a[1] < b[1] end)
    return out
end

local function same(a, b)
    if type(a) ~= "table" or #a ~= #b then return false end
    for i, p in ipairs(b) do
        if type(a[i]) ~= "table" or a[i][1] ~= p[1] or a[i][2] ~= p[2] then return false end
    end
    return true
end

-- Keeps the chair's choices on the player's own record and tells the guild, once per change.
function Look:Capture()
    local look = Look.Read()
    if not look then return end
    local key = BRutus:GetPlayerKey(Compat.PlayerName(), GetRealmName())
    local rec = BRutus.db.members[key]
    if not rec then
        rec = {}
        BRutus.db.members[key] = rec
    end
    if same(rec.look, look) then return end
    rec.look = look
    if BRutus.db.myData and BRutus.db.myData ~= rec then BRutus.db.myData.look = look end
    BRutus:Print(L["Your look is saved: guildos.me draws it after the next publish."])
    if BRutus.CommSystem and BRutus.CommSystem.BroadcastMyData then
        BRutus.CommSystem:BroadcastMyData(true)
    end
end

function Look:Initialize()
    local f = CreateFrame("Frame")
    -- Sitting down reads the look the character has; buying a new one reads it again.
    for _, event in ipairs({ "BARBER_SHOP_OPEN", "BARBER_SHOP_APPEARANCE_APPLIED" }) do
        Compat.RegisterEvent(f, event)
    end
    f:SetScript("OnEvent", function() Compat.After(SETTLE, function() Look:Capture() end) end)
end

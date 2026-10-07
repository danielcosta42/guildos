-- WoW: Forever only (issue #37): the character's appearance, read in the barber's chair.
--
-- The game tells an addon nothing about how a character looks, except in a barber's chair:
-- there C_BarberShop.GetAvailableCustomizations() lists every option with the choice the
-- character has (a probe on the beta, 2026-09-28: nil at login, every option in the chair).
-- Those are the ids guildos.me's model viewer draws, so the look is kept as {option, choice}
-- pairs on the player's own member record, travels with the broadcast like race and sex, and
-- goes out in the companion export (payload v8, the site's specs/038).
if GuildOS.Client.isAnniversary then return end

local Look = {}
GuildOS.Look = Look

local Compat = GuildOS.Compat
local L = GuildOS.L
local MAX = 32          -- the site keeps at most this many; a body has about ten

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

-- Keeps a look on the player's own record and tells the guild, once per change.
function Look:Keep(look)
    if not look then return end
    local key = GuildOS:GetPlayerKey(Compat.PlayerName(), GetRealmName())
    local rec = GuildOS.db.members[key]
    if not rec then
        rec = {}
        GuildOS.db.members[key] = rec
    end
    if same(rec.look, look) then return end
    rec.look = look
    if GuildOS.db.myData and GuildOS.db.myData ~= rec then GuildOS.db.myData.look = look end
    GuildOS:Print(L["Your look is saved: guildos.me draws it after the next publish."])
    if GuildOS.CommSystem and GuildOS.CommSystem.BroadcastMyData then
        GuildOS.CommSystem:BroadcastMyData(true)
    end
end

function Look:Initialize()
    -- A purchase: what is being bought is the chair's selection at the moment it is applied.
    -- By the time the game says it went through, it has already stood the player up and the
    -- chair has nothing left to read.
    if C_BarberShop and C_BarberShop.ApplyCustomizationChoices then
        hooksecurefunc(C_BarberShop, "ApplyCustomizationChoices", function() Look.pending = Look.Read() end)
    end
    local f = CreateFrame("Frame")
    for _, event in ipairs({ "BARBER_SHOP_OPEN", "BARBER_SHOP_APPEARANCE_APPLIED" }) do
        Compat.RegisterEvent(f, event)
    end
    f:SetScript("OnEvent", function(_, event)
        if event == "BARBER_SHOP_APPEARANCE_APPLIED" then
            Look:Keep(Look.pending)
            Look.pending = nil
        else
            -- Sitting down: the look the character has, read on the next frame, once the chair
            -- has set itself up and before anything can be previewed.
            Look.pending = nil
            Compat.After(0, function() Look:Keep(Look.Read()) end)
        end
    end)
end

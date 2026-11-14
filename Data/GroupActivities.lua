----------------------------------------------------------------------
-- Guild OS - What a group can be formed for (issue #341)
-- The Groups tab's catalogue, for the client it is loaded on: sections of activities, each with a
-- stable id that crosses the wire, the instance's map id (the name in the player's own language,
-- where the client knows the instance), its level range, its size and the game's own LFG background.
-- Names are English here and never matched against anything: an id is what two clients compare.
--
-- WoW: Forever's own are the nine of Data/ForeverDungeons.lua (four with a map, issue #214) and the
-- raids of Modules/RaidTracker.lua (issue #291); retail's raids are Midnight's four (issue #182).
-- Retail's dungeons rotate by season, so they are named by how they are run, not one by one.
----------------------------------------------------------------------
local L = GuildOS.L
local client = GuildOS.Client

local A = { sections = {}, byId = {}, CATS = { "dungeon", "raid", "other" } }
GuildOS.GroupActivities = A

local ART = "Interface\\LFGFrame\\UI-LFG-BACKGROUND-"

local function item(id, name, map, min, max, art, size)
    return { id = id, name = name, map = map, min = min, max = max, art = art and (ART .. art) or nil, size = size or 5 }
end

local function section(cat, title, items, isNew)
    local s = { cat = cat, title = title, items = items, isNew = isNew or nil }
    for _, it in ipairs(items) do
        it.cat = cat
        A.byId[it.id] = it
    end
    A.sections[#A.sections + 1] = s
    return s
end

-- Classic's dungeons: both Forever's and the leveling road of nobody else here.
local CLASSIC_LOW = {
    item("ragefire-chasm", "Ragefire Chasm", 389, 13, 18, "RagefireChasm"),
    item("wailing-caverns", "Wailing Caverns", 43, 17, 24, "WailingCaverns"),
    item("deadmines", "The Deadmines", 36, 17, 26, "Deadmines"),
    item("shadowfang-keep", "Shadowfang Keep", 33, 22, 30, "ShadowfangKeep"),
    item("blackfathom-deeps", "Blackfathom Deeps", 48, 24, 32, "BlackfathomDeeps"),
    item("stockade", "The Stockade", 34, 24, 32, "StormwindStockades"),
    item("gnomeregan", "Gnomeregan", 90, 29, 38, "Gnomeregan"),
    item("razorfen-kraul", "Razorfen Kraul", 47, 29, 38, "RazorfenKraul"),
    item("scarlet-monastery", "Scarlet Monastery", 189, 34, 45, "ScarletMonastery"),
    item("razorfen-downs", "Razorfen Downs", 129, 37, 46, "RazorfenDowns"),
}
local CLASSIC_HIGH = {
    item("uldaman", "Uldaman", 70, 41, 51, "Uldaman"),
    item("zulfarrak", "Zul'Farrak", 209, 44, 54, "ZulFarrak"),
    item("maraudon", "Maraudon", 349, 46, 55, "Maraudon"),
    item("sunken-temple", "Sunken Temple", 109, 50, 56, "SunkenTemple"),
    item("blackrock-depths", "Blackrock Depths", 230, 52, 60, "BlackrockDepths"),
    item("blackrock-spire", "Blackrock Spire", 229, 55, 60, "BlackrockSpire"),
    item("dire-maul", "Dire Maul", 429, 56, 60, "DireMaul"),
    item("stratholme", "Stratholme", 329, 58, 60, "Stratholme"),
    item("scholomance", "Scholomance", 289, 58, 60, "Scholomance"),
}

local function levels(title, items)
    local lo, hi = items[1].min, items[1].max
    for _, it in ipairs(items) do
        lo, hi = math.min(lo, it.min), math.max(hi, it.max)
    end
    return string.format(title, lo, hi)
end

if client.isRetail then
    section("dungeon", L["Dungeons"], {
        item("mythic-keystone", L["Mythic+ keystone"]),
        item("mythic-dungeon", L["Mythic dungeon"]),
        item("heroic-dungeon", L["Heroic dungeon"]),
        item("delve", L["Delve"]),
    })
    section("raid", L["Raids"], {
        item("voidspire", "The Voidspire", 2912, nil, nil, nil, 20),
        item("dreamrift", "The Dreamrift", 2939, nil, nil, nil, 20),
        item("march-on-queldanas", "March on Quel'Danas", 2913, nil, nil, nil, 20),
        item("venomous-abyss", "The Venomous Abyss", 3004, nil, nil, nil, 20),
    })
elseif client.isAnniversary then
    local outland = {
        item("hellfire-ramparts", "Hellfire Ramparts", 543, 58, 62, "HellfireCitadel"),
        item("blood-furnace", "The Blood Furnace", 542, 59, 63, "HellfireCitadel"),
        item("slave-pens", "The Slave Pens", 547, 60, 64, "CoilFang"),
        item("underbog", "The Underbog", 546, 61, 65, "CoilFang"),
        item("mana-tombs", "Mana-Tombs", 557, 62, 66, "Auchindoun"),
        item("auchenai-crypts", "Auchenai Crypts", 558, 63, 67, "Auchindoun"),
        item("old-hillsbrad", "Old Hillsbrad Foothills", 560, 64, 68, "CavernsOfTime"),
        item("sethekk-halls", "Sethekk Halls", 556, 65, 69, "Auchindoun"),
        item("steamvault", "The Steamvault", 545, 68, 70, "CoilFang"),
        item("shadow-labyrinth", "Shadow Labyrinth", 555, 68, 70, "Auchindoun"),
        item("shattered-halls", "The Shattered Halls", 540, 68, 70, "HellfireCitadel"),
        item("black-morass", "The Black Morass", 269, 68, 70, "CavernsOfTime"),
        item("mechanar", "The Mechanar", 554, 68, 70, "TempestKeep"),
        item("botanica", "The Botanica", 553, 68, 70, "TempestKeep"),
        item("arcatraz", "The Arcatraz", 552, 68, 70, "TempestKeep"),
        item("magisters-terrace", "Magisters' Terrace", 585, 68, 70, "MagistersTerrace"),
    }
    section("dungeon", levels(L["Outland dungeons, level %d to %d"], outland), outland)
    section("dungeon", L["Any difficulty"], {
        item("heroic-dungeon", L["Heroic dungeon"], nil, 70, 70),
        item("classic-dungeon", L["Classic dungeon"], nil, 13, 60),
    })
    section("raid", L["Raids"], {
        item("karazhan", "Karazhan", 532, 70, 70, "Karazhan", 10),
        item("gruuls-lair", "Gruul's Lair", 565, 70, 70, "GruulsLair", 25),
        item("magtheridons-lair", "Magtheridon's Lair", 544, 70, 70, "HellfireCitadel", 25),
        item("serpentshrine-cavern", "Serpentshrine Cavern", 548, 70, 70, "CoilFang", 25),
        item("tempest-keep", "Tempest Keep", 550, 70, 70, "TempestKeep", 25),
        item("zulaman", "Zul'Aman", 568, 70, 70, "ZulAman", 10),
        item("hyjal-summit", "Hyjal Summit", 534, 70, 70, "CavernsOfTime", 25),
        item("black-temple", "Black Temple", 564, 70, 70, "BlackTemple", 25),
        item("sunwell-plateau", "Sunwell Plateau", 580, 70, 70, "SunwellPlateau", 25),
    })
else
    -- WoW: Forever. Five of the nine have no map in the client yet (issue #214): their name is English
    -- until the launch scan fills it in.
    section("dungeon", L["New in WoW: Forever"], {
        item("hall-of-thanes", "The Hall of Thanes", 3065),
        item("ruins-of-lordaeron", "Ruins of Lordaeron", 2999),
        item("excavation-site-wetlands", "Excavation Site: Wetlands", 2998),
        item("city-of-dalaran", "City of Dalaran", 2959),
        item("drowned-city", "The Drowned City"),
        item("kroldok-stronghold", "Krol'dok Stronghold"),
        item("alcaz-prison", "Alcaz Prison"),
        item("blackmaw-hold", "Blackmaw Hold"),
        item("shapers-terrace", "Shaper's Terrace"),
    }, true)
    section("dungeon", levels(L["Classic dungeons, level %d to %d"], CLASSIC_LOW), CLASSIC_LOW)
    section("dungeon", levels(L["Classic dungeons, level %d to %d"], CLASSIC_HIGH), CLASSIC_HIGH)
    section("raid", L["Raids"], {
        item("onyxias-lair", "Onyxia's Lair", 249, 60, 60, nil, 40),
        item("barrow-deeps", "Barrow Deeps", nil, 60, 60, nil, 40),
        item("forever-hyjal-summit", "Hyjal Summit", nil, 60, 60, nil, 40),
    })
end

-- What is no instance: the same on every client.
section("other", L["Quests and more"], {
    item("elite-quests", L["Elite quests"]),
    item("world-boss", L["World boss"], nil, nil, nil, nil, 40),
    item("battlegrounds", L["Battlegrounds"], nil, nil, nil, nil, 10),
    item("world-pvp", L["World PvP"], nil, nil, nil, nil, 40),
    item("farming", L["Farming and reputation"]),
    item("leveling", L["Leveling together"]),
    item("other", L["Something else"]),
})

-- The sections of one category, in the order they are shown.
function A:Sections(cat)
    local out = {}
    for _, s in ipairs(self.sections) do
        if s.cat == cat then out[#out + 1] = s end
    end
    return out
end

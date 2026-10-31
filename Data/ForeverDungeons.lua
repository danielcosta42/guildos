-- WoW: Forever's new dungeons (issue #210, `forever-dungeons.v1`, the same catalogue as guildos.me's),
-- read from wago.tools DB2 `Map` and `DungeonEncounter`, build 1.60.1.70707, on 2026-10-31.
--
-- `final` is the boss whose death clears the dungeon: the one the game keeps a kill statistic for
-- (`Achievement`, category 14821), with the beta's guides for the one it has none of. The table's
-- `OrderIndex` is no route, and `LFGDungeons.FinalEncounterID` is still encrypted (issue #235).
-- `bosses` is the way through, what a full clear asks for. Not on it, and ignored when killed:
-- Lyn the Ignored 3310 (summoned with a tome) and Mana Wraith 3312 (no fight anybody has reported)
-- in Dalaran; Lordaeron Captain 3408 (a rare) and Viktor the Vile 3411 (hidden, after the end) in
-- Ruins; Highland Horror 3644 (one faction's quest) in Wetlands.
--
-- Five of the nine new dungeons are not among the readable maps yet (The Drowned City, Krol'dok
-- Stronghold, Alcaz Prison, Blackmaw Hold, Shaper's Terrace): the launch scan fills them in on both
-- sides (issue #214). Manor Mistmantle is not one of the nine, only a map in the client with no boss:
-- it records no clear. Matched by instance and encounter ids, never by a name: a name can arrive
-- secret or translated.
if GuildOS.Client.isAnniversary or GuildOS.Client.isRetail then return end

GuildOS.ForeverDungeons = {
    version = 1,
    build = "1.60.1.70707",
    byInstance = {
        [2959] = { id = "city-of-dalaran", name = "City of Dalaran", final = 3303,
            bosses = { 3311, 3298, 3301, 3302, 3299, 3300, 3303 } },
        [2999] = { id = "ruins-of-lordaeron", name = "Ruins of Lordaeron", final = 3354,
            bosses = { 3353, 3355, 3357, 3412, 3354 } },
        [2998] = { id = "excavation-site-wetlands", name = "Excavation Site: Wetlands", final = 3482,
            bosses = { 3480, 3481, 3482 } },
        [3065] = { id = "hall-of-thanes", name = "The Hall of Thanes", final = 3496,
            bosses = { 3493, 3495, 3494, 3496 } },
        [3109] = { id = "manor-mistmantle", name = "Manor Mistmantle", bosses = {} },
    },
}

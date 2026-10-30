-- WoW: Forever's new dungeons (issue #210, `forever-dungeons.v1`, the same catalogue as guildos.me's),
-- read from wago.tools DB2 `Map` and `DungeonEncounter`, build 1.60.1.70685, on 2026-10-30.
--
-- `final` is the boss whose death clears the dungeon: the last in the game's `OrderIndex` until the
-- launch build says otherwise (`LFGDungeons.FinalEncounterID` is still encrypted; issue #214).
-- Half-Pint Tavern is not among the readable maps yet, and Manor Mistmantle lists no boss: neither
-- records a clear until the launch scan fills them in. Matched by instance and encounter ids, never
-- by a name: a name can arrive secret or translated.
if GuildOS.Client.isAnniversary or GuildOS.Client.isRetail then return end

GuildOS.ForeverDungeons = {
    version = 1,
    build = "1.60.1.70685",
    byInstance = {
        [2959] = { id = "city-of-dalaran", name = "City of Dalaran", final = 3312,
            bosses = { 3298, 3299, 3300, 3301, 3302, 3303, 3310, 3311, 3312 } },
        [2999] = { id = "ruins-of-lordaeron", name = "Ruins of Lordaeron", final = 3412,
            bosses = { 3353, 3357, 3355, 3354, 3408, 3411, 3412 } },
        [2998] = { id = "excavation-site-wetlands", name = "Excavation Site: Wetlands", final = 3482,
            bosses = { 3480, 3481, 3644, 3482 } },
        [3065] = { id = "hall-of-thanes", name = "The Hall of Thanes", final = 3496,
            bosses = { 3493, 3495, 3494, 3496 } },
        [3109] = { id = "manor-mistmantle", name = "Manor Mistmantle", bosses = {} },
    },
}

-- WoW: Forever's dungeons (issue #210, `forever-dungeons.v1`, the same catalogue as guildos.me's): the nine new
-- ones and the classic ones the game ships, by instance id (GetInstanceInfo's 8th return, the DB2 `Map` id)
-- and encounter id (ENCOUNTER_END's first argument, the DB2 `DungeonEncounter` id).
--
-- Sources, read on 2026-11-27:
--   * wago.tools DB2 `Map`, `DungeonEncounter`, `Achievement` (category 14821, the kill statistics),
--     `Criteria` and `CriteriaTree`, product wowf, build 1.60.1.71139 (https://wago.tools/db2/Map?build=1.60.1.71139,
--     https://wago.tools/db2/DungeonEncounter?build=1.60.1.71139). The first four new dungeons were read from
--     build 1.60.1.70707 on 2026-10-31; their ids are the same in 71139.
--   * The classic instances: Forever reuses the retail engine's ids of the classic maps. Every classic encounter
--     below is in DungeonEncounter of Classic Era 1.15.9.70576 (https://wago.tools/db2/DungeonEncounter?build=1.15.9.70576)
--     with the same id, name and map, except Forever's own: Sunken Temple's 3582-3589 and Miner Johnson 3676.
--   * Route and final boss of the five dungeons added after the launch scan: WarcraftTavern's Forever guides
--     (https://www.warcrafttavern.com/forever/guides/the-drowned-city/, .../blackmaw-hold/, .../kroldok-stronghold/,
--     .../alcaz-island-prison/, .../shapers-terrace/) and Mobalytics' Blackmaw Hold guide
--     (https://mobalytics.gg/wow-forever/dungeons/blackmaw-hold-complete-dungeon-guide-uncas).
--
-- `final` is the boss whose death clears the dungeon: the one the game keeps a kill statistic for (`Achievement`,
-- category 14821, named "<boss> kills (<dungeon>)"), else the guides' last boss. The table's `OrderIndex` is no
-- route (Blackmaw Hold's last by it is Unbound Spirit, the guides' is Varrox Bleakhoof), and
-- `LFGDungeons.FinalEncounterID` is still encrypted (issue #235). `bosses` is the way through, what a full clear
-- asks for. Left off it, and ignored when killed: summoned, rare and one-faction bosses (Lyn the Ignored 3310 and
-- Mana Wraith 3312 in Dalaran; Lordaeron Captain 3408 and Viktor the Vile 3411 in Ruins; Highland Horror 3644 in
-- Wetlands; King Op 3504 in Shaper's Terrace, named by no guide; Miner Johnson 3676, Ragglesnout 2783, Kormok 3055,
-- Lord Valthalak 3070, Lord Hel'nurath 2793, Tsu'zee 2794 and Stratholme's 2795-2800).
--
-- `wings`: one instance id, several dungeons (Scarlet Monastery, Dire Maul, Blackrock Spire, Stratholme): each wing
-- is a clear of its own, found by the boss killed. `alt`: another encounter id the same boss may come by, mapped to
-- the one in `bosses` (Blackfathom Deeps and Sunken Temple carry two sets of the same bosses in DungeonEncounter,
-- and which one Forever fires is not known yet). `unverified = true`: the final boss or the set of ids is not
-- backed by a kill statistic, so a clear may be missed until `/gos debug probe` reports what the game sent
-- (Core/Probe.lua, Modules/DungeonLog.lua record every instance and encounter seen). `classic = true`: one of the
-- classic dungeons, not the game's new ones: the journal names no guild's first clear of it, and the calendar's
-- pick list keeps it in `classic` below.
--
-- Manor Mistmantle is not one of the nine, only a map in the client with no boss: it records no clear. Matched by
-- instance and encounter ids, never by a name: a name can arrive secret or translated.
if GuildOS.Client.isAnniversary or GuildOS.Client.isRetail then return end

GuildOS.ForeverDungeons = {
    version = 1,
    build = "1.60.1.71139",
    byInstance = {
        -- ── New in WoW: Forever ─────────────────────────────────────────────────────────────────
        [2959] = { id = "city-of-dalaran", name = "City of Dalaran", final = 3303,   -- statistic 63572
            bosses = { 3311, 3298, 3301, 3302, 3299, 3300, 3303 } },
        [2999] = { id = "ruins-of-lordaeron", name = "Ruins of Lordaeron", final = 3354,   -- statistic 63571
            bosses = { 3353, 3355, 3357, 3412, 3354 } },
        [2998] = { id = "excavation-site-wetlands", name = "Excavation Site: Wetlands", final = 3482, unverified = true,
            bosses = { 3480, 3481, 3482 } },   -- no statistic: the beta's guides
        [3065] = { id = "hall-of-thanes", name = "The Hall of Thanes", final = 3496,   -- statistic 63573
            bosses = { 3493, 3495, 3494, 3496 } },
        [3001] = { id = "shapers-terrace", name = "The Shaper's Terrace", final = 3502,   -- statistic 63574 (Nanaya)
            bosses = { 3503, 3498, 3597, 3499, 3600, 3507, 3500, 3501, 3505, 3502 } },
        [2994] = { id = "alcaz-prison", name = "Alcaz Prison", final = 3409,   -- statistic 63575 (Blazeroar)
            bosses = { 3410, 3403, 3418, 3409, 3415 } },
        -- No statistic for these three: the guides' last boss.
        [2970] = { id = "drowned-city", name = "The Drowned City", final = 3479, unverified = true,   -- Min'loth the Serpent
            bosses = { 3474, 3475, 3476, 3478, 3511, 3479 } },
        [2974] = { id = "blackmaw-hold", name = "Blackmaw Hold", final = 3334, unverified = true,   -- Varrox Bleakhoof
            bosses = { 3315, 3322, 3316, 3336, 3327, 3323, 3334 } },
        -- Bossman Toof, the guide's fifth, has no DungeonEncounter row in 71139.
        [3039] = { id = "kroldok-stronghold", name = "Krol'dok Stronghold", final = 3451, unverified = true,   -- Overlord Mugg
            bosses = { 3450, 3452, 3453, 3449, 3451 } },
        [3109] = { id = "manor-mistmantle", name = "Manor Mistmantle", bosses = {} },

        -- ── The classic dungeons ───────────────────────────────────────────────────────────────
        [389] = { id = "ragefire-chasm", name = "Ragefire Chasm", classic = true, final = 2735,   -- statistic 15027
            bosses = { 2732, 2733, 2734, 2735 } },
        [43] = { id = "wailing-caverns", name = "Wailing Caverns", classic = true, final = 592,   -- statistic 15028
            bosses = { 585, 586, 587, 588, 589, 590, 591, 592 } },
        [36] = { id = "deadmines", name = "The Deadmines", classic = true, final = 2747,   -- statistic 63570
            bosses = { 2741, 2742, 2743, 2744, 2745, 2746, 2747 } },
        [33] = { id = "shadowfang-keep", name = "Shadowfang Keep", classic = true, final = 2755,   -- statistic 1092
            bosses = { 2748, 2749, 2750, 2751, 2752, 2753, 2754, 2755 } },
        -- Two sets: 2910-2916 (difficulty 0/1) and 2761-2767 (difficulty 201, "Normal", 5): which Forever fires is unknown.
        [48] = { id = "blackfathom-deeps", name = "Blackfathom Deeps", classic = true, final = 2910, unverified = true,
            bosses = { 2916, 2915, 2914, 2913, 2912, 2911, 2910 },
            alt = { [2761] = 2916, [2762] = 2915, [2763] = 2914, [2764] = 2913, [2765] = 2912, [2766] = 2911, [2767] = 2910 } },
        [34] = { id = "stockade", name = "The Stockade", classic = true, final = 2760,   -- statistic 15029
            bosses = { 2756, 2757, 2758, 2759, 2760 } },
        [90] = { id = "gnomeregan", name = "Gnomeregan", classic = true, final = 2772,   -- statistic 6140
            bosses = { 2768, 2769, 2770, 2771, 2772 } },
        [47] = { id = "razorfen-kraul", name = "Razorfen Kraul", classic = true, final = 2778,   -- statistic 6139
            bosses = { 2773, 2774, 2775, 2776, 2777, 2778 } },
        [189] = { id = "scarlet-monastery", name = "Scarlet Monastery", classic = true, bosses = {},
            wings = {
                { id = "scarlet-monastery-graveyard", name = "Scarlet Monastery: Graveyard", final = 2779, unverified = true,
                  bosses = { 444, 2779 } },
                { id = "scarlet-monastery-library", name = "Scarlet Monastery: Library", final = 447, unverified = true,
                  bosses = { 446, 447 } },
                { id = "scarlet-monastery-armory", name = "Scarlet Monastery: Armory", final = 448, unverified = true,
                  bosses = { 448 } },
                { id = "scarlet-monastery-cathedral", name = "Scarlet Monastery: Cathedral", final = 450,   -- statistic 6786
                  bosses = { 449, 450 } },
            } },
        [129] = { id = "razorfen-downs", name = "Razorfen Downs", classic = true, final = 2785,   -- statistic 6141
            bosses = { 2780, 2781, 2782, 2784, 2785 } },
        [70] = { id = "uldaman", name = "Uldaman", classic = true, final = 554,   -- statistic 6142
            bosses = { 547, 548, 549, 1887, 551, 552, 553, 554 } },
        [209] = { id = "zulfarrak", name = "Zul'Farrak", classic = true, final = 600,   -- statistic 1094
            bosses = { 593, 594, 595, 596, 597, 598, 599, 600 } },
        [349] = { id = "maraudon", name = "Maraudon", classic = true, final = 429,   -- statistic 6143
            bosses = { 422, 423, 427, 424, 425, 426, 428, 429 } },
        -- Forever's own difficulty-0 set (3582-3589); the classic 486-493 and 2814 (difficulty 201) map onto it.
        [109] = { id = "sunken-temple", name = "Sunken Temple", classic = true, final = 3584, unverified = true,   -- statistic 6144
            bosses = { 3582, 3583, 3589, 3588, 3587, 3586, 3585, 3584 },
            alt = { [2814] = 3582, [492] = 3583, [488] = 3589, [486] = 3588, [487] = 3587, [490] = 3586, [491] = 3585,
                    [493] = 3584 } },
        [230] = { id = "blackrock-depths", name = "Blackrock Depths", classic = true, final = 2790,   -- statistic 1095
            bosses = { 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 2791, 242, 243, 244,
                       2789, 2790 } },
        [229] = { id = "blackrock-spire", name = "Blackrock Spire", classic = true, bosses = {},
            wings = {
                { id = "lower-blackrock-spire", name = "Lower Blackrock Spire", final = 275,   -- statistic 6145
                  bosses = { 267, 268, 269, 270, 271, 272, 274, 273, 275 } },
                { id = "upper-blackrock-spire", name = "Upper Blackrock Spire", final = 3069,   -- statistic 1096
                  bosses = { 3062, 3063, 3068, 3069 } },
            } },
        [429] = { id = "dire-maul", name = "Dire Maul", classic = true, bosses = {},
            wings = {
                { id = "dire-maul-east", name = "Dire Maul: East", final = 346, unverified = true,
                  bosses = { 343, 344, 345, 2792, 346 } },
                { id = "dire-maul-west", name = "Dire Maul: West", final = 361, unverified = true,
                  bosses = { 350, 347, 348, 349, 361 } },
                { id = "dire-maul-north", name = "Dire Maul: North", final = 368,   -- statistic 6146
                  bosses = { 362, 363, 364, 365, 366, 367, 368 } },
            } },
        [329] = { id = "stratholme", name = "Stratholme", classic = true, bosses = {},
            wings = {
                { id = "stratholme-living", name = "Stratholme: Living", final = 478, unverified = true,
                  bosses = { 473, 474, 476, 475, 472, 477, 478 } },
                { id = "stratholme-undead", name = "Stratholme: Undead", final = 484,   -- statistic 1097
                  bosses = { 479, 480, 481, 482, 483, 484 } },
            } },
        [289] = { id = "scholomance", name = "Scholomance", classic = true, final = 2801,   -- statistic 15030
            bosses = { 2805, 2804, 2811, 2809, 2813, 2810, 2803, 2802, 2808, 2812, 2807, 2806, 2801 } },
    },
    -- The classic dungeons guilds book most, highest level first, after the game's own: what guildos.me
    -- offers to book a night for (`bookableDungeons`, guildos-web #491), and the calendar's pick list for
    -- a Dungeon event (issue #308). Names only: the calendar offers these instead of the classic entries
    -- above (Calendar:DungeonChoices).
    classic = { "Scholomance", "Stratholme", "Upper Blackrock Spire", "Lower Blackrock Spire", "Dire Maul",
        "Blackrock Depths", "Sunken Temple", "Maraudon", "Zul'Farrak", "Uldaman", "Scarlet Monastery",
        "The Deadmines" },
}

-- The dungeon (or wing) a boss of `instanceID` belongs to, and that boss's id in it (`alt` mapped), or nil.
-- `wingId`: the wing a run is already in, which an encounter of another wing does not move.
function GuildOS.ForeverDungeons:RouteOf(instanceID, encounterID, wingId)
    local d = self.byInstance[instanceID]
    if not d or type(encounterID) ~= "number" then return nil end
    encounterID = d.alt and d.alt[encounterID] or encounterID
    local function has(x)
        for _, id in ipairs(x.bosses or {}) do
            if id == encounterID then return true end
        end
        return false
    end
    if d.wings then
        for _, w in ipairs(d.wings) do
            if (wingId == nil or w.id == wingId) and has(w) then return w, encounterID end
        end
        return nil
    end
    if has(d) then return d, encounterID end
    return nil
end

-- Whether an instance or an encounter id is in the registry at all, and whether it is confirmed: "known",
-- "unverified" or nil. For the probe's report (Core/Probe.lua).
function GuildOS.ForeverDungeons:StatusOf(instanceID, encounterID)
    local d = self.byInstance[instanceID]
    if not d then return nil end
    if encounterID == nil then return d.unverified and "unverified" or "known" end
    for _, w in ipairs(d.wings or { d }) do
        local id = d.alt and d.alt[encounterID] or encounterID
        for _, b in ipairs(w.bosses or {}) do
            if b == id then
                if d.alt and d.alt[encounterID] then return "unverified" end
                return (w.unverified or d.unverified) and "unverified" or "known"
            end
        end
    end
    return nil
end

----------------------------------------------------------------------
-- Guild OS - Winter Veil quests that count as taking part in the game's event (guildos-web#671)
--
-- A turn-in of one of these (QUEST_TURNED_IN) between Dec 15 and the event's wrapping deadline counts for the Chimney.
-- One per line: [questID] = "name", with the public page that confirms it. Never a guess: an ID that is not confirmed
-- on its own page is not here. While the table is empty the addon works and records nothing.
----------------------------------------------------------------------
-- Not here, not confirmed as Winter Veil on its page: "The Hero of the Day" (8763 Alliance, 8799 Horde).
GuildOS.WinterVeilQuests = {
    [6961] = "Great-father Winter is Here!",  -- Horde; https://www.wowhead.com/tbc/quest=6961 (Winter Veil event shown on the page)
    [7022] = "Greatfather Winter is Here!",  -- Alliance; https://www.wowhead.com/tbc/quest=7022 (Winter Veil event shown on the page)
    [6962] = "Treats for Great-father Winter",  -- Horde; https://www.wowhead.com/tbc/quest=6962 (Winter Veil event shown on the page)
    [7025] = "Treats for Greatfather Winter",  -- Alliance; https://www.wowhead.com/tbc/quest=7025 (Winter Veil event shown on the page)
    [6964] = "The Reason for the Season",  -- Horde; https://www.wowhead.com/tbc/quest=6964 (Winter Veil event shown on the page)
    [7062] = "The Reason for the Season",  -- Alliance; https://www.wowhead.com/tbc/quest=7062 (Winter Veil event shown on the page)
    [7061] = "The Feast of Winter Veil",  -- Horde; https://www.wowhead.com/tbc/quest=7061 (title and quest series match; the page shows no event field)
    [7063] = "The Feast of Winter Veil",  -- Alliance; https://www.wowhead.com/tbc/quest=7063 (title and quest series match; the page shows no event field)
    [6963] = "Stolen Winter Veil Treats",  -- Horde; https://www.wowhead.com/tbc/quest=6963 (title and quest series match; the page shows no event field)
    [7042] = "Stolen Winter Veil Treats",  -- Alliance; https://www.wowhead.com/tbc/quest=7042 (title and quest series match; the page shows no event field)
    [6983] = "You're a Mean One...",  -- Horde; https://www.wowhead.com/tbc/quest=6983 (Winter Veil event shown on the page)
    [7043] = "You're a Mean One...",  -- Alliance; https://www.wowhead.com/tbc/quest=7043 (Winter Veil event shown on the page)
    [6984] = "A Smokywood Pastures' Thank You!",  -- Horde; https://www.wowhead.com/tbc/quest=6984 (Winter Veil event shown on the page)
    [7045] = "A Smokywood Pastures' Thank You!",  -- Alliance; https://www.wowhead.com/tbc/quest=7045 (Winter Veil event shown on the page)
    [8746] = "Metzen the Reindeer",  -- Horde; https://www.wowhead.com/tbc/quest=8746 (Winter Veil event shown on the page)
    [8762] = "Metzen the Reindeer",  -- Alliance; https://www.wowhead.com/tbc/quest=8762 (Winter Veil event shown on the page)
}

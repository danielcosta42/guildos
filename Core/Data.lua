----------------------------------------------------------------------
-- BRutus Guild Manager - Static Game Data
-- Color palettes, class colors, item quality colors, gear slot tables.
-- Loaded immediately after Core.lua so all modules can reference these.
----------------------------------------------------------------------

-- UI color constants
-- ── "Obsidian" theme ──────────────────────────────────────────────
-- Near-black neutral charcoal surfaces with a barely-perceptible cool
-- tint, a restrained desaturated-violet accent used only on interaction
-- / active states, and a softened champagne gold reserved for the brand
-- and key emphasis. Sleek and understated rather than colourful.
BRutus.Colors = {
    -- Brand / emphasis
    gold      = { r = 0.93, g = 0.80, b = 0.48 },           -- champagne gold (softened)
    darkGold  = { r = 0.70, g = 0.58, b = 0.30 },
    silver    = { r = 0.70, g = 0.72, b = 0.78 },           -- cool silver

    -- Surfaces (deepest → most elevated)
    bg0       = { r = 0.035, g = 0.035, b = 0.050, a = 1.0 }, -- wells / scroll backgrounds
    bg1       = { r = 0.050, g = 0.050, b = 0.066, a = 1.0 }, -- inputs / popups
    bg2       = { r = 0.066, g = 0.066, b = 0.084, a = 1.0 }, -- elevated sub-panels
    panel     = { r = 0.066, g = 0.066, b = 0.082, a = 0.98 },
    panelDark = { r = 0.044, g = 0.044, b = 0.058, a = 1.0 },

    -- Roster rows
    row1      = { r = 0.102, g = 0.102, b = 0.122, a = 1.0 },
    row2      = { r = 0.076, g = 0.076, b = 0.094, a = 1.0 },
    rowHover  = { r = 0.150, g = 0.142, b = 0.196, a = 1.0 }, -- subtle violet lift on hover

    -- Accent (use sparingly: borders on hover, active tabs, key marks)
    accent    = { r = 0.56, g = 0.48, b = 0.82 },           -- refined desaturated violet
    accentDim = { r = 0.30, g = 0.26, b = 0.44 },
    accentSoft= { r = 0.56, g = 0.48, b = 0.82, a = 0.14 },  -- faint accent wash for gradients

    -- Status / semantic
    online    = { r = 0.42, g = 0.84, b = 0.46 },
    offline   = { r = 0.46, g = 0.46, b = 0.52 },
    white     = { r = 1.0, g = 1.0, b = 1.0 },              -- pure (kept for vertex resets)
    text      = { r = 0.90, g = 0.90, b = 0.94 },           -- off-white body text
    textDim   = { r = 0.60, g = 0.61, b = 0.68 },           -- muted secondary text
    red       = { r = 0.90, g = 0.36, b = 0.40 },
    green     = { r = 0.42, g = 0.82, b = 0.46 },
    blue      = { r = 0.40, g = 0.58, b = 0.95 },

    -- Chrome
    headerBg  = { r = 0.094, g = 0.094, b = 0.118, a = 1.0 },
    border    = { r = 0.30, g = 0.29, b = 0.40, a = 0.55 },  -- cool, subtle
    separator = { r = 0.26, g = 0.25, b = 0.34, a = 0.35 },
    shadow    = { r = 0.0,  g = 0.0,  b = 0.0,  a = 0.55 },  -- drop-shadow tint
}

-- Accent color presets (themes). The accent drives hover borders, active
-- tabs and key highlights; BRutus:ApplyTheme() recolors the palette from
-- the chosen preset on load.
BRutus.ACCENT_PRESETS = {
    { key = "violet",  label = "Violet",  r = 0.56, g = 0.48, b = 0.82 },
    { key = "gold",    label = "Gold",    r = 0.85, g = 0.70, b = 0.35 },
    { key = "teal",    label = "Teal",    r = 0.30, g = 0.74, b = 0.72 },
    { key = "crimson", label = "Crimson", r = 0.82, g = 0.36, b = 0.42 },
    { key = "emerald", label = "Emerald", r = 0.36, g = 0.74, b = 0.48 },
    { key = "azure",   label = "Azure",   r = 0.38, g = 0.60, b = 0.92 },
}

-- Preferred fonts (centralised so new UI can reference one source).
BRutus.Fonts = {
    normal = "Fonts\\FRIZQT__.TTF",
    number = "Fonts\\ARIALN.TTF",  -- condensed; good for dense numeric columns
}

-- Class colors (TBC)
BRutus.ClassColors = {
    ["WARRIOR"]     = { r = 0.78, g = 0.61, b = 0.43 },
    ["PALADIN"]     = { r = 0.96, g = 0.55, b = 0.73 },
    ["HUNTER"]      = { r = 0.67, g = 0.83, b = 0.45 },
    ["ROGUE"]       = { r = 1.00, g = 0.96, b = 0.41 },
    ["PRIEST"]      = { r = 1.00, g = 1.00, b = 1.00 },
    ["SHAMAN"]      = { r = 0.00, g = 0.44, b = 0.87 },
    ["MAGE"]        = { r = 0.25, g = 0.78, b = 0.92 },
    ["WARLOCK"]     = { r = 0.53, g = 0.53, b = 0.93 },
    ["DRUID"]       = { r = 1.00, g = 0.49, b = 0.04 },
}

-- Item quality colors
BRutus.QualityColors = {
    [0] = { r = 0.62, g = 0.62, b = 0.62 }, -- Poor
    [1] = { r = 1.00, g = 1.00, b = 1.00 }, -- Common
    [2] = { r = 0.12, g = 1.00, b = 0.00 }, -- Uncommon
    [3] = { r = 0.00, g = 0.44, b = 0.87 }, -- Rare
    [4] = { r = 0.64, g = 0.21, b = 0.93 }, -- Epic
    [5] = { r = 1.00, g = 0.50, b = 0.00 }, -- Legendary
}

-- Inventory slot IDs for TBC
BRutus.SlotIDs = {
    { id = 1,  name = "HeadSlot" },
    { id = 2,  name = "NeckSlot" },
    { id = 3,  name = "ShoulderSlot" },
    { id = 15, name = "BackSlot" },
    { id = 5,  name = "ChestSlot" },
    { id = 9,  name = "WristSlot" },
    { id = 10, name = "HandsSlot" },
    { id = 6,  name = "WaistSlot" },
    { id = 7,  name = "LegsSlot" },
    { id = 8,  name = "FeetSlot" },
    { id = 11, name = "Finger0Slot" },
    { id = 12, name = "Finger1Slot" },
    { id = 13, name = "Trinket0Slot" },
    { id = 14, name = "Trinket1Slot" },
    { id = 16, name = "MainHandSlot" },
    { id = 17, name = "SecondaryHandSlot" },
    { id = 18, name = "RangedSlot" },
}

-- Slot display names
BRutus.SlotNames = {
    [1]  = "Head",
    [2]  = "Neck",
    [3]  = "Shoulder",
    [5]  = "Chest",
    [6]  = "Waist",
    [7]  = "Legs",
    [8]  = "Feet",
    [9]  = "Wrist",
    [10] = "Hands",
    [11] = "Ring 1",
    [12] = "Ring 2",
    [13] = "Trinket 1",
    [14] = "Trinket 2",
    [15] = "Back",
    [16] = "Main Hand",
    [17] = "Off Hand",
    [18] = "Ranged",
}

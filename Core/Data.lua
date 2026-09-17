----------------------------------------------------------------------
-- BRutus Guild Manager - Static Game Data
-- Color palettes, class colors, item quality colors, gear slot tables.
-- Loaded immediately after Core.lua so all modules can reference these.
----------------------------------------------------------------------

-- UI color constants
-- ── "Forever" skin ────────────────────────────────────────────────
-- Derived from the guildos.me production tokens (design handoff; see
-- docs/superpowers/specs/2026-09-14-forever-skin-design.md). Near-monochrome
-- with ONE accent: gold is the only colour allowed as a background, and violet
-- only ever means epic item quality. Class and item-quality colours never
-- live here; they come from the game.
local function rgb(r, g, b, a) return { r = r, g = g, b = b, a = a or 1 } end

-- A legacy key gets its own copy, so code that tweaks a colour in place can
-- never recolour the token behind it.
local function alias(t, a) return rgb(t.r, t.g, t.b, a or t.a) end

local T = {
    bg       = rgb(0.063, 0.059, 0.086),  -- #100f16 window background (elevation 2)
    panel    = rgb(0.090, 0.086, 0.122),  -- #17161f card, title bar, column header (3)
    popup    = rgb(0.114, 0.106, 0.149),  -- #1d1b26 popup, dropdown, tooltip, selected row (4)
    well     = rgb(0.047, 0.043, 0.063),  -- #0c0b10 table body, input, scroll area (1)
    line     = rgb(0.165, 0.153, 0.200),  -- #2a2733 1px border and separator
    lineHi   = rgb(0.227, 0.212, 0.275),  -- #3a3646 popup border, border hover, scroll thumb
    text     = rgb(0.925, 0.906, 0.878),  -- #ece7e0 primary text
    textSoft = rgb(0.663, 0.635, 0.690),  -- #a9a2b0 supporting text
    label    = rgb(0.592, 0.565, 0.624),  -- #97909f mono label, section caption
    labelDim = rgb(0.435, 0.408, 0.471),  -- #6f6878 metric label, secondary column, footer
    disabled = rgb(0.294, 0.271, 0.325),  -- #4b4553 disabled and ghost text
    gold     = rgb(0.851, 0.663, 0.310),  -- #d9a94f the only brand accent
    onGold   = rgb(0.090, 0.075, 0.039),  -- #17130a text on gold
    ok       = rgb(0.490, 0.847, 0.561),  -- #7dd88f present, online, confirmed
    danger   = rgb(0.812, 0.357, 0.322),  -- #cf5b52 absence, penalty, kick, ban, error
    info     = rgb(0.357, 0.576, 0.812),  -- #5b93cf link to the site, sync, bot
    epic     = rgb(0.659, 0.435, 0.878),  -- #a86fe0 epic item quality, nothing else
}

local ACCENT_DIM  = 0.54  -- dimmed gold for secondary marks
local ACCENT_WASH = 0.14  -- alpha of the faint gold wash
local SHADOW      = 0.55  -- drop-shadow alpha (elevation 4 only)

BRutus.Colors = {
    bg = T.bg, panel = T.panel, popup = T.popup, well = T.well,
    line = T.line, lineHi = T.lineHi,
    text = T.text, textSoft = T.textSoft, label = T.label, labelDim = T.labelDim,
    disabled = T.disabled,
    gold = T.gold, onGold = T.onGold,
    ok = T.ok, danger = T.danger, info = T.info, epic = T.epic,

    -- Legacy keys. Screens older than the Forever skin still read these; each
    -- one points at the token that plays its role now. New code uses the tokens.
    silver     = alias(T.textSoft),
    textDim    = alias(T.label),
    white      = rgb(1, 1, 1),        -- pure white: vertex resets on icons and textures
    border     = alias(T.line),
    separator  = alias(T.line),
    accent     = alias(T.gold),
    accentDim  = rgb(T.gold.r * ACCENT_DIM, T.gold.g * ACCENT_DIM, T.gold.b * ACCENT_DIM),
    accentSoft = alias(T.gold, ACCENT_WASH),
    headerBg   = alias(T.panel),
    bg0        = alias(T.well),
    bg1        = alias(T.well),
    bg2        = alias(T.panel),
    panelDark  = alias(T.well),
    row1       = alias(T.well),
    row2       = alias(T.bg),         -- faint zebra until tables get 1px separators (#15)
    rowHover   = alias(T.panel),
    red        = alias(T.danger),
    green      = alias(T.ok),
    blue       = alias(T.info),
    online     = alias(T.ok),
    offline    = alias(T.disabled),
    shadow     = rgb(0, 0, 0, SHADOW),
}

-- Fonts. Four OFL files ship in Media/Fonts with their licences. Serif only
-- from 14px up; everything smaller is IBM Plex Mono, never under 10px; no
-- outline anywhere (design handoff §2).
local FONT_DIR     = "Interface\\AddOns\\GuildOS\\Media\\Fonts\\"
local SERIF        = FONT_DIR .. "Spectral-Regular.ttf"
local SERIF_STRONG = FONT_DIR .. "Spectral-SemiBold.ttf"
local MONO         = FONT_DIR .. "IBMPlexMono-Regular.ttf"
local MONO_STRONG  = FONT_DIR .. "IBMPlexMono-Medium.ttf"

BRutus.Fonts = {
    serif = SERIF, serifStrong = SERIF_STRONG, mono = MONO, monoStrong = MONO_STRONG,

    -- Roles from the handoff type scale.
    wordmark     = { file = SERIF_STRONG, size = 18 },
    windowTitle  = { file = SERIF,        size = 16 },
    sectionTitle = { file = SERIF_STRONG, size = 15 },
    body         = { file = SERIF,        size = 14 },
    memberName   = { file = SERIF_STRONG, size = 14 },
    itemName     = { file = SERIF_STRONG, size = 17 },
    caption      = { file = MONO,         size = 10 },
    tableNum     = { file = MONO,         size = 12 },
    colHeader    = { file = MONO_STRONG,  size = 10 },
    metricValue  = { file = MONO,         size = 22 },
    countdown    = { file = MONO,         size = 38 },
    badge        = { file = MONO,         size = 10 },

    -- Older readers expect one font for everything.
    normal = MONO,
    number = MONO,
}

local SERIF_MIN = 14  -- serif blurs below this at UI scale 1.0
local MONO_MIN  = 10  -- nothing reads below this

-- Set a FontString's font. A role from BRutus.Fonts picks the file (and the
-- size unless one is given); otherwise 14px and up is Spectral and anything
-- smaller is IBM Plex Mono. Either way serif never lands under 14px (it reads
-- as mono instead) and mono is clamped to 10px. Never outlined. Returns the
-- file and size used.
function BRutus:ApplyFont(fontString, size, role)
    local spec = role and BRutus.Fonts[role]
    local file, px
    if type(spec) == "table" then
        file, px = spec.file, tonumber(size) or spec.size
    else
        px = tonumber(size) or MONO_MIN
        file = (px >= SERIF_MIN) and SERIF or MONO
    end
    if (file == SERIF or file == SERIF_STRONG) and px < SERIF_MIN then
        file = MONO
    end
    if file ~= SERIF and file ~= SERIF_STRONG then
        px = math.max(MONO_MIN, px)
    end
    -- Only an explicit false means the file did not load; clients that return
    -- nothing on success must not be pushed onto the fallback.
    if fontString:SetFont(file, px, "") == false then
        fontString:SetFont(STANDARD_TEXT_FONT, px, "")
    end
    return file, px
end

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

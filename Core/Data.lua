----------------------------------------------------------------------
-- Guild OS - Static Game Data
-- Color palettes, class colors, item quality colors, gear slot tables.
-- Loaded immediately after Core.lua so all modules can reference these.
----------------------------------------------------------------------

-- UI color constants
-- ── The GuildOS style's palette ──────────────────────────────────────
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
    lineHi   = rgb(0.435, 0.408, 0.471),  -- #6f6878 control border, popup border, scroll thumb (3.56:1)
    text     = rgb(0.925, 0.906, 0.878),  -- #ece7e0 primary text
    textSoft = rgb(0.663, 0.635, 0.690),  -- #a9a2b0 supporting text
    label    = rgb(0.592, 0.565, 0.624),  -- #97909f mono label, section caption
    labelDim = rgb(0.435, 0.408, 0.471),  -- #6f6878 metric label, secondary column, footer
    disabled = rgb(0.294, 0.271, 0.325),  -- #4b4553 disabled and ghost text
    gold     = rgb(0.851, 0.663, 0.310),  -- #d9a94f the only brand accent
    goldHover  = rgb(0.890, 0.725, 0.408),  -- #e3b968 primary button under the cursor
    goldActive = rgb(0.769, 0.580, 0.247),  -- #c4943f primary button held down
    onGold   = rgb(0.090, 0.075, 0.039),  -- #17130a text on gold
    ok       = rgb(0.490, 0.847, 0.561),  -- #7dd88f present, online, confirmed
    danger   = rgb(0.937, 0.482, 0.447),  -- #ef7b72 absence, penalty, kick, ban, error
    warn     = rgb(0.910, 0.604, 0.353),  -- #e89a5a a score between ok and danger
    info     = rgb(0.357, 0.576, 0.812),  -- #5b93cf the tank role, a link to the site, sync
    epic     = rgb(0.659, 0.435, 0.878),  -- #a86fe0 epic item quality, nothing else
}

local ACCENT_DIM  = 0.54  -- dimmed gold for secondary marks
local ACCENT_WASH = 0.14  -- alpha of the faint gold wash

GuildOS.Colors = {
    bg = T.bg, panel = T.panel, popup = T.popup, well = T.well,
    line = T.line, lineHi = T.lineHi,
    text = T.text, textSoft = T.textSoft, label = T.label, labelDim = T.labelDim,
    disabled = T.disabled,
    gold = T.gold, goldHover = T.goldHover, goldActive = T.goldActive, onGold = T.onGold,
    ok = T.ok, danger = T.danger, warn = T.warn, info = T.info, epic = T.epic,

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
}

-- The legacy keys and the token each copies, so a style can re-point the palette in place
-- (issue #122): every module that captured `local C = GuildOS.Colors`, or one of its colours, sees it.
local ALIASES = {
    silver = { "textSoft" }, textDim = { "label" }, border = { "line" }, separator = { "line" },
    accent = { "gold" }, accentDim = { "gold", dim = ACCENT_DIM }, accentSoft = { "gold", a = ACCENT_WASH },
    headerBg = { "panel" }, bg0 = { "well" }, bg1 = { "well" }, bg2 = { "panel" }, panelDark = { "well" },
    row1 = { "well" }, row2 = { "bg" }, rowHover = { "panel" },
    red = { "danger" }, green = { "ok" }, blue = { "info" }, online = { "ok" }, offline = { "disabled" },
}

-- Re-point the named tokens in place, then every legacy key from its token.
function GuildOS:RepointColors(tokens)
    local C = GuildOS.Colors
    for key, v in pairs(tokens) do
        local t = C[key]
        if t then t.r, t.g, t.b, t.a = v.r, v.g, v.b, v.a or 1 end
    end
    for key, how in pairs(ALIASES) do
        local src, t, k = C[how[1]], C[key], how.dim or 1
        t.r, t.g, t.b, t.a = src.r * k, src.g * k, src.b * k, how.a or src.a
    end
end

-- Fonts. Five OFL files ship in Media/Fonts with their licences: IBM Plex Sans
-- for words, IBM Plex Mono only through the roles that ask for it (numbers,
-- captions, column headers, badges). Sans never under 11px, mono never under
-- 10px; no outline anywhere (docs/superpowers/specs/2026-11-17-swiss-identity-design.md).
local FONT_DIR    = "Interface\\AddOns\\GuildOS\\Media\\Fonts\\"
local SANS        = FONT_DIR .. "IBMPlexSans-Regular.ttf"
local SANS_MEDIUM = FONT_DIR .. "IBMPlexSans-Medium.ttf"
local SANS_STRONG = FONT_DIR .. "IBMPlexSans-SemiBold.ttf"
local MONO        = FONT_DIR .. "IBMPlexMono-Regular.ttf"
local MONO_STRONG = FONT_DIR .. "IBMPlexMono-Medium.ttf"

GuildOS.Fonts = {
    sans = SANS, sansMedium = SANS_MEDIUM, sansStrong = SANS_STRONG, mono = MONO, monoStrong = MONO_STRONG,

    -- Roles from the type scale (10, 11, 12, 14, 16, 18, 24, 40).
    wordmark     = { file = SANS_STRONG, size = 18 },
    windowTitle  = { file = SANS_STRONG, size = 16 },
    sectionTitle = { file = SANS_STRONG, size = 14 },
    body         = { file = SANS,        size = 12 },
    memberName   = { file = SANS_MEDIUM, size = 12 },
    itemName     = { file = SANS_STRONG, size = 14 },
    button       = { file = SANS_MEDIUM, size = 12 },
    caption      = { file = MONO,        size = 10 },
    tableNum     = { file = MONO,        size = 11 },
    colHeader    = { file = MONO_STRONG, size = 10 },
    metricValue  = { file = MONO,        size = 24 },
    countdown    = { file = MONO,        size = 40 },
    badge        = { file = MONO,        size = 10 },

    -- Older readers expect one font for words and one for numbers.
    normal = SANS,
    number = MONO,
}

local SANS_MIN = 11  -- sans reads poorly below this at UI scale 1.0
local MONO_MIN = 10  -- nothing reads below this

-- Korean and Chinese clients (issue #103): IBM Plex Sans and Mono carry Latin and Cyrillic but
-- no Hangul and no Han, so every character, guild, item and zone name the client gave in those
-- languages drew as boxes. There the client's own font, which has the language, is the only one
-- used, whatever the setting says.
GuildOS.GameFontOnly = ({ koKR = true, zhCN = true, zhTW = true })[GuildOS.Locale or ""] == true

-- Set a FontString's font. A role from GuildOS.Fonts picks the file (and the
-- size unless one is given); text with no role is IBM Plex Sans. Sans is
-- clamped to 11px and mono to 10px. Never outlined. Returns the file and size used.
function GuildOS:ApplyFont(fontString, size, role)
    local spec = role and GuildOS.Fonts[role]
    local file = type(spec) == "table" and spec.file or SANS
    local px = tonumber(size) or (type(spec) == "table" and spec.size) or SANS_MIN
    px = math.max((file == MONO or file == MONO_STRONG) and MONO_MIN or SANS_MIN, px)
    -- The player's choice (issue #57): the client's own font at the same sizes. A personal
    -- display preference, so it lives at the account root (GuildOSDB.font) and follows the
    -- player to every alt and guild, as the minimap button's does. Read on every call; a
    -- text drawn before a change keeps its font until the interface reloads.
    if GuildOS.GameFontOnly or (GuildOS.Style and GuildOS.Style.gameFont)
        or (type(GuildOSDB) == "table" and GuildOSDB.font == "game") then
        fontString:SetFont(STANDARD_TEXT_FONT, px, "")
        return STANDARD_TEXT_FONT, px
    end
    -- Only an explicit false means the file did not load; clients that return
    -- nothing on success must not be pushed onto the fallback.
    if fontString:SetFont(file, px, "") == false then
        fontString:SetFont(STANDARD_TEXT_FONT, px, "")
    end
    return file, px
end

-- Class colors (TBC)
GuildOS.ClassColors = {
    ["WARRIOR"]     = { r = 0.78, g = 0.61, b = 0.43 },
    ["PALADIN"]     = { r = 0.96, g = 0.55, b = 0.73 },
    ["HUNTER"]      = { r = 0.67, g = 0.83, b = 0.45 },
    ["ROGUE"]       = { r = 1.00, g = 0.96, b = 0.41 },
    ["PRIEST"]      = { r = 1.00, g = 1.00, b = 1.00 },
    ["SHAMAN"]      = { r = 0.00, g = 0.44, b = 0.87 },
    ["MAGE"]        = { r = 0.25, g = 0.78, b = 0.92 },
    ["WARLOCK"]     = { r = 0.53, g = 0.53, b = 0.93 },
    ["DRUID"]       = { r = 1.00, g = 0.49, b = 0.04 },
    -- Retail's four (ADR-0026); never met on a classic client.
    ["DEATHKNIGHT"] = { r = 0.77, g = 0.12, b = 0.23 },
    ["DEMONHUNTER"] = { r = 0.64, g = 0.19, b = 0.79 },
    ["MONK"]        = { r = 0.00, g = 1.00, b = 0.60 },
    ["EVOKER"]      = { r = 0.20, g = 0.58, b = 0.50 },
}

-- Item quality colors
GuildOS.QualityColors = {
    [0] = { r = 0.62, g = 0.62, b = 0.62 }, -- Poor
    [1] = { r = 1.00, g = 1.00, b = 1.00 }, -- Common
    [2] = { r = 0.12, g = 1.00, b = 0.00 }, -- Uncommon
    [3] = { r = 0.00, g = 0.44, b = 0.87 }, -- Rare
    [4] = { r = 0.64, g = 0.21, b = 0.93 }, -- Epic
    [5] = { r = 1.00, g = 0.50, b = 0.00 }, -- Legendary
}

-- Inventory slot IDs for TBC
GuildOS.SlotIDs = {
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
GuildOS.SlotNames = {
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

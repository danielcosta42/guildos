----------------------------------------------------------------------
-- Guild OS - Static Game Data
-- Color palettes, class colors, item quality colors, gear slot tables.
-- Loaded immediately after Core.lua so all modules can reference these.
----------------------------------------------------------------------

-- UI color constants
-- ── The Salão's palette (specs/salao/fase3.md) ───────────────────────
-- The approved mockup's: dark wood and bronze around parchment cards, the
-- game's yellow and a softer gold for what is chosen, a crimson primary
-- button. Violet only ever means epic item quality. Class and item-quality
-- colours never live here; they come from the game.
local function rgb(r, g, b, a) return { r = r, g = g, b = b, a = a or 1 } end
local function hex(h, a)
    return rgb(tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255, a)
end

-- A legacy key gets its own copy, so code that tweaks a colour in place can
-- never recolour the token behind it.
local function alias(t, a) return rgb(t.r, t.g, t.b, a or t.a) end

local T = {
    bg       = hex("24170d"),  -- the window, behind the wood
    panel    = hex("2a1a0d"),  -- the room's entry strip, a dark tile, a column header
    popup    = hex("1a1009"),  -- popup, dropdown, tooltip, footer, a round tool
    well     = hex("120b06"),  -- a field, a table body, an inset on the wood
    line     = hex("3a2a17"),  -- a row's line and a separator on the wood
    lineHi   = hex("6b5326"),  -- the metal: a control's, a dark card's and the frame's border
    text     = hex("f6e9cf"),  -- the ink on the wood
    textSoft = hex("cdb98e"),  -- supporting text on the wood
    label    = hex("bba57a"),  -- a caption, the footer
    labelDim = hex("9e8f77"),  -- a secondary caption
    disabled = hex("5b5348"),  -- disabled text, an offline dot
    gold     = hex("ffd100"),  -- the game's yellow: the guild's name, the open room, a table's header
    goldHover  = hex("ffe04d"),
    goldActive = hex("d9b200"),
    onGold   = hex("3b2512"),  -- text on gold
    ok       = hex("7dd88f"),  -- present, online, confirmed
    danger   = hex("ef7b72"),  -- absence, penalty, kick, ban, error
    warn     = hex("e89a5a"),  -- a score between ok and danger
    info     = hex("5b93cf"),  -- the tank role, a link to the site, sync
    epic     = hex("a86fe0"),  -- epic item quality, nothing else
    -- The Salão's own (fase 3).
    gold2     = hex("ffd77a"),  -- the soft gold: a chosen pill, a dark card's title, an avatar's ring
    metal2    = hex("c9a24a"),  -- the bright metal: the frame's inner line, the crest's ring
    door      = hex("e6d2a5"),  -- a room's door, an entry pill at rest
    wood      = hex("3b2614"),  -- the open door, the wood's first board
    crimson   = hex("b0261b"),  -- the primary button (its light falls to #6a0f08)
    crimsonLine = hex("d6a84b"),
    crimsonInk  = hex("ffe08a"),
    count     = hex("c0392b"),  -- a red count on a door or an entry
    darkButton  = hex("3a2c17"),  -- the dark button (its light falls to #20180d)
    darkInk     = hex("f2d68a"),
    darkCard  = rgb(10 / 255, 5 / 255, 2 / 255, 0.55),  -- a dark card on the wood
    -- The parchment cards: the paper, its ink and its softer ink, its lines, its title and its shadowed edge.
    paper      = hex("f3e4c2"),
    paperInk   = hex("3a2a17"),
    paperSoft  = hex("6f5a3c"),
    paperLine  = hex("dcc79c"),
    paperRule  = hex("c9b48a"),
    paperTitle = hex("6b1d0e"),
    paperEdge  = hex("b49867"),
    paperLight = hex("fffaf0"),  -- a field and a pinned note on the paper
    paperLink  = hex("8a5a20"),
    quiet      = hex("fff6de"),  -- the quiet button, cream on the paper (its light falls to #e8d3a6)
    quietInk   = hex("5a3b17"),
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
    gold2 = T.gold2, metal2 = T.metal2, door = T.door, wood = T.wood, crimson = T.crimson,
    crimsonLine = T.crimsonLine, crimsonInk = T.crimsonInk, count = T.count, darkCard = T.darkCard,
    darkButton = T.darkButton, darkInk = T.darkInk,
    paper = T.paper, paperInk = T.paperInk, paperSoft = T.paperSoft, paperLine = T.paperLine,
    paperRule = T.paperRule, paperTitle = T.paperTitle, paperEdge = T.paperEdge, paperLight = T.paperLight,
    paperLink = T.paperLink, quiet = T.quiet, quietInk = T.quietInk,

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

-- Fonts (specs/salao/fase3.md). The mockup's three, under the SIL Open Font License, in Media/Fonts with
-- their licences: Cinzel Bold for titles (the guild's name, a card's title, a table's header, a number in a
-- tile), Alegreya Sans for the interface (regular, medium, bold) and Alegreya for reading (a note, a message).
-- Cinzel and Alegreya ship as variable fonts and WoW reads only a variable font's default instance, so the
-- files here are static instances cut with fontTools (Cinzel at 700, Alegreya at 400).
-- The Salão's phase 1 drew everything in the game's font (#445); phase 3 reverses that on purpose: the
-- game's font with the game's art read as generic Forever, and IBM Plex as a dashboard.
local FONT_DIR   = "Interface\\AddOns\\GuildOS\\Media\\Fonts\\"
local TITLE      = FONT_DIR .. "Cinzel-Bold.ttf"
local UI_REGULAR = FONT_DIR .. "AlegreyaSans-Regular.ttf"
local UI_MEDIUM  = FONT_DIR .. "AlegreyaSans-Medium.ttf"
local UI_BOLD    = FONT_DIR .. "AlegreyaSans-Bold.ttf"
local READING    = FONT_DIR .. "Alegreya-Regular.ttf"
GuildOS.FONT_DIR = FONT_DIR

GuildOS.Fonts = {
    title = TITLE, ui = UI_REGULAR, uiMedium = UI_MEDIUM, uiBold = UI_BOLD, read = READING,
    -- The names older readers know, on the faces that play their part now.
    sans = UI_REGULAR, sansMedium = UI_MEDIUM, sansStrong = UI_BOLD, mono = UI_REGULAR, monoStrong = UI_BOLD,

    -- Roles. A title is never upper case and never letter-spaced: Cinzel's small capitals are the look.
    wordmark     = { file = TITLE,      size = 16 },
    windowTitle  = { file = TITLE,      size = 15 },
    sectionTitle = { file = TITLE,      size = 15 },   -- UI.SP.TITLE (#449)
    colHeader    = { file = TITLE,      size = 11 },   -- UI.SP.META
    metricValue  = { file = TITLE,      size = 18 },
    countdown    = { file = TITLE,      size = 36 },
    body         = { file = UI_REGULAR, size = 13 },
    memberName   = { file = UI_MEDIUM,  size = 13 },
    itemName     = { file = UI_BOLD,    size = 14 },
    button       = { file = UI_BOLD,    size = 12 },
    caption      = { file = UI_REGULAR, size = 11 },
    tableNum     = { file = UI_REGULAR, size = 12 },
    badge        = { file = UI_BOLD,    size = 11 },
    reading      = { file = READING,    size = 13 },

    normal = UI_REGULAR,
    number = UI_REGULAR,
}

local UI_MIN    = 11  -- Alegreya Sans reads poorly below this at UI scale 1.0
local TITLE_MIN = 10  -- Cinzel's small capitals read down to here
-- Alegreya Sans is smaller on its body than the fonts the screens were laid out with: a size a screen asks
-- for draws this much larger, so a 12 reads as a 12 did.
local UI_BUMP   = 1

-- Korean and Chinese clients (issue #103): none of the three has Hangul or Han, so every character, guild,
-- item and zone name the client gave in those languages would draw as boxes. There the client's own fonts
-- are the only ones used. Cinzel has no Cyrillic either: on a Russian client a title takes the game's.
GuildOS.GameFontOnly = ({ koKR = true, zhCN = true, zhTW = true })[GuildOS.Locale or ""] == true
local LATIN_ONLY = { [TITLE] = true }

-- The game's title face where the client has one: the font its quest titles use (Morpheus on Latin clients,
-- its Cyrillic cut on ruRU, the client's own on koKR, zhCN and zhTW), else its standard text font.
local function gameTitleFont()
    local f = QuestTitleFont and QuestTitleFont.GetFont and select(1, QuestTitleFont:GetFont())
    return f or STANDARD_TEXT_FONT
end

-- The player's own choice of the game's font (Settings > Interface, "Use the game's font"): saved at the account's
-- root as GuildOSDB.gameFont, read once at load by Style:Resolve, so a change waits for /reload. The key is new on
-- purpose: GuildOSDB.font = "game" from before the Salão (#445) stays ignored, nobody is switched back unasked.
function GuildOS:UsesGameFont()
    return GuildOS.GameFontOnly or (GuildOS.Style ~= nil and GuildOS.Style.gameFont == true)
end

-- The file `file` draws with on this client: itself, or the game's font where it lacks the language or the
-- player chose the game's.
function GuildOS:FontFace(file)
    if GuildOS:UsesGameFont() or (LATIN_ONLY[file] and GuildOS.Locale == "ruRU") then
        return file == TITLE and gameTitleFont() or STANDARD_TEXT_FONT
    end
    return file
end

-- Set a FontString's font. A role from GuildOS.Fonts picks the file (and the size unless one is given);
-- text with no role is Alegreya Sans. The interface's faces draw UI_BUMP larger and never under 11px, a
-- title never under 10px. Never outlined. Returns the file and size used.
function GuildOS:ApplyFont(fontString, size, role)
    local spec = role and GuildOS.Fonts[role]
    local file = type(spec) == "table" and spec.file or UI_REGULAR
    local px = tonumber(size) or (type(spec) == "table" and spec.size) or UI_MIN
    if file == TITLE then
        px = math.max(TITLE_MIN, px)
    else
        px = math.max(UI_MIN, px + (tonumber(size) and UI_BUMP or 0))
    end
    local face = GuildOS:FontFace(file)
    fontString.__gosFont = { file = file, face = face, px = px, asked = tonumber(size) or px }
    -- Only an explicit false means the file did not load; clients that return nothing on success must not be
    -- pushed onto the fallback.
    if fontString:SetFont(face, px, "") == false and face ~= STANDARD_TEXT_FONT then
        fontString:SetFont(STANDARD_TEXT_FONT, px, "")
        return STANDARD_TEXT_FONT, px
    end
    return face, px
end

-- Whether `text` draws in a Latin font: every character Latin (to U+024F) or general punctuation
-- (U+2000-U+206F). A player's text (a guild's name, an event's title) can be Cyrillic or Hangul on any client.
function GuildOS.IsLatinText(text)
    local s, i, n = tostring(text or ""), 1, #tostring(text or "")
    while i <= n do
        local b = s:byte(i)
        if b < 0x80 then
            i = i + 1
        elseif b >= 0xC0 and b < 0xE0 then
            local cp = (b - 0xC0) * 64 + ((s:byte(i + 1) or 0x80) - 0x80)
            if cp > 0x24F then return false end
            i = i + 2
        elseif b >= 0xE0 and b < 0xF0 then
            local cp = (b - 0xE0) * 4096 + ((s:byte(i + 1) or 0x80) - 0x80) * 64 + ((s:byte(i + 2) or 0x80) - 0x80)
            if cp < 0x2000 or cp > 0x206F then return false end
            i = i + 3
        elseif b >= 0xF0 then
            return false
        else
            i = i + 1   -- a stray continuation byte
        end
    end
    return true
end

-- Set a title's text: in its title face when the text is Latin, else in the interface's bold face (which has
-- Cyrillic and Greek) or the game's font, so a guild or an event named in another script never draws as boxes.
function GuildOS:SetTitleText(fontString, text)
    local f = fontString.__gosFont
    if f and f.file == TITLE then
        local want = GuildOS.IsLatinText(text) and GuildOS:FontFace(TITLE) or GuildOS:FontFace(UI_BOLD)
        if want ~= f.face then
            fontString:SetFont(want, f.px, "")
            f.face = want
        end
    end
    fontString:SetText(text)
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

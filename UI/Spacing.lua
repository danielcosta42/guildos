----------------------------------------------------------------------
-- Guild OS - The spacing standard (#449, specs/salao/fase3.md "Espaçamento")
-- Frame-free, loaded before UI/Helpers.lua, which hands it on as UI.SP; a test reads it alone.
----------------------------------------------------------------------
-- The spacing standard (#449, specs/salao/fase3.md "Espaçamento"): the one scale every screen and every
-- primitive below reads. Unit 4. Text sizes are the ones a screen asks the text API for (GuildOS:ApplyFont
-- draws Alegreya Sans one px larger, Cinzel as asked); nothing on a card asks for less than META.
--   PAD        a card's padding: its content never touches its edge
--   GAP        between two cards
--   SECTION    between two sections of a card; TITLE_GAP a section title to its content
--   FIELD      a field's (input, select, form button) height; LABEL_GAP its label above it; FIELD_GAP between fields
--   ROW        a table's row (ROW_AV with an avatar); CELL a cell's breathing room
--   BODY/META  body text and the meta line (time, count, caption); TITLE a section title (Cinzel); KPI a number
--   HIT        the smallest click target
--   TWO_COLS   the content's width from which cards sit in two columns
--   MARGIN     the room's margin around a screen
local SP = {
    UNIT = 4, PAD = 16, GAP = 14, SECTION = 18, TITLE_GAP = 8, TITLE_H = 18,
    FIELD = 26, LABEL_GAP = 4, FIELD_GAP = 12, ROW = 28, ROW_AV = 32, CELL = 10,
    BODY = 13, META = 11, TITLE = 15, KPI = 22, HIT = 24, TWO_COLS = 900, MARGIN = 8,
}
SP.TOP = SP.PAD + SP.TITLE_H + SP.TITLE_GAP   -- where a titled card's content starts
SP.FORM_ROW = SP.FIELD + SP.FIELD_GAP         -- one line of a form
GuildOS.Spacing = SP

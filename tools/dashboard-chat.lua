-- The Now cards' guild chat (issue #126), run against the real UI/Dashboard.lua and the Helpers it
-- draws with, on tools/dashboard-layout.lua's stub client (#377).
--
-- The big card under the others was "Guild activity", which repeated the Activity column beside
-- it and stood mostly empty. It is the guild's chat now: the feed Guild > Chat shows, with its
-- channel tabs and its box, and the arrow opens Guild > Chat. Since #377 it is one of the equal
-- cards of the grid, lit under the mouse as the others are.
--
--   luajit -e 'ADDON="."' tools/dashboard-chat.lua
--
-- Exits 1 on the first failed check.
ADDON = ADDON or "."
DASHBOARD_KIT = true
local kit = dofile(ADDON .. "/tools/dashboard-layout.lua")
DASHBOARD_KIT = nil
local check, fire, same = kit.check, kit.fire, kit.same

kit.client({ style = "guildos" })
local C = GuildOS.Colors
local panel = kit.newFrame("Frame", UIParent)
panel:SetSize(640, 516)
local refresh = GuildOS:CreateDashboardPanel(panel)
check(pcall(refresh) and pcall(refresh), "the Now cards draw, twice")

-- The feed itself, channel tabs included, is Guild > Chat's, tested in tools/window-shell.lua: here
-- only how the card uses it.
local card, titles = nil, {}
for _, c in ipairs(panel.dash.cards) do
  titles[c.hdr.text] = true
  if c.hdr.text == "GUILD CHAT" then card = c end
end
check(card ~= nil and not titles["GUILD ACTIVITY"], "a card is the guild's chat; the activity it repeated is gone")
check(#kit.feeds == 1 and kit.feeds[1] == card.body, "its body holds the chat feed, built once")
check(kit.feedRefreshed == 2, "and drawn again with the rest of the cards")
check(card.scripts.OnMouseUp == nil, "a click in the chat (a link, the box) stays in it")
local arrow
for _, f in ipairs(card.children) do
  if f.kind == "Button" and f.scripts.OnClick then arrow = f end
end
check(arrow ~= nil, "the arrow is a button")
fire(arrow, "OnClick")
check(kit.opened and kit.opened[1] == "guild" and kit.opened[2] == "chat", "that opens Guild > Chat")
fire(arrow, "OnEnter")
check(same(card.arrow.color, C.text) and same(card.border, C.label),
  "and lights up under the mouse, as a card does (never in gold)")
fire(arrow, "OnLeave")
check(same(card.arrow.color, C.label) and same(card.border, C.line), "and dims when it leaves")
local first = panel.dash.cards[1]
check(card.w == first.w and card.h == first.h and card.w > 0, "the chat card is the size of every other (#377)")

print(string.format("dashboard-chat: %d checks passed", kit.count()))

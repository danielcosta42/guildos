# Professions on WoW: Forever — directory

Issue: danielcosta42/guildos#33 · Epic: #30 (sub-project 2 of 5) · Forever only · Builds on #31

## 1. Problem

The foundation (#31) collects every member's professions and recipes, but the only screen that shows
them is the old recipes panel: a search over what members already know. It cannot say what the guild
does **not** cover, has no per-profession view of the crafters and their levels, and knows nothing of
the catalog's reagents, sources, specializations or crafting stations. The item tooltip's "Crafted by"
rebuilds a quadratic index every 30 seconds over every member's lists.

## 2. Design

### 2.1 Data — `Modules/ProfDirectory.lua` (Forever only, pure and tested)
`BRutus.ProfDirectory`, reading `BRutus.ProfCatalog` and `BRutus.Professions`:
- `Lines()` — the catalog's profession lines in display order: primaries, then secondaries, each
  group by localized name.
- `DisplayName(line)` — `L[en]` (pt-BR translations added for the 12 professions).
- `RecipeName(id)` — localized recipe name via `Compat.GetSpellInfo`, cached; `"#id"` if unknown.
- `Coverage(line)` — `{ total, covered, crafters }`: catalog recipes on the line, how many at least
  one member knows, how many members have the line.
- `RecipeRows(line, mode, query)` — the catalog's recipes on `line` (every line when nil), each
  `{ id, line, name, yellow, grey, out, spec, focus, src, reqSkill, recipeItem, crafters = { keys } }`;
  `mode` is `"all"`, `"guild"` (known by someone) or `"gaps"` (known by nobody); `query` matches the
  localized name, case-insensitive, as plain text. Sorted by yellow rank, then name.
- `MemberRows(line)` — members with the line: `{ key, name, class, online, rank, max, spec, count,
  native }`, sorted by rank (native last), then name. Name, class and online come from the guild
  roster, read once per call.
- `ItemRecipes(itemID)` — catalog recipes that create the item (a map built once from the catalog).
- `CraftersForItem(itemID)` / `CraftersForSpell(spellID)` — RecipeTracker's shape,
  `{ { playerName, playerKey, class, profName } }`, or nil.
- `Reagents(id)` — `{ { itemID, count } }`.

### 2.2 The panel — `UI/ProfessionsPanel.lua` (Forever only)
Replaces the recipes panel on Forever: `UI/Features.lua` builds `CreateProfessionsPanel` and labels the
tab "Professions" when it exists; Anniversary keeps "Recipes".
- **Left rail** (170 px): "All" plus each line from `Lines()`: profession icon, localized name and a
  second line "N crafters · P%" (coverage). The selected one is highlighted.
- **Top bar**: title, two sub-tabs **Recipes** / **Crafters**, the search box (Recipes only) and
  three filter buttons **All / In the guild / Nobody crafts** (Recipes only).
- **Recipes list** (virtual rows, 24 px): recipe icon and name; the skill range `yellow–grey`; the
  crafters (up to three names, online first, class-coloured, `+N`; "nobody" in the danger colour);
  requirements (specialization and station, short). Columns drop by priority as the window narrows
  (`UI:ResolveColumns`). Hover shows the item (or enchant) tooltip; click opens the recipe card.
- **Crafters list**: name (class colour, online dot), a progress bar with `rank / max` (no bar and
  "no addon" for a native record), specialization, recipe count.
- **Recipe card** (popup beside the window): output item, reagents with icons and counts, source
  (trainer, recipe item with its link, or automatic), required skill (recipe items), specialization,
  station, and the crafters with a Whisper button each (online first).
- An empty state per list ("No recipes match", "Nobody in the guild has this profession yet").

### 2.3 Tooltips
- `RecipeTracker:GetCraftersForItem` / `GetCraftersForSpell` read `ProfDirectory` on Forever (no
  30-second quadratic rebuild).
- An item the catalog can craft that no member knows gets one line, "Nobody in the guild crafts
  this", under the item.

### 2.4 Out of scope
Coverage planning for officers (sub-project 3), the site (4), crafting requests (5), stations as a
guild inventory (which member can deploy which camp object — needs the station ↔ camp-object mapping,
not in the catalog yet).

## 3. Tests
- `tools/professions.lua` gains a `ProfDirectory` section on the fixture catalog: display order,
  coverage, rows in each mode, query (plain text, case-insensitive), sort, member rows (native last,
  roster name/class/online), item → recipes, crafters in RecipeTracker's shape, reagents.
- `RecipeTracker:GetCraftersForItem` routes to the directory on Forever.
- The panel and the card are checked in game (maintainer): layout at narrow and wide sizes, pt-BR.

# Web panel: the companion's commands as buttons

The web app went live and the addon still hides its whole surface behind slash commands
nobody discovers: `/gos web [on|off]`, `/gos roster`, `/gos roster invite`,
`/gos roster groups`. An officer who has not read the CurseForge page has no way to
learn any of it exists.

This adds a `Web` feature window: publishing on/off, a one-click publish, and the three
raid-night actions, each as a button that explains itself instead of printing an error
after the fact.

Design round held 2026-08-12 (window versus hub block, window contents, and the
reload-to-publish button all signed off by the user).

## 1. What the addon can and cannot know

This bounds every line of copy in the panel, so it comes first.

`Modules/CompanionExport.lua` writes `GuildOSDB.__companion` on `PLAYER_LOGOUT`, and
nothing else. The Go companion watches that file and POSTs it. **The addon never learns
whether the companion picked it up or whether the site accepted it.** The panel may
therefore say "written", never "sent" or "connected".

The reverse direction is manual on purpose: `companion/sync.go` only ever reads
`GuildOS.lua`, and WoW reads SavedVariables at load only, so a roster cannot arrive
mid-session by any route. The officer copies the string from the site and pastes it in.
The panel makes that path one click away; it does not remove it.

**What is available today**

| Call | Gives |
|---|---|
| `BRutus.Companion:IsEnabled()` / `:SetEnabled(on)` | the publishing toggle |
| `BRutus.Companion:Build()` | `(payloadString, memberCount)` or `(nil, err)` |
| `BRutus.CompanionImport:Current()` | the loaded roster, or nil |
| `BRutus.CompanionImport:InviteAll()` | `(invited, skipped, err)` |
| `BRutus.CompanionImport:OrganizeGroups()` | `(moved, err)` |
| `BRutus:ShowImportPopup()` | the paste-a-roster popup |

A loaded roster carries `raidId`, `title`, `instance`, `startsAt` and `members`, each
member with `name`, `class`, `spec`, `slot` and `group`.

**What has to be added:** a write timestamp. `PLAYER_LOGOUT` stores the payload but not
when, so "last written" cannot be shown without it.

## 2. Goals and non-goals

**Goals**

- Every companion command reachable as a button, from a window that is visible in the hub.
- Publishing without logging out.
- A button that is disabled tells you why, in the panel, before you click.
- Someone who has never heard of the site can work out what to do from this window.

**Non-goals**

- Automating the site → game direction. It cannot be live (section 1) and is its own project.
- Delivery confirmation. It would need the companion to write back and would only surface
  a session later.
- Replacing the slash commands. They keep working exactly as they do now.
- Any change to the wire format, the companion, or the site.

## 3. The feature

Registered in `UI/Features.lua` at order 95, between Leadership (90) and Settings (100):

```lua
UI:RegisterFeature({
    id = "web", label = L["Web"], order = 95,
    icon = ICON .. "INV_Misc_Spyglass_02",
    w = 460, h = 440, minW = 380, minH = 320,
    build = function(c, win) BRutus:CreateWebPanel(c, win) end,
})
```

It gets a hub row for free, badged with the signup count while a roster is loaded.

**Not `officerOnly`.** Publishing is each player's own choice and the guild's picture on
the site gets better the more members opt in, so a rank-and-file member must be able to
find this and switch it on. The raid actions gate themselves on raid leadership instead
(section 5).

Panel lives in a new `UI/WebPanel.lua`, loaded after `UI/Layout.lua`. It is responsive
through `UI:MakeResponsive` like every other panel.

## 4. Layout

```
┌ Web ──────────────────────────────────── × ┐   ┌ Web ──────────────────────────────────── × ┐
│ PUBLICAÇÃO                                 │   │ PUBLICAÇÃO                                 │
│ ● Ligada                      [Desligar]   │   │ ○ Desligada                     [Ligar]    │
│ 58 membros vão no próximo envio            │   │ Nada sai do jogo enquanto estiver assim.   │
│ Última gravação: agora há pouco            │   │                                            │
│                                            │   ├────────────────────────────────────────────┤
│ [Enviar agora]                             │   │ RAID PLANEJADA                             │
│ Grava e recarrega a interface. O companion │   │ Nenhuma carregada.                         │
│ envia em seguida, do seu PC.               │   │ [Colar roster do site]                     │
├────────────────────────────────────────────┤   │  └ ligue a publicação primeiro             │
│ RAID PLANEJADA                     25      │   ├────────────────────────────────────────────┤
│ Karazhan · sáb 21:00 · em 2d 4h            │   │ PRIMEIRA VEZ?                              │
│                                            │   │ 1. Abra guildos.ferion.com.br   [Copiar]   │
│ [Trazer roster] [Convidar] [Grupos]        │   │ 2. Baixe o companion e cole o token        │
│                             └ entre numa   │   │ 3. Saia do jogo uma vez                    │
│                               raid primeiro│   │                                            │
└────────────────────────────────────────────┘   └────────────────────────────────────────────┘
     publishing on, roster loaded                          first run
```

Three stacked sections, each hidden when it has nothing to say:

**PUBLICAÇÃO** is always shown. On: the member count from `Companion:Build()`, the last
write time, and `[Enviar agora]`. Off: one line saying nothing leaves the game, and
nothing else.

**RAID PLANEJADA** shows the loaded roster's title, instance, start time and countdown,
with the signup count on the right. With no roster it collapses to one line plus
`[Colar roster do site]`.

**PRIMEIRA VEZ?** is shown exactly while publishing is off, and hidden while it is on.
No extra state is stored: the toggle already answers "has this person set it up".
`[Copiar]` puts the address in a pre-selected read-only edit box for Ctrl+C, since WoW
cannot open a browser and this is the idiom `ShowExportPopup` already uses.

Countdown formatting matches `UI/Dashboard.lua`'s `fmtCountdown` (`in %dd %dh`, etc.).

## 5. Button gating

The refusal reasons already exist inside `InviteAll` and `OrganizeGroups`, but only fire
after the user acts. Extracting them lets the button and the action share one definition,
so what the panel says and what the action does cannot drift:

```lua
function Import:CanInvite()    -- -> ok, reason
function Import:CanOrganize()  -- -> ok, reason
```

`InviteAll` and `OrganizeGroups` call them first and return the same reason on refusal,
so the slash commands behave exactly as they do today.

| Button | Enabled when | Reason shown when not |
|---|---|---|
| Enviar agora | publishing on **and** not in combat | "Ligue a publicação primeiro." / "Não dá para recarregar em combate." |
| Trazer roster | publishing on | "Ligue a publicação primeiro." (`Parse` refuses with the same line, so offering the popup would only waste a paste) |
| Convidar | a roster is loaded and publishing is on | "Carregue um roster primeiro." |
| Grupos | a roster is loaded, in a raid, and leader or assistant | "Entre numa raid primeiro." / "Só o líder organiza grupos." |

A disabled button is greyed and its reason is drawn under the button row, not in a
tooltip: the point is that it is readable without hunting.

**Enviar agora** calls `ReloadUI()`. `PLAYER_LOGOUT` fires on reload, which is what
writes the payload, so the reload IS the publish. There is no confirmation popup: the
microcopy under the button says it reloads and the window was opened deliberately.
`InCombatLockdown()` is a hard block, because an accidental reload mid-boss costs more
than the button saves.

## 6. Refresh

The panel recomputes on `OnShow`, and while shown on `PLAYER_REGEN_DISABLED` /
`PLAYER_REGEN_ENABLED` (the combat gate), `GROUP_ROSTER_UPDATE` (the raid gates) and a
10s ticker for the countdown. The ticker stops on hide, matching the hub.

`Companion:Build()` walks the whole guild, so it runs on refresh only, never per frame,
and its result is cached until the next refresh.

## 7. Changes outside the panel

| File | Change |
|---|---|
| `Modules/CompanionExport.lua` | store `GuildOSDB.__companionAt = time()` beside the payload write |
| `Modules/CompanionImport.lua` | add `CanInvite` / `CanOrganize`; `InviteAll` / `OrganizeGroups` call them |
| `UI/Features.lua` | register the `web` feature |
| `GuildOS.toc` | load `UI/WebPanel.lua` |
| `Locales/enUS.lua`, `Locales/ptBR.lua` | the new strings |

## 8. Testing

`CanInvite` and `CanOrganize` read only `Current()` plus WoW group state, so they run in
the existing `/gos selftest` harness with the group functions stubbed:

- `companion.can_invite_needs_roster` : no roster -> refused with the roster reason.
- `companion.can_invite_needs_publishing` : roster loaded, publishing off -> refused.
- `companion.can_organize_needs_raid` : roster loaded, not in a raid -> refused.
- `companion.can_organize_needs_lead` : in a raid without lead -> refused.
- `companion.can_organize_ok` : roster, in raid, leading -> allowed.
- `companion.actions_agree_with_predicates` : `InviteAll` / `OrganizeGroups` return the
  same reason their predicate gives, so the button text and the action cannot diverge.

Plus a headless smoke test that builds the panel and drives its layout across widths,
asserting the button enabled-state and the reason line in each scenario, in the same
shape as the roster and recipes smoke tests.

Frame dimensions are floats in the live client, so any width assertion uses a tolerance.

## 9. Risks

- **`ReloadUI` is disruptive.** Mitigated by the combat block and explicit microcopy. It
  is still the only way to publish without logging out.
- **`Build()` cost on refresh.** It already runs on every logout; running it on panel
  show and on a 10s ticker while the panel is open is bounded and cached.
- **Copy shows a URL the addon cannot open.** Accepted: every WoW addon has this
  constraint, and the pre-selected edit box is the established answer.

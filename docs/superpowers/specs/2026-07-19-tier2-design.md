# Guild OS — Tier 2 (Diferenciais fortes) — Design Spec

- **Data:** 2026-07-19
- **Status:** Autopilot (user delegated design + build: "faz todos em autopilot"). No per-feature approval gate; specs written for the record + retrospective review.
- **Branch:** `feat/tier2` (NOT to be pushed/published without explicit user go-ahead).
- **Origem:** varredura competitiva (GRM, GuildMap, ChatUtils, Axiom, GCM, GuildKit). Tier 1 (Ban/Auto-invite/Event-log) já mergeado.

## Objetivo

Quatro diferenciais de médio esforço, na ordem de dependência:
1. **Alt/Main + True Roster** (fundacional — alimenta #2 e #3).
2. **Chat enhancements**.
3. **Analytics de composição**.
4. **Recruit scanner ativo**.

## Convenções globais (todas as features)
- Cliente BCC 20506; `C_Timer`/`C_GuildInfo` via `BRutus.Compat.*`. luacheck 0/0 é o gate (`C:\Users\danie\bin\luacheck.exe . --config .luacheckrc`). Pure logic testada via `/gos selftest`. Toda string em 5 locales. Colors do `BRutus.Colors`. Rule 10 (sem lógica em callback de UI). Commits Conventional; **sem atribuição de IA**.

---

## Feature 1 — Alt/Main + "True Roster"

**Reuso (já existe):** `db.altLinks = { [altKey] = mainKey }` (Core.lua:77); `BRutus:LinkAlt/UnlinkAlt/GetLinkedChars` (Utils.lua, officer-gated + sync via `CommSystem:BroadcastAltLinks`); UI de linkar por-membro no `MemberDetail`.

**Novo (o valor do #1):**
- **API agregadora** (pura, em Utils.lua ou um `Modules/AltRoster.lua`):
  - `BRutus:GetMain(key) -> key` — `altLinks[key] or key`.
  - `BRutus:IsAlt(key) -> bool`.
  - `BRutus:GetAltTag(key) -> string|nil` — `nil` se sem link; senão "alt of <Main>" (curto). Consumido por #2 e pelo roster.
  - `BRutus:GetTrueRoster() -> { groups = { {main=key, mainName, alts={key…}, online=bool, level, class} }, uniqueCount, totalChars }` — cruza `altLinks` com o guild roster (`GetGuildRosterInfo`, nil-check); mains que não estão no roster são ignorados; alts fora do roster não contam char.
- **True Roster view:** toggle na aba Roster ("Group alts" / "True Roster") que colapsa alts sob o main (main com badge "+N alts", clicável pra expandir) + um **KPI card** "N players · M chars".
- **Decisão:** mantém officer-maintained (não cria member-write). **Adia:** alt-group rank sync (lockdown Blizzard) → follow-up.

**Sync:** nenhum novo (altLinks já sincroniza). **Esforço:** M (a maior parte é a view + API).

---

## Feature 2 — Chat enhancements

**Novo `Modules/ChatTweaks.lua`** + toggles no Settings. Usa `ChatFrame_AddMessageEventFilter` (o hook seguro/reversível pra transformar linhas de chat).
- **Alvo:** `CHAT_MSG_GUILD` e `CHAT_MSG_OFFICER` (config). Não toca em Trade/say pra não poluir.
- **Anotações no nome do autor** (cada uma togglável em `db.chatTweaks`):
  - **Ícone de classe** (via `CLASS_ICON_TCOORDS` + `|T…:0|t`), cor de classe já vem do Blizzard.
  - **Ícone de raça** (atlas/texture por raça+gênero, best-effort; se indisponível, pula).
  - **Nível** `[70]` — lookup no guild roster por nome (cache leve; nil-safe).
  - **Tag alt/main** (`*alt`) via `BRutus:GetAltTag` (feature #1) — só se #1 tiver link.
- **Config:** `db.chatTweaks = { guild=true, officer=true, classIcon=true, raceIcon=false, level=true, altTag=true }` + toggles no painel Settings (bloco "CHAT").
- **1-click invite:** já existe (`RecruitmentSystem:HookChatInvite`); não reimplementar.
- **Cuidado:** o filter roda por linha de chat — manter leve (sem loops de roster por mensagem; usar um cache nome→{class,level,race} atualizado em `GUILD_ROSTER_UPDATE`, não por mensagem).

**Esforço:** S-M. **Pure logic testável:** a função que monta o prefixo dado {class,level,race,altTag,cfg}.

---

## Feature 3 — Analytics de composição

**Novo `Modules/GuildAnalytics.lua`** (agregação pura) + `UI/AnalyticsPanel.lua` (uma sub-aba, provavelmente em Roster ou uma aba "Analytics").
- **Agregação pura** sobre o guild roster (+ `db.members` pra dados enriquecidos quando houver): distribuições por **classe, faixa de nível, rank, raça, zona**. `BRutus.GuildAnalytics:Distribution(dimension, onlineOnly) -> { {label, count, pct, color?} } , total`.
- **UI:** barras horizontais simples (uma StatusBar/textura por linha, largura ∝ pct), rotuladas, com count + %, cor de classe quando `dimension=="class"`. Toggle **online/offline**. Seletor de dimensão (5 botões/dropdown). Sem lib externa.
- **Decisão:** dataviz mínimo e legível (segue o padrão de UI do addon; barras com label à esquerda, valor à direita — evitar poluição). Ordena desc por count.

**Esforço:** M. **Pure logic testável:** `Distribution` (contagens/pct).

---

## Feature 4 — Recruit scanner ativo (o moat, mais frágil)

**Novo `Modules/RecruitScanner.lua` + `UI/RecruitScannerPanel.lua`.** Sourcing ativo de unguilded.
- **Scan:** `/who` por filtros (classe/raça/nível-range). Mesma infra frágil do auto-invite (F4): `SetWhoToUI(1)` + `SendWho(query)` + `WHO_LIST_UPDATE` + `C_FriendList.GetNumWhoResults/GetWhoInfo`, **fila (um por vez) + timeout + fail-safe** (sem resultado → lista vazia, nunca crash). Filtra **guilded fora** (só quem não tem guild) e **banidos** (`BanList:IsBanned`).
- **Resultados:** grid (nome, nível, classe, zona) com seleção múltipla.
- **Mass-whisper:** template com tokens (`[player]`, `[class]`, `[level]`) → envia `/w` aos selecionados **com throttle** (respeitar spam; e `SendChatMessage` a whisper é permitido sem clique de hardware). Cooldown por nome pra não re-sussurrar.
- **Reply inbox:** hook `CHAT_MSG_WHISPER`; se o autor está na lista de contatados, captura a resposta num inbox (nome + msg + hora), togglável. Ajuda a triar quem respondeu.
- **Decisões:** whisper-templates com no máx N destinatários por lote (anti-spam); **desligado por padrão**; officer-gated. **Risco alto in-game** (API `/who` no 2.5) — fail-safe em tudo.

**Esforço:** L. **Pure logic testável:** expansão de token do template; filtro de candidato (unguilded + não-banido + passa filtros).

---

## Sequenciamento
`#1 Alt/Main → #2 Chat → #3 Analytics → #4 Scanner`. Cada uma: plano próprio + build SDD (subagentes com review/fix por task) + luacheck 0/0. Branch `feat/tier2`, **não pushar** sem OK explícito (push republica no CurseForge).

## Riscos / verificação humana (sem cliente WoW aqui)
- Tudo precisa de verificação in-game (chat filter, /who, UI, tags).
- **#4 `/who`** é o maior risco (mesmo do F4): fail-safe = lista vazia / sem convite, nunca crash.
- Chat filter: manter leve (cache, sem roster-loop por mensagem).
- Cada domínio novo com cap/prune onde houver histórico (inbox do #4).

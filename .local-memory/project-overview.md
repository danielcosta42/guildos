# BRutus — Project Overview

_Last updated: 2026-04-26_

---

## Objetivo

BRutus é um addon de gerenciamento de guild para World of Warcraft TBC Anniversary Edition.
Substitui o frame padrão de guild do Blizzard por um hub moderno que coleta, sincroniza e exibe dados de membros automaticamente, sem necessidade de inspeção manual.

---

## Público-alvo

- **Líderes e oficiais de guild** no WoW TBC Anniversary
- **Raid leaders** que precisam de visibilidade sobre atunamentos, consumíveis e presença
- **Membros** que querem acompanhar suas próprias progressões e wishlists

---

## Principais Funcionalidades

| Funcionalidade | Módulo | Acesso |
|---|---|---|
| Roster de guild com colunas ordenáveis | `DataCollector`, `UI/RosterFrame` | Todos |
| Painel de detalhe do membro | `UI/MemberDetail` | Todos |
| Rastreamento de atunamentos | `AttunementTracker` | Todos |
| Sincronização automática de dados | `CommSystem` | Todos |
| TMB Wishlist (That's My BiS) | `WishlistSystem`, `UI/FeaturePanels` | Todos |
| Browser de receitas da guild | `RecipeTracker`, `UI/RecipesPanel` | Todos |
| Rastreamento de raids e presença | `RaidTracker`, `UI/FeaturePanels` | Todos |
| Verificação de consumíveis | `ConsumableChecker` | Oficiais (em raid) |
| Histórico de loot | `LootTracker`, `UI/FeaturePanels` | Todos |
| Master Looter assistido | `LootMaster` | ML em raid |
| Notas de oficial | `OfficerNotes`, `UI/MemberDetail` | Oficiais |
| Trial tracker | `TrialTracker`, `UI/FeaturePanels` | Oficiais |
| Sistema de recrutamento | `RecruitmentSystem`, `UI/FeaturePanels` | Oficiais |
| HUD de cooldowns de raid | `UI/RaidHUD` | Líderes em raid |
| Verificação de spec/talentos | `SpecChecker` | Todos |

---

## Limitações do WoW TBC Anniversary (Interface 20505)

| Limitação | Impacto |
|---|---|
| `GetLootMethod()` retorna nil | `LootMaster` usa fallback de 4 etapas |
| `SendChatMessage` requer hardware event para canais públicos | Recrutamento usa popup clicável |
| Addon messages: limite de 255 bytes | `CommSystem` chunking obrigatório |
| Lua 5.1: sem `goto`, sem bitwise, sem `//` | Código usa `math.floor`, `bit.band` não disponível |
| `C_ChatInfo`, `C_QuestLog`, `C_Timer` — podem não existir | Todos passam por `BRutus.Compat.*` |
| `BackdropTemplate` obrigatório no TBC | Todos os frames usam o mixin |
| `GetGuildRosterInfo` 1-indexed, pode retornar nil | Sempre com nil-check e loop de 1 a N |
| `PLAYER_ENTERING_WORLD` dispara em toda mudança de zona | Guarda com `isInitialLogin or isReloadingUi` |

---

## Escopo Atual (v1.0.0)

- ✅ Roster com coleta automática de dados
- ✅ Sincronização guild (LibSerialize + LibDeflate + ChatThrottleLib)
- ✅ Atunamentos com propagação conta-wide
- ✅ Wishlists pessoais + prioridades de loot
- ✅ Rastreamento de raids + presença com pontuação
- ✅ Master Looter com rolls restritos e trade queue
- ✅ Receitas da guild com busca
- ✅ Notas de oficial sincronizadas
- ✅ Trial tracker
- ✅ Sistema de recrutamento com popup
- ✅ HUD de cooldowns de raid
- ✅ Verificação de consumíveis
- ✅ Spec/talent viewer

---

## Escopo Futuro (não implementado)

- [ ] EventBus interno para desacoplar módulos
- [ ] StorageService / Repository pattern (BRutus.db protegido)
- [ ] SyncService com versionamento de protocolo, ACK/NACK, retry
- [ ] Slash commands separados do Core.lua
- [ ] Split de UI/Helpers.lua em Theme + Core + Panels
- [ ] Comandos de debug: `/brutus sync status`, `/brutus storage stats`
- [ ] Soft delete / tombstone para entidades sincronizadas
- [ ] Conflito resolution documentado e automatizado
- [ ] Limites configuráveis de crescimento do SavedVariables

---

## Stack Técnico

| Componente | Tecnologia |
|---|---|
| Linguagem | Lua 5.1 |
| Serialização | LibSerialize |
| Compressão | LibDeflate |
| Throttle de mensagens | ChatThrottleLib |
| DI/Lib loader | LibStub |
| UI Framework | WoW Native Frames + BackdropTemplate |
| Persistência | SavedVariables (`BRutusDB`) |
| Lint | luacheck (`C:\Users\danie\bin\luacheck.exe`) |
| CI/CD | GitHub Actions + BigWigsMods packager |
| Publish | CurseForge ID 1549177 (BCC client) |

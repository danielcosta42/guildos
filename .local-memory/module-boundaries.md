# GuildOS — Module Boundaries

_Last updated: 2026-04-26_

---

## Regra Geral

Cada módulo tem uma **responsabilidade única** e não deve cruzar para a responsabilidade de outro.

```
Módulo A pode CHAMAR métodos de Módulo B
Módulo A NÃO deve escrever diretamente no "db domain" de Módulo B
Módulo A NÃO deve conhecer o formato de serialização de Módulo B
```

---

## Mapa de Responsabilidades

| Módulo | Dono de | Pode chamar | NÃO deve |
|---|---|---|---|
| `Core.lua` | Namespace GuildOS, Logger, Compat, State, Config, lifecycle | tudo (é o bootstrap) | conter business logic de features |
| `DataCollector` | Coleta e armazena dados do player local | `AttunementTracker` | UI, comm internals |
| `AttunementTracker` | Quest attunements + propagação via altLinks | `GuildOS.Compat` | UI, comm |
| `CommSystem` | Encode/send/receive/route mensagens | `DataCollector`, todos os handlers | business logic dos handlers |
| `RecruitmentSystem` | Auto-recruit + welcome | `CommSystem:SendMessage` | UI direta, comm internals |
| `WishlistSystem` | Wishlists + prios de loot | `CommSystem:SendMessage` | UI, comm internals |
| `RaidTracker` | Raid sessions, snapshots, attendance, score | `ConsumableChecker` | UI |
| `LootTracker` | Histórico de loot | nada | UI, comm |
| `LootMaster` | ML loot distribution | `LootTracker`, `WishlistSystem`, `CommSystem` | dados de roster |
| `RecipeTracker` | Recipe scan + sync | `CommSystem:SendMessage` | UI |
| `OfficerNotes` | Notas + sync | `CommSystem:SendMessage` | UI |
| `TrialTracker` | Trial lifecycle + sync | `CommSystem:SendMessage`, `DataCollector` | UI |
| `ConsumableChecker` | Detectar buffs de consumíveis | nada | UI, comm |
| `SpecChecker` | Detectar spec/talentos | nada | UI, comm |
| `UI/Helpers.lua` | Widgets + tema | nada externo | data logic, comms |
| `UI/RosterFrame.lua` | Roster window + tabs | todos módulos (leitura), `GuildOS:GetSetting/SetSetting` | data writes, business logic |
| `UI/MemberDetail.lua` | Painel de detalhe | módulos (leitura) | data writes |
| `UI/FeaturePanels.lua` | Feature panels | módulos (leitura), `GuildOS:GetSetting` | data writes |
| `UI/RecipesPanel.lua` | Browser de receitas | `RecipeTracker` | data writes |
| `UI/RaidHUD.lua` | CD overlay + consumable popup | `GuildOS.State.raidCD`, `ConsumableChecker` | data writes |

---

## Violações Atuais Mapeadas

### UI escrevendo GuildOS.db diretamente

| Arquivo | Linha / Padrão | Status |
|---|---|---|
| `UI/RosterFrame.lua` | `GuildOS.db.settings.*` | ✅ Corrigido — usa GetSetting/SetSetting |
| `UI/FeaturePanels.lua` | `GuildOS.db.raidTracker.*` | ⚠️ leitura direta OK, mas algumas escritas problemáticas |
| `UI/FeaturePanels.lua` | `GuildOS.db.recruitment.*` | ⚠️ Campos de settings escritos inline em callbacks |
| `UI/MemberDetail.lua` | `GuildOS.db.altLinks` | ⚠️ Escreve altLinks diretamente em vez de chamar GuildOS:LinkAlt |

### Módulos enviando comm com magic strings

| Arquivo | Magic string | Status |
|---|---|---|
| `WishlistSystem.lua` | `"WL:"`, `"LP:"` | ⚠️ Não em MSG_TYPES |
| `RecipeTracker.lua` | `"RC:"` | ⚠️ Não em MSG_TYPES |
| `OfficerNotes.lua` | `"ON:"` | ⚠️ Não em MSG_TYPES |
| `TrialTracker.lua` | `"TR:"` | ⚠️ Não em MSG_TYPES |

### LootMaster misturando responsabilidades

| Responsabilidade | Deveria estar em |
|---|---|
| Roll logic + parsing | `LootMaster` (OK) |
| Trade queue | `LootMaster` (OK) |
| UI de roll frame | `UI/FeaturePanels.lua` ou arquivo próprio |
| UI de loot frame | `UI/FeaturePanels.lua` ou arquivo próprio |
| Comm de AWARD | `CommSystem` via MSG_TYPES |

---

## Dependências entre Módulos (grafo atual)

```
Core ────────────────────────────────────────► todos os módulos
                                                (cria o namespace)
CommSystem ──────────────────────────────────► DataCollector (HandleBroadcast)
                                              ► WishlistSystem (HandleWishlistBroadcast)
                                              ► RecipeTracker (HandleIncoming)
                                              ► OfficerNotes (HandleIncoming)
                                              ► TrialTracker (HandleIncoming)
                                              ► RaidTracker (HandleIncoming)

DataCollector ───────────────────────────────► (sem deps de outros módulos GuildOS)
AttunementTracker ───────────────────────────► GuildOS.Compat
RaidTracker ─────────────────────────────────► ConsumableChecker
LootMaster ──────────────────────────────────► LootTracker, WishlistSystem, CommSystem
WishlistSystem ──────────────────────────────► CommSystem
RecipeTracker ───────────────────────────────► CommSystem
OfficerNotes ────────────────────────────────► CommSystem
TrialTracker ────────────────────────────────► CommSystem, DataCollector
RecruitmentSystem ───────────────────────────► CommSystem

UI/RosterFrame ──────────────────────────────► DataCollector, AttunementTracker,
                                               RaidTracker, GuildOS (GetSetting)
UI/FeaturePanels ────────────────────────────► RaidTracker, LootTracker, LootMaster,
                                               WishlistSystem, TrialTracker,
                                               RecruitmentSystem, ConsumableChecker
UI/MemberDetail ─────────────────────────────► DataCollector, AttunementTracker,
                                               OfficerNotes, SpecChecker
UI/RecipesPanel ─────────────────────────────► RecipeTracker
UI/RaidHUD ──────────────────────────────────► ConsumableChecker, GuildOS.State.raidCD
```

---

## Regras de Boundaries a Seguir

1. **UI → Módulo**: UI chama métodos públicos dos módulos. Nunca escreve em `GuildOS.db.*` diretamente.
2. **Módulo → CommSystem**: módulos chamam `CommSystem:SendMessage(type, data)`. Nunca `ChatThrottleLib` diretamente.
3. **CommSystem → Módulos**: CommSystem chama handlers registrados. Não conhece business logic.
4. **Módulo → State**: cada módulo lê/escreve apenas seu próprio sub-table em `GuildOS.State.*`.
5. **Módulo → DB**: cada módulo acessa apenas seu próprio sub-domínio em `GuildOS.db.*`.
6. **Cross-domain**: módulo A não deve escrever no domínio de módulo B. Se necessário, chama um método público de B.

---

## Interfaces Públicas por Módulo

Para que a UI e outros módulos possam interagir sem conhecer internals:

| Módulo | Métodos públicos (API estável) |
|---|---|
| `DataCollector` | `:CollectMyData()`, `:GetBroadcastData()`, `:StoreReceivedData(key, data)` |
| `AttunementTracker` | `:ScanAttunements()`, `:GetEffectiveAttunements(key)`, `:GetAttunementSummary(key)` |
| `RaidTracker` | `:GetRecentSessions(limit)`, `:GetAttendancePercent(key, group)`, `:GetSnapshotScore(sd, key)`, `:DeleteSession(id)` |
| `LootTracker` | `:GetHistory(limit)`, `:RecordMLAward(entry)` |
| `WishlistSystem` | `:GetItemInterest(itemId)`, `:AddToWishlist(itemId, link, isOffspec)`, `:RemoveFromWishlist(itemId)` |
| `RecipeTracker` | `:Search(query, filter)`, `:BuildRecipeIndex()` |
| `OfficerNotes` | `:GetNotes(key)`, `:AddNote(key, text)`, `:DeleteNote(key, idx)` |
| `TrialTracker` | `:GetActiveTrials()`, `:AddTrial(key, sponsor)`, `:UpdateStatus(key, status)` |
| `ConsumableChecker` | `:CheckRaid()`, `:GetLastResults()`, `:GetMissingCount(results)` |
| `SpecChecker` | `:GetSpecLabel(key)`, `:CollectOwnSpec()` |
| `RecruitmentSystem` | `:StartAutoRecruit()`, `:StopAutoRecruit()`, `:Toggle()` |

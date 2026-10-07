# GuildOS — Current Architecture

_Last updated: 2026-04-26_

---

## Estrutura de Pastas

```
GuildOS/
├── GuildOS.toc                  ← load order + SavedVariables
├── Core.lua                    ← GLOBAL GuildOS, DB defaults, Logger, Compat, State, Config,
│                                  lifecycle events, slash commands, utility helpers
├── CommSystem.lua              ← sync: encode/compress/chunk/send/receive/route
├── DataCollector.lua           ← coleta gear/profs/stats/spec do player local
├── AttunementTracker.lua       ← atunamentos via quests + propagação conta-wide
├── RaidTracker.lua             ← raid sessions, snapshots, attendance, scores
├── LootTracker.lua             ← histórico de loot
├── LootMaster.lua              ← ML UI + lógica de rolls + trade queue
├── WishlistSystem.lua          ← wishlists + prioridades de loot
├── RecipeTracker.lua           ← scan de receitas + busca guild-wide
├── OfficerNotes.lua            ← notas de oficial + sync
├── TrialTracker.lua            ← lifecycle de trials
├── RecruitmentSystem.lua       ← auto-recruit + welcome
├── ConsumableChecker.lua       ← verificação de buffs
├── SpecChecker.lua             ← detecção de spec/talentos
├── Libs/
│   ├── LibStub.lua
│   ├── CallbackHandler-1.0.lua
│   ├── LibSerialize.lua
│   ├── LibDeflate.lua
│   └── ChatThrottleLib.lua
└── UI/
    ├── Helpers.lua             ← TODOS os widgets + tema (C table, factory functions)
    ├── RosterFrame.lua         ← janela principal + tabs
    ├── MemberDetail.lua        ← painel de detalhe do membro
    ├── FeaturePanels.lua       ← raids, loot, trials, settings, wishlist, recrutamento
    ├── RecipesPanel.lua        ← browser de receitas
    └── RaidHUD.lua             ← CD overlay + popup de consumíveis
```

---

## Camadas Atuais (estado real, não idealizado)

```
┌─────────────────────────────────────────────────────────────────────┐
│  UI (Helpers, RosterFrame, FeaturePanels, MemberDetail,             │
│       RecipesPanel, RaidHUD)                                        │
│  ⚠ Acessa GuildOS.db diretamente em vários pontos                   │
│  ⚠ Contém lógica de negócio inline em SetScript callbacks          │
├─────────────────────────────────────────────────────────────────────┤
│  Módulos de Domínio                                                 │
│  RaidTracker | LootTracker | LootMaster | WishlistSystem            │
│  RecipeTracker | OfficerNotes | TrialTracker | RecruitmentSystem    │
│  DataCollector | AttunementTracker | ConsumableChecker | SpecChecker│
│  ⚠ Cada módulo acessa GuildOS.db diretamente                        │
│  ⚠ Alguns módulos enviam comm diretamente (não via CommSystem)      │
├─────────────────────────────────────────────────────────────────────┤
│  CommSystem (sync parcialmente centralizado)                        │
│  ⚠ Tipos de mensagem soltos: "WL", "LP", "ON", "RC", "TR"          │
│  ⚠ Sem versionamento de protocolo                                  │
│  ⚠ Sem ACK/NACK/retry                                              │
├─────────────────────────────────────────────────────────────────────┤
│  Core.lua (namespace, Logger, Compat, State, Config, lifecycle)     │
│  ⚠ Também contém slash commands e helpers utilitários              │
│  ⚠ Muito grande — mistura 6 responsabilidades                      │
├─────────────────────────────────────────────────────────────────────┤
│  GuildOSDB SavedVariables (acesso direto sem camada de proteção)     │
│  ⚠ Qualquer módulo pode escrever qualquer campo                    │
│  ⚠ Sem schema versioning centralizado                              │
│  ⚠ Sem limites de crescimento                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Responsabilidades de Cada Arquivo

| Arquivo | Responsabilidade real hoje | Problemas |
|---|---|---|
| `Core.lua` | Namespace, DB defaults, Logger, Compat, State, Config, lifecycle events, slash commands, 20+ helpers | Muito grande, 6+ responsabilidades |
| `CommSystem.lua` | Encode/chunk/send/receive/route | Tipos de mensagem magic strings espalhados, sem protocolo versionado |
| `DataCollector.lua` | Coleta dados do player local | OK, bem encapsulado |
| `AttunementTracker.lua` | Atunamentos via C_QuestLog | OK — IsQuestComplete delegado ao Compat |
| `RaidTracker.lua` | Sessions, snapshots, attendance, score | Acesso direto a GuildOS.db.raidTracker |
| `LootTracker.lua` | Histórico de loot | Pequeno, OK |
| `LootMaster.lua` | ML loot: rolls, trade, announce | Grande (700+ linhas), mistura UI + lógica |
| `WishlistSystem.lua` | Wishlists + prios | Envia "WL" e "LP" diretamente (não via MSG_TYPES) |
| `RecipeTracker.lua` | Scan + busca de receitas | Envia "RC" diretamente |
| `OfficerNotes.lua` | Notas + sync | Envia "ON" diretamente |
| `TrialTracker.lua` | Trial lifecycle + sync | Envia "TR" diretamente |
| `RecruitmentSystem.lua` | Recrutamento + welcome | OK após refactor |
| `ConsumableChecker.lua` | Detecção de buffs | OK, bem isolado |
| `SpecChecker.lua` | Spec/talentos | OK |
| `UI/Helpers.lua` | TODOS widgets + tema + scroll bars | Mistura tema, factory, helpers |
| `UI/RosterFrame.lua` | Roster window + tabs | Usa GetSetting/SetSetting (✅ refatorado) |
| `UI/MemberDetail.lua` | Painel de detalhe | Acessa GuildOS.db diretamente |
| `UI/FeaturePanels.lua` | Feature panels | Acessa GuildOS.db diretamente em vários pontos |
| `UI/RecipesPanel.lua` | Browser de receitas | OK, usa módulos |
| `UI/RaidHUD.lua` | CD overlay + consumable popup | Usa GuildOS.State.raidCD (✅ refatorado) |

---

## Load Order (.toc)

| # | Arquivo | Depende de |
|---|---|---|
| 1–5 | `Libs/*` | nada |
| 6 | `Core.lua` | Libs — cria global GuildOS |
| 7 | `DataCollector.lua` | GuildOS |
| 8 | `AttunementTracker.lua` | GuildOS, Compat |
| 9 | `CommSystem.lua` | GuildOS, State.comm |
| 10 | `RecruitmentSystem.lua` | GuildOS, CommSystem, State.recruitment |
| 11 | `WishlistSystem.lua` | GuildOS, CommSystem |
| 12 | `RaidTracker.lua` | GuildOS |
| 13 | `LootTracker.lua` | GuildOS |
| 14 | `LootMaster.lua` | GuildOS, LootTracker |
| 15 | `RecipeTracker.lua` | GuildOS, CommSystem |
| 16 | `OfficerNotes.lua` | GuildOS, CommSystem |
| 17 | `TrialTracker.lua` | GuildOS, CommSystem |
| 18 | `ConsumableChecker.lua` | GuildOS |
| 19 | `SpecChecker.lua` | GuildOS |
| 20 | `UI/Helpers.lua` | GuildOS |
| 21–25 | `UI/*.lua` | GuildOS.UI, módulos de domínio |

---

## Problemas Arquiteturais Identificados

### 🔴 Crítico
1. **GuildOS.db acesso não protegido** — qualquer módulo e UI pode escrever qualquer campo sem validação
2. **Magic strings de sync** — "WL", "LP", "ON", "RC", "TR" espalhados, não registrados em MSG_TYPES
3. **Sem versionamento de protocolo de sync** — mensagens antigas podem sobrescrever dados novos
4. **Core.lua tem 6+ responsabilidades** — difícil de manter e testar

### 🟡 Importante
5. **UI acessa GuildOS.db diretamente** — em MemberDetail, FeaturePanels (parcialmente)
6. **LootMaster mistura UI + lógica** — 700+ linhas, difícil de testar
7. **Sem camada de Repository** — lógica de persistência espalhada
8. **Sem EventBus interno** — módulos chamam UI diretamente ou dependem de polling

### 🟢 Menor
9. **UI/Helpers.lua mistura responsabilidades** — tema + factory + helpers
10. **Sem limites no SavedVariables** — histórico de loot, awards, notas podem crescer infinitamente
11. **Timers/tickers sem cancelamento garantido** — risk de duplicatas em reload
12. **Slash commands em Core.lua** — deveria estar em Commands.lua separado

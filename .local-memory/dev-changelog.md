# GuildOS — Dev Changelog (Local)

_Este arquivo registra o progresso de desenvolvimento local — não vai para o git._
_Para o changelog público, ver `CHANGELOG.md`._

---

## 2026-04-26 — Fase 1: Documentação Arquitetural Completa

### Resumo
Sessão dedicada à análise completa da codebase antes de qualquer refatoração.
16 arquivos de documentação criados em `.local-memory/`.
2 arquivos de documentação criados em `.memory/`.

### Arquivos Criados

**`.local-memory/` (análise e planejamento):**
- `project-overview.md` — Objetivo do addon, funcionalidades, stack técnico
- `current-architecture.md` — Estado atual, problemas arquiteturais mapeados
- `target-architecture.md` — Arquitetura alvo 8 camadas, estrutura de pastas futura
- `dataflows.md` — 9 fluxos de dados documentados com diagramas ASCII
- `sync-architecture.md` — Estado atual do CommSystem, plano de migração para SyncService
- `sync-protocol.md` — Wire format v1 e v2, validação de envelope, chunking, deduplicação
- `storage-architecture.md` — Mapa de acessos a GuildOS.db, schema atual e alvo, Repositories
- `memory-management.md` — Distinção Lua memory vs SavedVars, riscos de timers e frames
- `module-boundaries.md` — Responsabilidades por módulo, violações atuais, grafo de dependências
- `ui-architecture.md` — Hierarquia de frames, Helpers.lua C table, padrões visuais
- `event-system.md` — Inventário de WoW events por módulo, EventBus alvo
- `coding-standards.md` — 14 regras de engenharia, estilo, anti-patterns
- `refactor-plan.md` — Plano de 8 fases incremental
- `testing-notes.md` — Cenários de teste manuais, comandos slash de debug
- `decisions.md` — 12 ADRs (9 existentes + 3 novos desta sessão)
- `dev-changelog.md` — Este arquivo

**`.memory/` (mirror dos arquivos internos do Copilot):**
- `README.md` — Índice e workflow do agente
- `architecture.md` — Cópia de `/memories/repo/architecture.md`

### Problemas Arquiteturais Identificados

**🔴 Críticos:**
1. `GuildOS.db` acessado diretamente por todos os módulos (sem Storage layer)
2. Magic strings de sync ("WL", "LP", "ON", "RC", "TR") não em `MSG_TYPES` — protocolo não auditável
3. Sem versionamento no envelope de sync — risco de corrupção de dados em atualizações
4. `Core.lua` tem 6+ responsabilidades — namespace, DB defaults, lifecycle, utils, State, Compat

**🟡 Importantes:**
5. `CommSystem:Initialize()` usa `C_Timer.NewTicker` direto (viola ADR-0003/Compat)
6. `UI/MemberDetail.lua` e `UI/FeaturePanels.lua` escrevem `GuildOS.db` diretamente
7. `LootMaster.lua` mistura UI + lógica de negócio (~700 linhas)
8. Sem Repository layer — lógica de persistência espalhada
9. Sem EventBus interno — UI não pode reagir a eventos sem polling ou acoplamento direto
10. `CommSystem.State.comm.pendingMessages` não tem timeout de limpeza garantido para todas as situações

**🟢 Menores:**
11. `UI/Helpers.lua` mistura tema (cores) e factory functions
12. `welcomedRecently` (RecruitmentSystem) cresce sem limpeza de sessão antiga
13. `lootMaster.awardHistory` sem limite de tamanho

### Status do Luacheck
```
C:\Users\danie\bin\luacheck.exe . --config .luacheckrc
→ 0 warnings / 0 errors
```

### Próximos Passos
Ver `refactor-plan.md` para o plano de 8 fases.
**Fase 2** é a próxima: StorageService + Repositories, migrar `GuildOS.db` para acesso controlado.

---

## (Template para próximas entradas)

## YYYY-MM-DD — Título

### Resumo
Descrição em 2-3 linhas do que foi feito.

### Mudanças
- arquivo.lua: descrição da mudança

---

## 2025-01-27 — Fase 1 Refatoração: Config.lua Central

### Resumo
Criação de `Config.lua` com todos os constants centralizados em `GuildOS.Config.*`.
Substituição de magic numbers em `CommSystem.lua` e `Core.lua`.
Fix de dois bugs: `C_Timer` usado diretamente em CommSystem (deve usar Compat).

### Arquivos Criados
- `Config.lua` — fonte única de truth para todas as constants do addon

### Arquivos Modificados
- `GuildOS.toc` — inserção de `Config.lua` após `Core.lua`
- `CommSystem.lua` — CHUNK_SIZE e THROTTLE_INTERVAL referenciam GuildOS.Config; C_Timer → Compat
- `Core.lua` — STALE_THRESHOLD local removido; referencia GuildOS.Config.LIMITS.STALE_PROFESSION_THRESHOLD

### Constants Centralizadas
- Identidade: ADDON_NAME, VERSION, COMM_VERSION, PREFIX, SAVED_VARIABLES
- Comunicação: CHUNK_SIZE(230), BROADCAST_THROTTLE(5), SYNC_TICKER_INTERVAL(300), INIT_REQUEST_DELAY(8), CHUNK_DELAY(0.1), CHUNK_TIMEOUT(30)
- MSG_TYPES: todos os 16 tipos (11 canônicos + 5 legacy WL/LP/ON/RC/TR)
- DOMAINS: 10 domínios de sync
- EVENTS: 11 nomes de EventBus (para Fase 4)
- LIMITS: LOOT_HISTORY_MAX, OFFICER_NOTES_MAX, STALE_PROFESSION_THRESHOLD, etc.
- DB_SCHEMA_VERSION: 2

### Bug Fixes
- CommSystem.Initialize(): `C_Timer.NewTicker(300, ...)` → `GuildOS.Compat.NewTicker(Config.SYNC_TICKER_INTERVAL, ...)`
- CommSystem.Initialize(): `C_Timer.After(5/10, ...)` → `GuildOS.Compat.After(Config.OFFICER_SYNC_DELAY_1/2, ...)`
- CommSystem.Initialize(): `C_Timer.After(8, ...)` → `GuildOS.Compat.After(Config.INIT_REQUEST_DELAY, ...)`
- CommSystem.SendMessage(): `C_Timer.After((i-1)*0.1, ...)` → `GuildOS.Compat.After(...*Config.CHUNK_DELAY, ...)`
- CommSystem.OnMessageReceived(): `C_Timer.After(30, ...)` → `GuildOS.Compat.After(Config.CHUNK_TIMEOUT, ...)`

### Status do Luacheck
```
→ 0 warnings / 0 errors in 21 files
```

### Próximos Passos
**Fase 2**: Storage.lua — camada de acesso controlado ao GuildOS.db
- outro.lua: descrição da mudança

### Testes
- [ ] luacheck: 0 warnings / 0 errors
- [ ] /reload sem erros
- [ ] Feature X funciona corretamente

### Notas
Observações técnicas, gotchas, decisões inline.

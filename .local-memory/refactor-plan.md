# GuildOS — Refactor Plan

_Last updated: 2026-04-26_
_Status: Fase 1 — Análise e Documentação COMPLETA. Fase 2 ainda não iniciada._

---

## Princípios da Refatoração

1. **Incremental** — o addon funciona 100% após cada fase
2. **Backward compatible** — nunca quebrar dados de SavedVariables existentes
3. **Sem novas features** — refatorar é reorganizar, não adicionar
4. **Testar após cada fase** — `/reload` + `/gos` deve funcionar sem erros Lua

---

## Fase 1 — Análise e Documentação ✅ COMPLETA

**Objetivo**: Entender o estado atual antes de alterar qualquer coisa.

### Entregáveis (todos criados):
- [x] `.local-memory/project-overview.md`
- [x] `.local-memory/current-architecture.md`
- [x] `.local-memory/target-architecture.md`
- [x] `.local-memory/dataflows.md`
- [x] `.local-memory/sync-architecture.md`
- [x] `.local-memory/sync-protocol.md`
- [x] `.local-memory/storage-architecture.md`
- [x] `.local-memory/memory-management.md`
- [x] `.local-memory/module-boundaries.md`
- [x] `.local-memory/ui-architecture.md`
- [x] `.local-memory/event-system.md`
- [x] `.local-memory/coding-standards.md`
- [x] `.local-memory/refactor-plan.md`
- [x] `.local-memory/testing-notes.md`
- [x] `.local-memory/decisions.md`
- [x] `.local-memory/dev-changelog.md`
- [x] `.gitignore` atualizado

### Riscos mapeados:
- ~~GuildOS.db sem proteção~~
- ~~Magic strings de sync~~
- ~~UI escrevendo db diretamente~~
- ~~Timers sem referência para Cancel~~

---

## Fase 2 — StorageService + Repositories 🔲 PENDENTE

**Objetivo**: Proteger `GuildOS.db` com uma camada de acesso controlado.

### Pré-requisitos:
- Fase 1 completa ✅

### Passos:
1. Criar `Storage/Storage.lua` com API básica: `Get`, `Set`, `GetAll`, `Delete`, `GetSetting`, `SetSetting`
2. Adicionar ao `.toc` após `Core.lua`, antes dos módulos de domínio
3. Mover `GuildOS:GetSetting` / `GuildOS:SetSetting` de `Core.lua` para delegarem ao Storage
4. Criar `Repository/MemberRepository.lua` — primeiro repository
5. Migrar `DataCollector` para usar `MemberRepository` em vez de `GuildOS.db.members` direto
6. Verificar luacheck: 0 warnings
7. Testar `/reload` + roster exibe membros corretamente
8. Repetir para outros repositories: Raid, Loot, Wishlist...

### Arquivos impactados:
- `Core.lua` (delegar GetSetting/SetSetting)
- `DataCollector.lua`
- `Storage/Storage.lua` (novo)
- `Repository/MemberRepository.lua` (novo)
- `GuildOS.toc` (adicionar novos arquivos)

### Critério de sucesso:
- `GuildOS.db.members` não é mais acessado diretamente por nenhum módulo de feature
- Luacheck: 0 warnings
- Addon funciona identicamente ao antes

---

## Fase 3 — SyncService (ao lado do CommSystem) 🔲 PENDENTE

**Objetivo**: Criar SyncService com protocolo versionado, sem quebrar o CommSystem.

### Passos:
1. Criar `Sync/SyncService.lua`
2. Registrar o MESMO prefix (`"GuildOS"`) — aceitar AMBOS os formatos (v1 e v2)
3. Implementar `Publish`, `Request`, `RegisterHandler`
4. Implementar envelope v2 (sem ACK ainda)
5. Implementar deduplicação por messageId
6. Manter CommSystem intacto, funcionando em paralelo
7. Adicionar ao `.toc` após `CommSystem.lua`

### Critério de sucesso:
- Mensagens v1 continuam chegando e sendo processadas
- SyncService inicia sem conflito com CommSystem
- Luacheck: 0 warnings

---

## Fase 4 — Migrar Domínios para SyncService 🔲 PENDENTE

**Ordem recomendada** (menor risco de impacto primeiro):

| Domínio | Tipo atual | Prioridade |
|---|---|---|
| `presence` (PI/PO) | Simples, sem dados críticos | 1 |
| `recipe` (RC) | Low stakes, dados reconstituíveis | 2 |
| `wishlist` (WL/LP) | Usado frequentemente | 3 |
| `member` (BC/RQ/RS) | Mais crítico, mais testado | 4 |
| `officerNotes` (ON/OA) | Officers, moderado | 5 |
| `trial` (TR) | Officers | 6 |
| `altLinks` (AL) | Officers, simples | 7 |
| `raid` (RD/RX) | Mais crítico, mais complexo | 8 |

Para cada domínio:
1. Adicionar handler em `SyncService:RegisterHandler(domain, action, fn)`
2. Mover envio para `SyncService:Publish(domain, action, data)`
3. Remover o case correspondente do `CommSystem:OnMessageReceived`
4. Testar sync com outro cliente
5. Documentar em dev-changelog.md

---

## Fase 5 — EventBus Interno 🔲 PENDENTE

**Objetivo**: Desacoplar módulos. UI reage a eventos em vez de polling.

### Passos:
1. Criar `Events.lua` com `Emit`, `On`, `Off`
2. Adicionar ao `.toc` após `Core.lua`
3. Adicionar emissão em `DataCollector:StoreReceivedData` → `MEMBER_UPDATED`
4. Fazer `RosterFrame` escutar `MEMBER_UPDATED` em vez de depender só de `GUILD_ROSTER_UPDATE`
5. Progressivamente adicionar outros eventos conforme necessário
6. Não remover os triggers existentes — adicionar os novos em paralelo

---

## Fase 6 — Separar Commands + Reduzir Core.lua 🔲 PENDENTE

### Passos:
1. Criar `Commands.lua`
2. Mover `SlashCmdList["GUILDOS"]` para Commands.lua
3. Mover handlers de slash commands de Core.lua para Commands.lua
4. Extrair `GuildOS.Compat` para `Compat.lua` (atualmente em Core.lua)
5. Extrair helpers utilitários para `Utils.lua` (DeepCopy, GetClassColor, TimeAgo, etc.)
6. Core.lua fica apenas com: namespace creation, DB defaults, lifecycle events

---

## Fase 7 — Split de UI/Helpers.lua 🔲 PENDENTE

1. Criar `UI/Theme.lua` — extrair `C` table e score color helpers (sem frames)
2. Criar `UI/Core.lua` — extrair factory functions
3. Manter `UI/Helpers.lua` como shim que re-exporta tudo
4. Adicionar ao `.toc` na ordem correta

---

## Fase 8 — Debug Tools e Limpeza 🔲 PENDENTE

1. Adicionar `/gos sync status` — mostra queue, pendingMessages, last broadcast
2. Adicionar `/gos storage stats` — conta entries por domínio
3. Adicionar `/gos memory stats` — conta frames, timers ativos
4. Remover código legado do CommSystem que foi migrado para SyncService
5. Documentação final e limpeza de TODO comments

---

## Dependências entre Fases

```
Fase 1 (✅) → Fase 2 → Fase 3 → Fase 4
                ↓
             Fase 5 pode acontecer em paralelo com Fase 3
             Fase 6 pode acontecer em paralelo com Fase 3
             Fase 7 pode acontecer a qualquer momento
             Fase 8 após todas as outras
```

---

## Critérios de Sucesso Globais

- [ ] Core.lua < 200 linhas (hoje: ~600+)
- [ ] CommSystem ou SyncService centralizado, sem magic strings espalhadas
- [ ] GuildOS.db protegido por Storage/Repositories
- [ ] UI desacoplada de persistência (zero writes diretos a GuildOS.db em UI files)
- [ ] Sync documentada, versionada, com revision check
- [ ] Sem risco de loop de sync
- [ ] Sem timers duplicados
- [ ] Luacheck: 0 warnings / 0 errors em todos os arquivos
- [ ] Addon funciona no WoW após cada fase

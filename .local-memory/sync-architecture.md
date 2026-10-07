# GuildOS — Sync Architecture

_Last updated: 2026-04-26_

---

## Estado Atual do CommSystem

O `CommSystem.lua` é a camada de sync atual. Funciona, mas tem problemas de design:

### O que funciona bem
- Encode/compress/chunk/send com LibSerialize + LibDeflate + ChatThrottleLib
- Reassembla de chunks multi-part com timeout de limpeza (30s)
- Roteamento básico por tipo de mensagem
- Throttle de broadcast (5s entre envios)
- Verificação de permissão de officer antes de aplicar mensagens sensíveis

### Problemas atuais

| Problema | Risco |
|---|---|
| Tipos "WL", "LP", "ON", "RC", "TR" são magic strings espalhadas | Breaking change fácil, difícil de auditar |
| Sem versionamento de protocolo | Mensagens antigas podem sobrescrever dados novos |
| Sem ACK/NACK/retry | Mensagens podem ser perdidas silenciosamente |
| `CommSystem:OnMessageReceived` tem 80+ linhas de if/elseif | Difícil de adicionar novos tipos |
| Modules conhecem detalhes de serialização interna | Acoplamento forte |
| Sem `messageId` único para deduplicação | Possível aplicação dupla da mesma mensagem |
| Sem `revision` nas entidades | Dados antigos podem sobrescrever dados novos |
| Sem separação de `source` (local vs sync) | Loop de sync possível |

---

## Arquitetura Alvo: SyncService

```
┌─────────────────────────────────────────────────────────────────────┐
│  Services / Modules                                                 │
│  Chamam: GuildOS.Sync:Publish(domain, action, payload)              │
│          GuildOS.Sync:Request(domain, action, payload)               │
│          GuildOS.Sync:RegisterHandler(domain, action, fn)           │
└─────────────────────────────┬───────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────────────┐
│  SyncService (Sync/SyncService.lua)                                 │
│                                                                     │
│  Outbound:                                                          │
│  ├─ Monta envelope (messageId, protocolVersion, domain, action...) │
│  ├─ LibSerialize:Serialize(envelope)                                │
│  ├─ LibDeflate:CompressDeflate(serialized)                          │
│  ├─ LibDeflate:EncodeForWoWAddonChannel(compressed)                 │
│  ├─ Chunkeia em pedaços de 230 bytes                               │
│  ├─ Enfileira com prioridade                                        │
│  └─ ChatThrottleLib:SendAddonMessage(priority, prefix, msg, channel)│
│                                                                     │
│  Inbound:                                                           │
│  ├─ Recebe CHAT_MSG_ADDON                                           │
│  ├─ Reassembla chunks (com timeout de limpeza)                      │
│  ├─ Decodifica + descomprime                                        │
│  ├─ Valida envelope (versão, sender, guild)                         │
│  ├─ Verifica permissão (domain-level)                               │
│  ├─ Deduplica por messageId                                         │
│  ├─ Verifica revision (não aplica se revision <= known)            │
│  └─ Chama handler registrado: fn(envelope, sender)                 │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Fases de Migração do CommSystem para SyncService

### Fase A — Backward Compatible
- Criar `SyncService.lua` ao lado do `CommSystem.lua`
- SyncService registra os MESMOS prefixos e tipos
- CommSystem continua funcionando
- Novos domínios podem usar SyncService diretamente

### Fase B — Migrar domínios um por um
Ordem recomendada (menor risco primeiro):
1. `recipe` (RC) — menos crítico
2. `presence` (PI/PO) — simples
3. `member` (BC/RQ/RS) — mais usado
4. `wishlist` (WL/LP) — frequente
5. `officerNotes` (ON/OA) — officers
6. `trial` (TR) — officers
7. `raid` (RD/RX) — crítico
8. `altLinks` (AL) — officers

### Fase C — Remover CommSystem legacy
- Após todos os domínios migrados e testados
- Manter backward compat por 1 patch de versão menor

---

## Envelope de Mensagem

### Versão 1 (atual, implícita)
```
"MSGTYPE:raw_data"
```
Sem metadados. Sem versão. Sem deduplicação.

### Versão 2 (alvo)
```lua
{
    v    = 2,              -- protocolVersion
    id   = "A1B2",         -- messageId (deduplicação)
    av   = "1.0.0",        -- addonVersion
    dom  = "member",       -- domain
     act = "snapshot",     -- action
    ts   = 1714123456,     -- timestamp (GetTime())
    rev  = 3,              -- entity revision
    pv   = 1,              -- payloadVersion
    src  = "local",        -- source: local|sync|migration|import
    data = { ... },        -- payload
}
```

---

## Regras Anti-Loop

Uma alteração recebida via sync **nunca deve gerar outra sync**.

```lua
-- Correto:
function MemberService:ApplyRemoteUpdate(data, source)
    -- source = "sync" → salva, emite evento local, NÃO republica
    Repository:Save(data)
    Events:Emit("MEMBER_UPDATED", data.key)
end

-- Errado:
function MemberService:ApplyRemoteUpdate(data, source)
    Repository:Save(data)
    Sync:Publish("member", "delta", data) -- ← loop!
end
```

---

## Estratégia de Conflito

### Regra principal: Revision Check
```
revision_incoming <= revision_stored → descarta, não sobrescreve
revision_incoming > revision_stored  → aceita
```

### Regras especiais por domínio

| Domínio | Regra |
|---|---|
| `member` | Player só pode ser sobrescrito pelo próprio player ou officer |
| `raid` | Officers somente; revision check obrigatório |
| `officerNotes` | Officers somente; merge de notas por author+timestamp |
| `trial` | Officers somente; merge de notas |
| `altLinks` | Officers somente; snapshot completo substitui |
| `wishlist` | Cada player é dono do próprio wishlist |

### Soft Delete / Tombstone
Para deletes sincronizáveis (ex: sessão de raid deletada):
```lua
-- Armazena tombstone permanente
GuildOS.db.raidTracker.deletedSessions[sessionID] = {
    deletedAt = GetTime(),
    deletedBy = playerKey,
}
-- Nunca restaura se tombstone existe com revision >= incoming
```

---

## Fila de Sync e Throttle

```
Fila de saída:
  - Prioridade "BULK" para dados de background (broadcast, receitas)
  - Prioridade "NORMAL" apenas para mensagens time-sensitive (WELCOME_CLAIM)
  - ChatThrottleLib controla o rate automaticamente
  - Nunca fazer burst: usar C_Timer.After para espaçar chunks

Limpeza de estado:
  - pendingMessages timeout: 30s
  - Se ACK não recebido: retenta 1x após 10s (fase futura)
  - Limitar seenMessageIds a últimas 500 entradas
```

---

## Mapa de Domínios e Tipos Atuais vs Alvo

| Atual msgType | Domínio alvo | Action alvo | Permissão |
|---|---|---|---|
| `BC` | `member` | `snapshot` | todos |
| `RQ` | `member` | `request` | todos |
| `RS` | `member` | `response` | todos |
| `PI` | `presence` | `ping` | todos |
| `PO` | `presence` | `pong` | todos |
| `VR` | `presence` | `version` | todos |
| `AL` | `altLinks` | `snapshot` | officers |
| `RD` | `raid` | `snapshot` | officers |
| `RX` | `raid` | `delete` | officers |
| `OA` | `officerNotes` | `snapshot_all` | officers |
| `WC` | `recruitment` | `welcome_claim` | officers |
| `WL` | `wishlist` | `snapshot` | todos |
| `LP` | `wishlist` | `prios_snapshot` | officers |
| `ON` | `officerNotes` | `delta` | officers |
| `RC` | `recipe` | `snapshot` | todos |
| `TR` | `trial` | `snapshot` | officers |

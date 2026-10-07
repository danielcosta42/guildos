# GuildOS — Sync Protocol

_Last updated: 2026-04-26_

---

## Protocolo v1 (atual, implícito)

### Wire Format

```
Single message:   "S:<base64-encoded-compressed-payload>"
Multi-chunk:      "M:<msgId>:<chunkIdx>:<totalChunks>:<chunk>"

Payload descomprimido: "MSGTYPE:raw_data"
```

### Limitações do v1
- Sem versão de protocolo
- Sem messageId global (msgId só existe dentro do chunking)
- Sem revision nas entidades
- Sem source tracking
- Raw_data é o resultado direto de LibSerialize:Serialize — sem envelope padronizado
- Tipos magic string espalhados

---

## Protocolo v2 (alvo)

### Wire Format (igual ao v1 — transporte não muda)

```
Single (≤253 bytes): "S:<encoded>"
Multi-chunk:         "M:<msgId>:<chunkIdx>:<totalChunks>:<chunk>"
```

### Envelope (muda)

O payload descomprimido passa de `"MSGTYPE:raw_data"` para:

```lua
LibSerialize:Serialize({
    v    = 2,           -- protocol version (uint)
    id   = "A1B2C3D4", -- messageId: 8 hex chars, random
    av   = "1.1.0",    -- addon version string
    dom  = "member",   -- domain: veja tabela de domínios
    act  = "snapshot", -- action: veja tabela de actions
    ts   = 1714123456, -- sender GetTime() (não confiável, apenas para ordering hint)
    rev  = 5,          -- entity revision counter (incrementa no sender)
    pv   = 1,          -- payload schema version
    src  = "local",    -- origin: "local"|"sync"|"migration"|"import"
    data = { ... },    -- payload específico do domínio
})
```

### Compatibilidade com v1

O receiver identifica v1 por:
```lua
local msg = decompressed
if msg:sub(1, 2) == "v=" or (decoded_table and decoded_table.v) then
    -- v2 envelope
else
    -- v1 legacy: parse "MSGTYPE:data"
end
```

Durante a transição, o addon envia v2 mas aceita v1 recebido.

---

## Tabela de Domínios e Actions

| Domain | Action | Descrição | Permissão |
|---|---|---|---|
| `member` | `snapshot` | Broadcast completo dos dados do player | todos |
| `member` | `request` | Solicitar dados de todos ou de um específico | todos |
| `member` | `response` | Resposta a request | todos |
| `presence` | `ping` | Verificar presença | todos |
| `presence` | `pong` | Responder presença + version | todos |
| `presence` | `version` | Anunciar versão do addon | todos |
| `altLinks` | `snapshot` | Snapshot completo de links alt/main | officers |
| `raid` | `snapshot` | Dados de sessões + attendance | officers |
| `raid` | `delete` | Deletar sessão (com tombstone) | officers verificados |
| `officerNotes` | `delta` | Nova nota individual | officers |
| `officerNotes` | `snapshot_all` | Bulk sync de todas as notas | officers |
| `recruitment` | `welcome_claim` | Supressor de welcome duplicado | officers |
| `wishlist` | `snapshot` | Wishlist completa do player | todos |
| `wishlist` | `prios_snapshot` | Prioridades de loot (officer-set) | officers |
| `officerNotes` | `delta` | Nota individual | officers |
| `recipe` | `snapshot` | Receitas de uma profissão | todos |
| `trial` | `snapshot` | Dados completos de trials | officers |

---

## Validação de Envelope

```lua
function SyncService:ValidateEnvelope(env, sender)
    if type(env) ~= "table" then return false, "not_table" end
    if not env.v or not env.id or not env.dom or not env.act then
        return false, "missing_fields"
    end
    if env.v > PROTOCOL_VERSION then
        return false, "protocol_too_new"
    end
    -- Verificar que sender pertence à mesma guild
    if not IsGuildMember(sender) then return false, "not_guild" end
    -- Verificar permissão por domínio
    if OFFICER_DOMAINS[env.dom] and not GuildOS:IsOfficerByName(sender) then
        return false, "permission_denied"
    end
    return true
end
```

---

## Deduplicação

```lua
-- Manter circular buffer dos últimos 500 messageIds recebidos
SyncService.seenIds = {}
SyncService.seenCount = 0

function SyncService:IsDuplicate(id)
    if self.seenIds[id] then return true end
    self.seenIds[id] = true
    self.seenCount = self.seenCount + 1
    -- Limpar entradas antigas após 500
    if self.seenCount > 500 then
        -- wipe e reinicia (simples, não perfeito)
        wipe(self.seenIds)
        self.seenCount = 0
    end
    return false
end
```

---

## Revision Check

```lua
function SyncService:ShouldApply(domain, entityKey, incomingRevision)
    local current = Repository:GetRevision(domain, entityKey) or 0
    return incomingRevision > current
end
```

---

## Chunking Detalhado

```
Constantes:
  CHUNK_SIZE = 230   (bytes por chunk; 255 - overhead do header)
  Header: "M:<8hexChars>:<3digits>:<3digits>:"
  Overhead máximo: 20 bytes → 255 - 20 = 235 → usando 230 para margem

Fluxo de envio:
  1. Monta envelope (tabela Lua)
  2. LibSerialize:Serialize(envelope) → string binária
  3. LibDeflate:CompressDeflate(serialized) → comprimido
  4. LibDeflate:EncodeForWoWAddonChannel(compressed) → safe ASCII
  5. Se len ≤ 253: "S:<encoded>" (mensagem única)
  6. Se len > 253:
     - msgId = random 8 hex chars
     - totalChunks = ceil(len / CHUNK_SIZE)
     - Para cada chunk i:
       - C_Timer.After((i-1) * 0.1, send) [espaça 100ms entre chunks]
       - "M:<msgId>:<i>:<totalChunks>:<chunk>"

Fluxo de recepção:
  1. "S:" → encoded direto
  2. "M:" → parse header, acumula em pendingMessages[sender:msgId]
     - Timeout 30s para limpeza (C_Timer.After)
     - Quando received == total → concatena chunks ordenados
  3. LibDeflate:DecodeForWoWAddonChannel(encoded)
  4. LibDeflate:DecompressDeflate(decoded)
  5. LibSerialize:Deserialize(decompressed)
```

---

## Handshake de Versão

```
Addon carregado:
  Após 3s → Sync:Publish("presence", "version", { v = GuildOS.VERSION })

Recepção de "version":
  Se version < MIN_VERSION → print aviso
  Se version > current → print info "versão mais nova detectada"

Não bloqueia sync, apenas informa.
```

---

## ACK/NACK (fase futura)

Para mensagens críticas (ex: award de loot, delete de raid):

```
Sender → Publish com { requireAck = true }
Receiver → após aplicar com sucesso → Sync:Publish("ack", payload.id)
Sender → aguarda ACK por 10s → se não receber → retenta 1x
         → se ainda falhar → log warning + marcar como pendente
```

Esta feature não está implementada no v1. Planejar para SyncService v2.

# GuildOS — Memory Management

_Last updated: 2026-04-26_

---

## Distinção: Memória Lua vs SavedVariables

| Tipo | Sobrevive ao /reload | Localização | Responsável |
|---|---|---|---|
| Runtime state | NÃO | `GuildOS.State.*` | Core.lua |
| Frames e widgets | NÃO (recriados) | variáveis locais em UI/*.lua | UI files |
| Timers/Tickers | NÃO | `GuildOS.State.*` ou local | Módulo dono |
| SavedVariables | SIM | `GuildOSDB[guildKey]` | Storage |
| Cache computado | NÃO | variáveis locais | Módulo dono |

---

## Mapa de Runtime State Atual

```lua
GuildOS.State = {
    comm = {
        lastBroadcast   = 0,        -- throttle de broadcast
        pendingMessages = {},       -- chunks aguardando reassembla
                                    -- key: "sender:msgId"
                                    -- RISCO: pode crescer se chunks chegam mas nunca completam
                                    -- Mitigação: C_Timer.After(30, cleanup) por mensagem
    },
    lootMaster = {
        activeLoot        = nil,    -- item ativo na loot frame
        rolls             = {},     -- rolls recebidos no roll ativo
        rollTimer         = nil,    -- referência ao timer de roll
        isMLSession       = false,
        lootWindowOpen    = false,
        listeningForRolls = false,
        restrictedRollers = nil,
        pendingTrades     = {},     -- itens na fila de trade
        testMode          = false,
        rollPattern       = nil,    -- regex compilado para detectar rolls
        disenchanter      = "",
    },
    recruitment = {
        ticker           = nil,     -- ticker do auto-recruit
        lastSend         = 0,
        knownMembers     = {},      -- snapshot de membros para detectar novos joins
        rosterReady      = false,
        welcomedRecently = {},      -- dedup de welcome messages
                                    -- RISCO: cresce indefinidamente se não limpo
    },
    raid = {
        currentRaid    = nil,       -- dados da sessão em andamento
        trackingActive = false,
        snapshotTimer  = nil,       -- ticker de snapshot a cada 5min
        endTimer       = nil,       -- timer de confirmação de fim de raid
    },
    consumables = { lastCheck = nil },  -- resultado do último check
    raidCD      = {
        state   = {},    -- [playerName][cdKey] = { start, duration, icon }
        members = {},    -- [name] = classFile
    },
}
```

---

## Riscos de Memória Identificados

### 🔴 pendingMessages sem limpeza garantida
```lua
-- Atual: timeout de 30s POR mensagem
-- Problema: se C_Timer.After falhar ou não disparar, entry persiste
-- Recomendação: varrer periodicamente (a cada 60s) e limpar entradas > 60s de idade
```

### 🔴 welcomedRecently cresce indefinidamente
```lua
-- Atual: nunca é limpo (só resetado no reload)
-- Problema: em raids longas, pode acumular dezenas de entradas
-- Recomendação: limpar entradas com _sent=true após 5 minutos
-- ou: usar circular buffer de tamanho fixo (20 entries)
```

### 🟡 knownMembers varre toda a roster na inicialização
```lua
-- Atual: snapshot de GetGuildRosterInfo em Initialize
-- Problema: se guild tem 200+ membros, pode ser lento
-- Recomendação: fazer snapshot lazy apenas quando recrutamento está ativo
```

### 🟡 Frames da UI não são reutilizados consistentemente
```lua
-- LootMaster.ShowLootFrame recria frames a cada loot opened
-- Recomendação: pool de frames ou hide/reuse
```

### 🟡 Timers duplicados em reload parcial
```lua
-- Se Initialize() for chamado duas vezes (edge case), tickers podem duplicar
-- Recomendação: sempre cancelar o ticker existente antes de criar novo
if State.raid.snapshotTimer then
    State.raid.snapshotTimer:Cancel()
end
State.raid.snapshotTimer = C_Timer.NewTicker(300, fn)
```

### 🟢 raidCD.state acumula entradas de players que saíram
```lua
-- Baixo risco: ScanRaidRoster() faz wipe() antes de rebuild
-- Mas UpdateRow() pode referenciar entries de plays offline
-- Mitigação: BuildHUDRows já usa members que passou pelo wipe
```

---

## Regras de Gerenciamento de Memória

### Timers/Tickers
- Sempre guardar referência no `GuildOS.State.*` correspondente
- Sempre cancelar antes de recriar: `if ref then ref:Cancel() end`
- Nunca criar NewTicker dentro de um OnUpdate frame
- Usar `GuildOS.Compat.NewTicker` — não `C_Timer.NewTicker` direto

### Tabelas
- Usar `wipe(table)` para reaproveitar tabelas em vez de criar novas
- Não criar tabelas grandes em handlers de `COMBAT_LOG_EVENT_UNFILTERED`
- Não fazer `table.concat` com milhares de strings — usar um buffer

### Frames
- Frames de loot/roll recriar apenas se `== nil`; senão reusar com `Show()`
- FauxScrollFrame rows: pool fixo de `VISIBLE_ROWS` rows, sempre reusar
- Não criar FontStrings inline em loops — criar durante setup, atualizar no update

### SavedVariables
- Limites definidos em módulos:
  - `lootHistory` — cap 500
  - `awardHistory` — cap 500 (TODO: implementar)
  - `officerNotes[key].notes` — cap 50
  - `raidTracker.sessions` — cap 200 (TODO: implementar)
  - `raidTracker.deletedSessions` — cap 500 tombstones (TODO: implementar)
- Nunca persistir: frames, funções, itemLinks como única chave (usar itemId)
- `lastResults` de consumable: sobrescrever, não acumular

### Eventos Frequentes
- `COMBAT_LOG_EVENT_UNFILTERED` — fazer early return em tipos irrelevantes ANTES de qualquer processamento
- `UNIT_AURA` — debounce/throttle se varrer raid inteira

---

## Tabela de Timers Ativos

| Timer | Quem cria | Onde guardado | Cancelado quando |
|---|---|---|---|
| Sync ticker (5min) | `CommSystem:Initialize()` | local (não em State!) | nunca (permanente) |
| Request after 8s | `CommSystem:Initialize()` | one-shot, auto-cancela | após disparo |
| Snapshot ticker (5min) | `RaidTracker:StartSession()` | `State.raid.snapshotTimer` | `EndSession()` |
| End raid timer | `RaidTracker` | `State.raid.endTimer` | cancelado se raid retomada |
| Recruitment ticker | `Recruitment:StartAutoRecruit()` | `State.recruitment.ticker` | `StopAutoRecruit()` |
| Trial expiry check | `TrialTracker:Initialize()` | local (one-shot? ou ticker?) | TODO: verificar |
| Pending chunk timeout | `CommSystem:OnMessageReceived()` | por mensagem, one-shot | após 30s |
| Stagger de chunks (send) | `CommSystem:SendMessage()` | one-shot por chunk | após disparo |

### ⚠️ Risco: CommSystem sync ticker não está em GuildOS.State
O ticker do CommSystem é criado em `Initialize()` e não tem referência guardada.
Se `Initialize()` for chamado novamente (não acontece hoje, mas é frágil), cria ticker duplicado.

---

## Dados que NÃO devem ser salvos em SavedVariables

- Frames e objetos WoW (crash)
- Funções Lua (não serializáveis)
- itemLink como chave única (pode mudar entre patches)
- Resultados de scan temporários (consumables last check → OK salvar apenas `lastResults`)
- Queue de sync (runtime only)
- Pending ACKs (runtime only)
- Debug flags temporárias
- Estado visual (quais painéis estão abertos, posição de scroll)

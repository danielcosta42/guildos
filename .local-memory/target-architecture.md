# GuildOS — Target Architecture

_Last updated: 2026-04-26_

---

## Visão Geral

A arquitetura alvo separa o addon em 8 camadas claras com responsabilidades únicas.
A refatoração é **incremental** — cada fase mantém o addon funcionando.

---

## Diagrama de Camadas

```
┌─────────────────────────────────────────────────────────────────────┐
│  UI Layer                                                           │
│  UI/RosterFrame | UI/FeaturePanels | UI/MemberDetail                │
│  UI/RecipesPanel | UI/RaidHUD                                       │
│  ✓ Apenas renderização e interação visual                          │
│  ✓ Chama Services, nunca acessa Storage/GuildOS.db diretamente      │
│  ✓ Reage a DomainEvents do EventBus interno                        │
├─────────────────────────────────────────────────────────────────────┤
│  Commands Layer                                                     │
│  Commands.lua                                                       │
│  ✓ Todos os slash commands separados do Core                       │
│  ✓ Delega para Services                                            │
├─────────────────────────────────────────────────────────────────────┤
│  Services Layer                                                     │
│  RaidService | LootService | WishlistService | RecipeService        │
│  MemberService | OfficerNotesService | TrialService                 │
│  RecruitmentService | AttunementService                             │
│  ✓ Regras de negócio puras                                         │
│  ✓ Emite DomainEvents após alterações                              │
│  ✓ Delega sync para SyncService                                    │
├─────────────────────────────────────────────────────────────────────┤
│  Sync Layer                                                         │
│  SyncService (evolução do CommSystem)                               │
│  ✓ API única: Publish / Request / RegisterHandler                  │
│  ✓ Cuida de: serialize, compress, chunk, throttle, ACK/NACK/retry  │
│  ✓ Protocolo versionado com envelope de metadados                  │
│  ✓ Nunca aplica dados diretamente — delega para Services           │
├─────────────────────────────────────────────────────────────────────┤
│  Repository Layer                                                   │
│  MemberRepository | RaidRepository | LootRepository                │
│  WishlistRepository | RecipeRepository | OfficerNotesRepository     │
│  TrialRepository | RecruitmentRepository                            │
│  ✓ Leitura/escrita por domínio                                     │
│  ✓ Única camada que conhece a estrutura do Storage                 │
├─────────────────────────────────────────────────────────────────────┤
│  Storage Layer                                                      │
│  Storage.lua                                                        │
│  ✓ ÚNICO acesso direto a GuildOSDB/GuildOS.db                       │
│  ✓ Schema, defaults, migrations, limites                           │
│  ✓ Distinção clara: persisted / runtime / cache / computed         │
├─────────────────────────────────────────────────────────────────────┤
│  Events Layer                                                       │
│  Events.lua (EventBus interno)                                      │
│  ✓ GuildOS.Events:Emit(event, payload)                              │
│  ✓ GuildOS.Events:On(event, handler)                                │
│  ✓ Registro e roteamento de eventos do WoW                         │
├─────────────────────────────────────────────────────────────────────┤
│  Core Layer                                                         │
│  Core.lua (reduzido a boot + lifecycle)                             │
│  Config.lua (constantes, prefixos, limites, defaults)              │
│  Utils.lua (helpers puros sem estado global)                       │
│  Compat.lua (GuildOS.Compat — API guards, hoje em Core.lua)         │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Estrutura de Pastas Alvo

```
GuildOS/
├── GuildOS.toc
├── Core.lua            ← boot/lifecycle apenas
├── Config.lua          ← constantes, versões, prefixos, defaults
├── Compat.lua          ← GuildOS.Compat (API guards) — extraído do Core
├── Events.lua          ← GuildOS.Events (EventBus interno)
├── Commands.lua        ← todos os slash commands
├── Utils.lua           ← helpers puros (hoje em Core.lua)
│
├── Storage/
│   └── Storage.lua     ← único acesso a GuildOSDB
│
├── Repository/
│   ├── MemberRepository.lua
│   ├── RaidRepository.lua
│   ├── LootRepository.lua
│   ├── WishlistRepository.lua
│   ├── RecipeRepository.lua
│   ├── OfficerNotesRepository.lua
│   └── TrialRepository.lua
│
├── Sync/
│   └── SyncService.lua ← evolução do CommSystem
│
├── Services/           ← (opcionais; domínios menores podem ficar nos módulos atuais)
│   ├── MemberService.lua
│   ├── RaidService.lua
│   └── ...
│
├── (módulos atuais mantidos durante transição)
│   DataCollector.lua | AttunementTracker.lua | RaidTracker.lua ...
│
├── Libs/
└── UI/
    ├── Theme.lua       ← C table, cores, tamanhos (extraído de Helpers)
    ├── Core.lua        ← factory functions (extraído de Helpers)
    ├── Helpers.lua     ← shim backward-compat
    ├── RosterFrame.lua
    ├── MemberDetail.lua
    ├── FeaturePanels.lua
    ├── RecipesPanel.lua
    └── RaidHUD.lua
```

---

## SyncService API Alvo

```lua
-- Publicar um evento de sync
GuildOS.Sync:Publish(domain, action, payload, options)
-- domain: "member" | "raid" | "loot" | "wishlist" | "recipe" | ...
-- action: "snapshot" | "delta" | "delete" | "ack" | "nack" | "request" | ...
-- options: { priority, target, requireOfficer, version }

-- Requisitar dados de outros membros
GuildOS.Sync:Request(domain, action, payload, options)

-- Registrar handler para mensagens recebidas
GuildOS.Sync:RegisterHandler(domain, action, function(envelope, sender)
    -- validado, deduplicado, descomprimido
end)
```

---

## Envelope de Mensagem Alvo

```lua
{
    messageId       = "A1B2",      -- hex randômico para dedup
    protocolVersion = 2,           -- versão do protocolo
    addonVersion    = "1.0.0",     -- versão do addon do sender
    domain          = "member",    -- domínio de dados
    action          = "snapshot",  -- tipo de ação
    sender          = "Name-Realm",
    senderRank      = 1,           -- rank verificado na guild
    guildKey        = "Guild-Realm",
    timestamp       = 1714123456,  -- GetTime() do sender
    revision        = 3,           -- contador de revisão da entidade
    payloadVersion  = 1,           -- versão do schema do payload
    source          = "local",     -- "local" | "sync" | "migration" | "import"
    payload         = { ... },     -- dados domínio-específicos
}
```

---

## Domínios de Sync

| Domínio | Actions | Permissão |
|---|---|---|
| `member` | snapshot, delta | todos |
| `raid` | snapshot, delta, delete | officers |
| `loot` | snapshot | officers |
| `wishlist` | snapshot | todos |
| `recipe` | snapshot | todos |
| `officerNotes` | delta, snapshot_all | officers |
| `trial` | snapshot | officers |
| `recruitment` | welcome_claim | officers |
| `altLinks` | snapshot | officers |
| `presence` | ping, pong | todos |

---

## Storage Schema Alvo

```lua
GuildOSDB = {
    dbVersion = 2,
    guilds = {
        ["GuildName-Realm"] = {
            members          = {},
            raidTracker      = {},
            lootHistory      = {},  -- LIMITADO a 500 entries
            lootMaster       = {},
            guildWishlists   = {},
            lootPrios        = {},
            wishlists        = {},
            recipes          = {},
            recipeScanTimes  = {},
            officerNotes     = {},
            trials           = {},
            altLinks         = {},
            recruitment      = {},
            consumableChecks = {},
            settings         = {},
        }
    }
}
-- Dados de runtime ficam em GuildOS.State (nunca em SavedVariables)
```

---

## EventBus Interno Alvo

```lua
-- Emitir
GuildOS.Events:Emit("MEMBER_UPDATED", memberKey)
GuildOS.Events:Emit("RAID_SESSION_UPDATED", sessionId)
GuildOS.Events:Emit("SYNC_STATUS_CHANGED", status)

-- Escutar
GuildOS.Events:On("MEMBER_UPDATED", function(key)
    RosterFrame:RefreshRow(key)
end)

-- Cancelar
GuildOS.Events:Off("MEMBER_UPDATED", handlerRef)
```

---

## Regras Obrigatórias

1. `GuildOS.db` só pode ser acessado por `Storage.lua` e `Repository/*.lua`
2. UI nunca acessa SavedVariables diretamente
3. UI callbacks são one-liners que delegam para Services
4. Toda sync passa pela API `GuildOS.Sync:Publish/Request`
5. Nenhuma alteração recebida via sync gera outra sync automaticamente
6. `source` nas entidades distingue: `local` | `sync` | `migration` | `import`
7. Dados com `revision` menor nunca sobrescrevem dados com `revision` maior
8. Deletes sincronizáveis usam soft delete / tombstone
9. Dados temporários (State) nunca são persistidos
10. Computed data (scores, percentuais) não são salvos se podem ser recalculados

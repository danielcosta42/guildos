# GuildOS — Event System

_Last updated: 2026-04-26_

---

## Arquitetura Atual: Frames Espalhados

Atualmente não existe um EventBus centralizado.
Cada módulo cria seu próprio frame e registra eventos diretamente.

### Frame Principal (Core.lua)

```lua
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
```

| Evento WoW | Handler | Responsabilidade |
|---|---|---|
| `ADDON_LOADED` | `GuildOS:Initialize()` | Bootstrap — registra prefix, etc |
| `PLAYER_LOGIN` | `GuildOS:OnLogin()` | Resolve DB, inicializa módulos |
| `PLAYER_ENTERING_WORLD` | `GuildOS:OnEnterWorld()` | Coleta + broadcast dados |
| `GUILD_ROSTER_UPDATE` | `GuildOS:OnGuildRosterUpdate()` | Refresh do RosterFrame |
| `PLAYER_GUILD_UPDATE` | `GuildOS:OnGuildRosterUpdate()` | Refresh do RosterFrame |

---

### Frames por Módulo

| Módulo | Eventos registrados | Frame |
|---|---|---|
| `CommSystem` | `CHAT_MSG_ADDON` | local frame em `Initialize()` |
| `DataCollector` | `PLAYER_EQUIPMENT_CHANGED`, `SKILL_LINES_CHANGED` | local frame em `Initialize()` |
| `RaidTracker` | `ZONE_CHANGED_NEW_AREA`, `RAID_ROSTER_UPDATE`, `ENCOUNTER_START`, `ENCOUNTER_END`, `PLAYER_ENTERING_WORLD` | local frame em `Initialize()` |
| `LootMaster` | `LOOT_OPENED`, `LOOT_CLOSED`, `CHAT_MSG_SYSTEM`, `TRADE_SHOW`, `TRADE_ACCEPT_UPDATE` | local frame em `Initialize()` |
| `LootTracker` | `LOOT_SLOT_CLEARED` (ou similar) | local frame |
| `RecipeTracker` | `TRADE_SKILL_SHOW`, `TRADE_SKILL_CLOSE`, `CRAFT_SHOW`, `CRAFT_CLOSE` | local frame |
| `SpecChecker` | `INSPECT_READY` | local frame |
| `RecruitmentSystem` | `GUILD_ROSTER_UPDATE` (para snapshot de membros), `CHAT_MSG_SYSTEM` (para welcome) | local frames |
| `TrialTracker` | nenhum (usa timers) | — |
| `RaidHUD` | `GROUP_ROSTER_UPDATE`, `COMBAT_LOG_EVENT_UNFILTERED` | local frames |

---

## Problemas do Sistema Atual

### 🔴 Sem desacoplamento
- Módulos chamam UI diretamente ou dependem de polling
- Não há forma de um módulo notificar outros sem conhecer quem está interessado
- Ex: quando `DataCollector:StoreReceivedData` salva um membro, o RosterFrame não sabe automaticamente — precisa de GUILD_ROSTER_UPDATE ou polling

### 🔴 Múltiplos frames para o mesmo evento
- `GUILD_ROSTER_UPDATE` é registrado tanto no Core quanto no RecruitmentSystem
- `PLAYER_ENTERING_WORLD` é registrado no Core e no RaidTracker
- Performance: múltiplos handlers, mas aceitável se cada um é leve

### 🟡 Sem cancelamento de handlers
- Uma vez registrado, um handler fica para sempre
- Não há `Off()` / unsubscribe

---

## EventBus Alvo (Events.lua)

```lua
-- Events.lua
GuildOS.Events = {}
local handlers = {}

-- Registrar handler para um evento interno
function GuildOS.Events:On(event, fn)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], fn)
end

-- Cancelar handler
function GuildOS.Events:Off(event, fn)
    if not handlers[event] then return end
    for i, h in ipairs(handlers[event]) do
        if h == fn then
            table.remove(handlers[event], i)
            return
        end
    end
end

-- Emitir evento interno
function GuildOS.Events:Emit(event, ...)
    if not handlers[event] then return end
    for _, fn in ipairs(handlers[event]) do
        local ok, err = pcall(fn, ...)
        if not ok then
            GuildOS.Logger.Warn("EventBus error on " .. event .. ": " .. tostring(err))
        end
    end
end
```

### Eventos Internos Planejados

| Evento interno | Quando emitir | Quem escuta |
|---|---|---|
| `MEMBER_UPDATED` | `DataCollector:StoreReceivedData()` | `RosterFrame` |
| `MEMBER_LOCALLY_UPDATED` | `DataCollector:CollectMyData()` | `RosterFrame`, `MemberDetail` |
| `RAID_SESSION_STARTED` | `RaidTracker:StartSession()` | `RaidHUD`, `FeaturePanels` |
| `RAID_SESSION_ENDED` | `RaidTracker:EndSession()` | `RaidHUD`, `FeaturePanels` |
| `RAID_SNAPSHOT_TAKEN` | `RaidTracker:TakeSnapshot()` | `FeaturePanels` |
| `LOOT_RECORDED` | `LootTracker:RecordMLAward()` | `FeaturePanels` |
| `WISHLIST_UPDATED` | `WishlistSystem:BroadcastMyWishlist()` | `FeaturePanels` |
| `RECIPE_SCANNED` | `RecipeTracker:StoreMyRecipes()` | `RecipesPanel` |
| `SYNC_STATUS_CHANGED` | `CommSystem/SyncService` | `UI` (status indicator) |
| `OFFICER_NOTE_ADDED` | `OfficerNotes:AddNote()` | `MemberDetail` |
| `TRIAL_UPDATED` | `TrialTracker:*` | `FeaturePanels` |
| `RECRUITMENT_STATUS_CHANGED` | `RecruitmentSystem:*` | `FeaturePanels` |
| `SETTINGS_CHANGED` | `GuildOS:SetSetting()` | `RosterFrame`, outros |

---

## Eventos WoW Usados — Inventário Completo

| Evento WoW | Frequência | Quem usa | Risco perf |
|---|---|---|---|
| `ADDON_LOADED` | uma vez | Core | nenhum |
| `PLAYER_LOGIN` | uma vez | Core | nenhum |
| `PLAYER_ENTERING_WORLD` | por zone change | Core, RaidTracker | baixo |
| `GUILD_ROSTER_UPDATE` | frequente | Core, Recruitment | baixo |
| `PLAYER_GUILD_UPDATE` | raro | Core | nenhum |
| `CHAT_MSG_ADDON` | por mensagem addon | CommSystem | baixo |
| `PLAYER_EQUIPMENT_CHANGED` | por troca de item | DataCollector | baixo |
| `SKILL_LINES_CHANGED` | por treino/skill | DataCollector | baixo |
| `ZONE_CHANGED_NEW_AREA` | por mudança de zona | RaidTracker | baixo |
| `RAID_ROSTER_UPDATE` | frequente em raid | RaidTracker | médio |
| `ENCOUNTER_START` | por boss pull | RaidTracker | nenhum |
| `ENCOUNTER_END` | por fim de encounter | RaidTracker | nenhum |
| `LOOT_OPENED` | por abertura de loot | LootMaster | nenhum |
| `LOOT_CLOSED` | por fechamento de loot | LootMaster | nenhum |
| `CHAT_MSG_SYSTEM` | muito frequente | LootMaster, Recruitment | ⚠️ médio |
| `TRADE_SHOW` | por abertura de trade | LootMaster | nenhum |
| `TRADE_ACCEPT_UPDATE` | durante trade | LootMaster | nenhum |
| `TRADE_SKILL_SHOW` | por abertura de trade skill | RecipeTracker | nenhum |
| `TRADE_SKILL_CLOSE` | por fechamento | RecipeTracker | nenhum |
| `CRAFT_SHOW` | por abertura de craft (Enchanting) | RecipeTracker | nenhum |
| `CRAFT_CLOSE` | por fechamento | RecipeTracker | nenhum |
| `INSPECT_READY` | por inspect completado | SpecChecker | nenhum |
| `GROUP_ROSTER_UPDATE` | por mudança de grupo | RaidHUD | baixo |
| `COMBAT_LOG_EVENT_UNFILTERED` | MUITO frequente | RaidHUD | ⚠️ ALTO |

### Atenção: COMBAT_LOG_EVENT_UNFILTERED

Este evento dispara **dezenas de vezes por segundo** em combate.
O handler em `RaidHUD.lua` deve retornar imediatamente se o evento não for relevante:

```lua
local function HandleCombatLogCD()
    local timestamp, subEvent, _, sourceGUID, sourceName = CombatLogGetCurrentEventInfo()
    -- Retornar imediatamente para eventos não relevantes
    if subEvent ~= "SPELL_CAST_SUCCESS" then return end
    -- ...
end
```

### Atenção: CHAT_MSG_SYSTEM

Este evento dispara para todo tipo de mensagem de sistema, incluindo roll results de TODOS os jogadores.
O handler em LootMaster deve ter early return:

```lua
if not GuildOS.State.lootMaster.listeningForRolls then return end
```

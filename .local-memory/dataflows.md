# GuildOS — Dataflows

_Last updated: 2026-04-26_

---

## 1. Carregamento Inicial (Login / Reload)

```
ADDON_LOADED (GuildOS)
  └─► GuildOS:Initialize()
        ├─ GuildOS.Compat.RegisterAddonPrefix("GuildOS")
        └─ print version to chat

PLAYER_LOGIN
  └─► GuildOS:OnLogin()
        ├─ GuildOS:ResolveGuildDB()         ← cria ou recupera GuildOSDB[guildKey] → GuildOS.db
        │   (retry até 5x com C_Timer.After se guild não carregada ainda)
        └─ GuildOS:InitModules()
              ├─ DataCollector:Initialize()
              ├─ AttunementTracker:Initialize()
              ├─ CommSystem:Initialize()     ← registra CHAT_MSG_ADDON, inicia ticker 5min, request após 8s
              ├─ RecruitmentSystem:Initialize()
              ├─ WishlistSystem:Initialize()
              ├─ RaidTracker:Initialize()
              ├─ LootTracker:Initialize()
              ├─ LootMaster:Initialize()
              ├─ RecipeTracker:Initialize()
              ├─ OfficerNotes:Initialize()
              ├─ TrialTracker:Initialize()
              ├─ ConsumableChecker:Initialize()
              └─ SpecChecker:Initialize()

PLAYER_ENTERING_WORLD (isInitialLogin=true ou isReloadingUi=true)
  └─► GuildOS:OnEnterWorld()
        ├─ DataCollector:CollectMyData()
        └─ CommSystem:BroadcastMyData()
              ├─ DataCollector:GetBroadcastData() → payload limpo
              └─ CommSystem:SendMessage(BROADCAST, serialized)
                    ├─ LibSerialize:Serialize(data)
                    ├─ LibDeflate:CompressDeflate(payload)
                    ├─ LibDeflate:EncodeForWoWAddonChannel(compressed)
                    └─ ChatThrottleLib:SendAddonMessage("BULK", "GuildOS", msg, "GUILD")
```

---

## 2. Sincronização de Dados (Recepção)

```
CHAT_MSG_ADDON (prefix="GuildOS")
  └─► CommSystem:OnMessageReceived(msg, channel, sender)
        ├─ Ignora próprias mensagens
        ├─ "S:<encoded>" → decode direto
        ├─ "M:<msgId>:<idx>:<total>:<chunk>" → acumula em GuildOS.State.comm.pendingMessages
        │   timeout 30s: pm[key] = nil
        │   quando received == total → reassembla
        ├─ LibDeflate:DecodeForWoWAddonChannel(encoded)
        ├─ LibDeflate:DecompressDeflate(decoded)
        ├─ parse: msgType, data = match("^(%w+):(.*)$")
        └─ roteamento por msgType:
              BC  → CommSystem:HandleBroadcast(sender, data)
                      └─► DataCollector:StoreReceivedData(key, playerData)
              RQ  → CommSystem:HandleRequest(sender, data)
                      └─► CommSystem:BroadcastMyData() (staggered)
              RS  → CommSystem:HandleResponse(sender, data)
                      └─► CommSystem:HandleBroadcast(sender, data)
              PI  → CommSystem:HandlePing(sender) → PONG
              VR  → CommSystem:HandleVersionCheck(sender, data)
              WL  → Wishlist:HandleWishlistBroadcast(sender, data)
              LP  → Wishlist:HandleLootPriosBroadcast(sender, data)
              ON  → OfficerNotes:HandleIncoming(data)
              RC  → RecipeTracker:HandleIncoming(sender, data)
              TR  → TrialTracker:HandleIncoming(data)        [officer only]
              AL  → GuildOS.db.altLinks = links               [officer only]
              RD  → RaidTracker:HandleIncoming(data)         [officer only]
              RX  → RaidTracker:HandleDeleteIncoming(data)   [officer + verificado]
              OA  → OfficerNotes:HandleAllIncoming(data)     [officer only]
              WC  → State.recruitment.welcomedRecently[member] = true
```

---

## 3. Atualização de UI

```
GUILD_ROSTER_UPDATE / PLAYER_GUILD_UPDATE
  └─► GuildOS:OnGuildRosterUpdate()
        └─ RosterFrame:RefreshRoster()
              ├─ BuildMemberList() — GetGuildRosterInfo + GuildOS.db.members merge
              ├─ UpdateSortIndicators()
              ├─ UpdateRows() — FauxScrollFrame virtual scroll
              └─ UpdateStats() — contagem de membros, online, addon-users

Tab click
  └─► RosterFrame:SetActiveTab(key)
        └─ FeaturePanels.ShowPanel(panelName)

Row click (membro)
  └─► GuildOS:ShowMemberDetail(memberData)
        └─ PopulateDetail(frame, data) — spec, gear, profs, atunamentos, notas, alts

RaidTracker
  └─► (sem EventBus hoje) — polling via RefreshRaidsPanel quando tab é aberta
```

---

## 4. Fluxo de Coleta de Dados Local

```
PLAYER_EQUIPMENT_CHANGED / SKILL_LINES_CHANGED
  └─► DataCollector:CollectMyData()
        ├─ CollectGear() → GetInventoryItemLink para cada slot
        ├─ CollectProfessions() → GetSkillLineInfo loop
        ├─ CollectStats() → UnitStat("player", stat)
        └─ AttunementTracker:ScanAttunements()
              └─ IsQuestComplete(questId) → GuildOS.Compat.IsQuestComplete(questId)
                    └─ C_QuestLog.IsQuestFlaggedCompleted(questId) [com fallback]
```

---

## 5. Fluxo de Raid Tracking

```
ZONE_CHANGED_NEW_AREA
  └─► RaidTracker:CheckZone()
        ├─ GetInstanceInfo() → instance type/id
        ├─ Se entrou em raid → StartSession(instanceID)
        │     ├─ currentRaid = { ... } → GuildOS.State.raid.currentRaid
        │     └─ snapshotTimer = C_Timer.NewTicker(300, TakeSnapshot)
        └─ Se saiu de raid → EndSession()
              ├─ cancela snapshotTimer e endTimer
              ├─ se <10 min → descarta sessão
              └─ salva em GuildOS.db.raidTracker.sessions

ENCOUNTER_START / ENCOUNTER_END
  └─► OnEncounterStart / OnEncounterEnd → registra em currentRaid.encounters

RAID_ROSTER_UPDATE
  └─► RaidTracker:TakeSnapshot("roster_change")
        └─ ConsumableChecker:CheckRaid() → check flask/food/elixir para cada member
```

---

## 6. Fluxo de Loot Master

```
LOOT_OPENED (se IsMasterLooter())
  └─► LootMaster:OnLootOpened()
        └─ ShowLootFrame(items) — lista itens Rare+

Item clicado na loot frame
  └─► LootMaster:AnnounceItem(itemLink, lootSlot)
        ├─ Se lootPrios → AnnounceWithPrios
        ├─ Se wishlistOnly + candidatos → AutoCouncilAward ou StartRestrictedRoll
        └─ Se open roll → DoNormalAnnounce (RAID_WARNING + addon msg)

CHAT_MSG_SYSTEM (listening=true)
  └─► ProcessSystemRoll(message)
        └─ RegisterRoll(name, rollType, roll)

Timer expira
  └─► EndRolling()
        ├─ Anuncia vencedor
        ├─ AwardLoot(winner) → GiveMasterLoot ou QueueForTrade
        └─ LootTracker:RecordMLAward(entry)
```

---

## 7. Fluxo de Slash Commands

```
/gos [args]
  └─► Core.lua SlashCmdList handler
        ├─ "" → GuildOS:ToggleRoster()
        ├─ "scan" → DataCollector:CollectMyData()
        ├─ "sync" → CommSystem:FullSync()
        ├─ "reset" → GuildOSDB = nil; ReloadUI()
        └─ "recruit ..." → Recruitment:HandleCommand(args)
```

---

## 8. Fluxo de Sincronização de Dados de Oficial

```
Officer altera nota:
  OfficerNotes:AddNote(playerKey, text)
    ├─ Adiciona a GuildOS.db.officerNotes[key]
    └─ BroadcastNote(playerKey, entry) → CommSystem:SendMessage("ON:", ...)

Officer altera trial:
  TrialTracker:AddTrial(playerKey, sponsor)
    ├─ Cria GuildOS.db.trials[key]
    └─ BroadcastTrials() → CommSystem:SendMessage("TR:", ...)

Officer sincroniza raids:
  RaidTracker:BroadcastRaidData() → CommSystem:SendMessage("RD:", ...)
```

---

## 9. Fluxo de Wishlist

```
Player adiciona item:
  Wishlist:AddToWishlist(itemId, itemLink, isOffspec)
    ├─ Cria/atualiza GuildOS.db.wishlists[charKey]
    └─ BroadcastMyWishlist() → CommSystem:SendMessage("WL:", ...)

Recepção:
  Wishlist:HandleWishlistBroadcast(sender, data)
    └─ Armazena em GuildOS.db.guildWishlists[lowerName]

Tooltip hover item:
  Wishlist:HookTooltips() → OnTooltipSetItem
    └─ GetItemInterest(itemId) → mostra quem tem no wishlist
```

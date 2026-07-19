# Guild OS — Roster Admin & Audit (Tier 1) — Design Spec

- **Data:** 2026-07-19
- **Status:** Aprovado (design) — aguardando revisão do spec antes do plano
- **Autor:** Daniel + Claude (brainstorming)
- **Origem:** varredura competitiva (GRM, GuildMap, ChatUtils, Axiom, Jefe de Guerra/GCM, GuildKit).
  Furos reais identificados que 3+ concorrentes exploram e o Guild OS não cobre.

---

## 1. Objetivo

Fechar os três furos de **administração/auditoria de roster** que os concorrentes têm e o
Guild OS não:

1. **Ban/Blacklist list** sincronizada (GRM + Axiom + GuildKit).
2. **Auto-invite por keyword** com trava (GuildKit + Axiom).
3. **Event log unificado e sincronizado** — trilha de auditoria de roster (GRM "Event Log" +
   Axiom "Vulture Protocol" + GuildKit "Activity Feed").

Escolhas de escopo do usuário (brainstorming):
- Event log: **synced + dedup (full)** — ver eventos mesmo tendo ficado offline.
- Ban list: **completo** — permanent + temp-ban com auto-expiry, 3 gatilhos de alerta.
- Auto-invite: **hands-free com trava** — ban-gate + filtros + cooldown + opt-in.

## 2. Non-goals (YAGNI)

- Gatilho de auto-invite por canal/guild (só **whisper** no v1).
- Hardcore death log.
- Reconciliação de troca-de-nome sem GUID estável (stretch condicional).
- Gráficos/analytics de composição (é outro Tier).
- Recruit scanner via `/who` em massa (é outro Tier — o auto-invite usa `/who` só pontualmente).

## 3. Contexto — o que já existe e será reusado

- **SyncService** (`Modules/SyncService.lua`): protocolo v2. API relevante:
  - `SyncService:On(domain, fn)` — registra handler `fn(env, sender)`.
  - `SyncService:Publish(domain, action, data, opts)` — `opts = { rev, requireAck, target, priority }`.
  - `SyncService.OFFICER_DOMAINS[domain] = true` — escrita restrita a oficial (`IsOfficerByName(sender)`).
  - `SyncService.MEMBER_ACTIONS` — ações liberadas a membro dentro de domínio officer.
  - `ShouldApply(domain, key, rev)` / `NextRevision(domain, key)` / `SetRevision(domain, key, rev)`.
  - Dedup de transporte por `messageId` (circular buffer 500); ACK + 1 retry (10s).
  - Store de revisão persistente: `db.sync.rev[domain][entityKey]`.
- **RecruitmentSystem** (`Modules/RecruitmentSystem.lua`): já tem
  `HookChatInvite`, `GuildInvite(target)` sob `CanGuildInvite()`, opt-in tri-state de re-post,
  e o padrão de coordenação determinística `_welcomeIntents` (WELCOME_INTENT/CLAIM, menor-nome-vence).
- **GuildManager** (`Modules/GuildManager.lua`): `managementLog` — ring buffer **local**,
  `LogAction(action, target, detail)`, cap `LOG_MAX`, exibido na sub-aba **History** da Leadership.
  **Será absorvido** pelo RosterLog.
- **Convenções** (roadmap + memory): um módulo = um propósito + seu sync; `C_Timer`/`C_GuildInfo`
  via `Compat`; `GetGuildRosterInfo` 1-indexed e sempre nil-checado; cada domínio novo precisa de
  **cap + prune**; cold-login timing exige throttle (mesh lesson).

## 4. Arquitetura (Approach A)

| Peça | Arquivo | Sync domain | Esforço |
|---|---|---|---|
| Ban List | `Modules/BanList.lua` (novo) + sub-aba `UI/ManagementPanel.lua` | `ban` (officer) | M |
| Auto-invite | estende `Modules/RecruitmentSystem.lua` + config `UI/FeaturePanels.lua` | — | S-M |
| Event Log | `Modules/RosterLog.lua` (novo, absorve `managementLog`) + sub-aba `UI/ManagementPanel.lua` | `audit` (officer) | L |

Ambos os domínios entram em `SyncService.OFFICER_DOMAINS` (`ban`, `audit`) → **só oficial publica**.
Registro dos módulos no `.toc` na ordem: `BanList` antes de `RecruitmentSystem` (gate) e `RosterLog`
depois de `GuildManager` (absorve o log). Inicialização via o hook confiável já usado pelos módulos.

**Decisão de segurança (audit officer-domain):** publicar eventos é restrito a oficiais. Isso previne
forja social ("Bob kickou Alice"). Cobertura permanece alta porque kicks/promotes são *executados* por
um oficial que está online por definição, e a maioria dos oficiais roda o addon. Eventos ocorridos com
zero oficiais-com-addon online não são registrados (aceito, raro).

---

## 5. Feature 1 — Ban List (`ban`)

### 5.1 Modelo de dados
```
db.banList = {
  [nameKey] = {           -- nameKey = nome curto normalizado (lower), sem realm p/ mesmo realm
    name    = "Playername",   -- capitalização de exibição
    reason  = "ninja / griefing",
    author  = "OfficerName",
    ts      = <serverTime>,   -- quando baniu
    expiry  = nil | <serverTime>,   -- nil = permanente; futuro = temp-ban
    rev     = <int>,          -- revision da entidade
    removed = nil | true,     -- tombstone (un-ban propagável)
  }, ...
}
```

### 5.2 API do módulo
- `BanList:Add(name, reason, durationSec?)` — durationSec nil = permanente; senão `expiry = now + dur`.
  Aloca `NextRevision("ban", key)`, grava, `Publish("ban","set", entry, {rev})` — **broadcast a todos os
  oficiais** (sem `target`). O ACK do SyncService é ponto-a-ponto (exige `target`), então **não se aplica
  a broadcast**: a convergência vem do revision-check (maior rev vence) + o sync periódico de 5 min.
- `BanList:Remove(name)` — grava tombstone `removed=true` com rev++, publica `ban/remove` (broadcast, rev).
- `BanList:IsBanned(name)` → bool — **true só se** entrada existe, `removed` falso, e (`expiry` nil **ou** `expiry > now`).
- `BanList:Get(name)` → entry (p/ motivo/autor no alerta e tooltip).
- `BanList:List()` → array ordenado (ativos primeiro, depois expirados), p/ UI.
- Handler `SyncService:On("ban", fn)`: aplica `set`/`remove` se `ShouldApply("ban", key, env.rev)`,
  depois `SetRevision`.

### 5.3 Detecção / alertas
1. **Rejoin** — no `GUILD_ROSTER_UPDATE`, reusa o snapshot-diff (mesma técnica do welcome). Membro
   novo cujo nome `IsBanned` → RaidWarning-style aos oficiais online:
   `⛔ Banido {name} ({reason}) acabou de entrar — banido por {author} em {data}`.
2. **Whisper** — `CHAT_MSG_WHISPER` de nome banido → aviso discreto no chat do oficial (1x, com cooldown).
3. **Tooltip** — hook `GameTooltip:HookScript("OnTooltipSetUnit", fn)`; se `UnitName` do tooltip
   `IsBanned` → `AddLine("⛔ BANIDO — {reason} (por {author})", 1, 0.2, 0.2)`.

### 5.4 Auto-expiry / prune
Temp-bans não são deletados na hora de expirar; `IsBanned` já os trata como inativos. Um prune
periódico (no `PruneStaleData` estendido) remove entradas `expiry < now - 7d` e tombstones antigos.

### 5.5 UI
Sub-aba **"Ban List"** na Leadership (officer-only): tabela (Nome · Motivo · Autor · Data · Expira),
botão Add (nome + motivo + toggle permanente/temp + campo de dias), Remove por linha, busca por nome.
Entradas expiradas em cinza.

### 5.6 Comandos
- `/gos ban <nome> [motivo]` — ban permanente.
- `/gos tempban <nome> <dias> [motivo]` — temp-ban.
- `/gos unban <nome>` — remove.
- `/gos banlist` — abre a sub-aba.

### 5.7 Edge cases
- Nome com realm (cross-realm): normalizar por nome curto no mesmo realm; guardar realm se presente.
- Banir alguém que já está na guild: aceitar (avisa que está dentro; opcionalmente sugerir kick manual).
- Conflito de edição concorrente: revision-check resolve (maior rev vence); tombstone com rev maior
  sempre vence um `set` antigo.

### 5.8 Aceitação
- [ ] Oficial A bane → Oficial B (online) vê a entrada em ≤ 1 ciclo de sync (convergência por revision).
- [ ] Banido tenta reentrar → alerta dispara pros oficiais online.
- [ ] Tooltip mostra flag vermelha em banido.
- [ ] Temp-ban expira sozinho (`IsBanned` vira false) sem ação manual.
- [ ] Un-ban propaga (tombstone) e some para todos.

---

## 6. Feature 2 — Auto-invite (estende RecruitmentSystem)

### 6.1 Racional de simplificação
Gatilho é **whisper** (`ginv`). Whisper é 1:1 → só o oficial sussurrado recebe o `CHAT_MSG_WHISPER`,
logo **não há duplicação entre oficiais** e o padrão `_welcomeIntents` **não é necessário** aqui.

### 6.2 Config
```
db.recruitment.autoInvite = {
  enabled     = false,
  keyword     = "ginv",     -- match case-insensitive; exato ou "começa com"
  minLevel    = 0,
  classes     = {},          -- vazio = qualquer
  races       = {},          -- vazio = qualquer
  cooldownSec = 300,         -- não re-convidar o mesmo nome dentro disso
  whoFallback = "skip",      -- "skip" | "invite" quando /who não retorna
  officerOptIn= <tri-state>, -- igual ao re-post existente
}
```

### 6.3 Fluxo (`CHAT_MSG_WHISPER`)
1. `enabled` + keyword bate + `IsInGuild()` + eu sou oficial c/ `CanGuildInvite()` + opt-in ligado.
2. `BanList:IsBanned(sender)` → se banido: **rejeita**, alerta oficiais, opcional `/w` "não liberado". Fim.
3. Cooldown: se `sender` convidado há < `cooldownSec` → ignora.
4. **Filtros** (se `minLevel>0` ou `classes`/`races` não vazios):
   - `SetWhoToUI(1)` (resultado na API, não no Social frame) + `SendWho('n-"'..sender..'"')`.
   - Enfileira (um `/who` por vez; throttle Blizzard ~5s) com timeout.
   - No `WHO_LIST_UPDATE`: lê nível/classe/raça do resultado exato; checa filtros.
   - Sem resultado/timeout → `whoFallback` (`skip` = não convida; `invite` = convida assim mesmo).
   - Sem filtros setados → pula direto pro passo 5.
5. `GuildInvite(sender)`; marca cooldown; `BRutus:Print` discreto de confirmação.

### 6.4 UI / comandos
- Config na aba **Settings → Recruitment** (ou sub-seção do painel de recrutamento): toggle enabled,
  keyword, filtros, cooldown, whoFallback, opt-in.
- `/gos autoinvite on|off` · `/gos autoinvite config` (abre painel) · `/gos autoinvite keyword <txt>`.

### 6.5 Edge cases
- Múltiplos whispers do mesmo nome em sequência: cooldown protege.
- Player já na guild sussurra keyword: `GuildInvite` falha silenciosamente; opcional detectar e `/w`.
- `/who` desligado por outra sessão/UI: usar fila própria + timeout; nunca travar.
- Filtro pede dados que `/who` não traz (raça em alguns clientes): tratar ausente como "não bloqueia"
  se `whoFallback = invite`, senão skip.

### 6.6 Aceitação
- [ ] Whisper `ginv` de não-banido dentro dos filtros → convite automático.
- [ ] Whisper `ginv` de banido → **sem convite** + alerta.
- [ ] Filtro de nível/classe barra quem não passa (com `whoFallback=skip`).
- [ ] Cooldown impede convite repetido.
- [ ] Oficial sem opt-in não dispara nada.

---

## 7. Feature 3 — Event Log / RosterLog (`audit`)

### 7.1 Detecção (duas fontes combinadas)
- **CHAT_MSG_SYSTEM** via globais localizados → dá **o ator**:
  - `ERR_GUILD_JOIN_S` (join), `ERR_GUILD_LEAVE_S` (leave),
  - `ERR_GUILD_REMOVE_SS` (kick: alvo + ator), `ERR_GUILD_PROMOTE_SSS`, `ERR_GUILD_DEMOTE_SSS`.
  - Construir patterns com `gsub("%%s","(.+)")` como o welcome já faz; fallback PT/EN.
- **Roster diff** no `GUILD_ROSTER_UPDATE` → o que não emite system msg: **level-up**, **note change**,
  e fallback para join/leave (sem ator).

### 7.2 Modelo
```
event = {
  id     = <hash estável: bucket(ts, 5s) .. type .. target .. (actor or "")>,
  type   = "join"|"leave"|"kick"|"promote"|"demote"|"levelup"|"note"|"return",
  target = "Playername",
  actor  = "OfficerName" | nil,
  detail = { fromRank=, toRank=, level=, fromNote=, toNote=, ... },  -- conforme o tipo
  ts     = <serverTime>,
}
db.rosterLog = { events... }   -- ring buffer newest-last, cap 1000 / prune > 90d
db.rosterLog_seen = { [id]=true }  -- dedup de armazenamento (cap junto)
```
- **`return`**: se um `join` chega e o `target` tem `leave` anterior no log → marca `return` e linka.

### 7.3 Sync + backfill
- Domínio `audit` officer-only. Evento novo (após dedup local por `id`): `Publish("audit","add", event)`.
- Handler aplica se `id` não visto (dedup de armazenamento). `IsDuplicate` do transporte ajuda antes.
- **Backfill no login** (throttled, respeitando cold-login timing):
  - Após inicialização estável, oficial envia `audit/backfill_req` com `sinceTs = último ts local`.
  - Peer(s) respondem `audit/backfill_resp` com eventos `ts > sinceTs` que têm (cap por resposta, ex. 100).
  - Requester aplica com dedup por `id`. Throttle evita request storm (bound como no mesh).

### 7.4 Absorção do managementLog
- `RosterLog` passa a receber as ações via addon que hoje vão pro `managementLog` (motd/info/kick via
  addon): `GuildManager:LogAction` delega a `RosterLog:Record(...)` (ou RosterLog observa os mesmos pontos).
- Migração única: importar `db.managementLog` existente pro `db.rosterLog` no primeiro load (marcado por
  schema version), depois descontinuar o antigo.

### 7.5 UI
- Sub-aba **History → "Audit Log"** na Leadership: lista newest-first com ícone/cor por tipo, filtro por
  **tipo** e por **membro**, busca por texto, e faixa de data. Ator exibido quando presente
  ("kickado por X"). Botão limpar (officer, local).
- **Digest**: o login digest ("desde seu último login") passa a puxar contagens do RosterLog
  (novos membros, saídas, kicks, promoções).

### 7.6 Cap + prune
Ring buffer 1000 eventos e/ou prune > 90 dias (o que vier primeiro), via `PruneStaleData` estendido.
`rosterLog_seen` podado junto (só mantém ids dentro da janela).

### 7.7 Stretch condicional — troca de nome
Só implementar se `GetGuildRosterInfo` expuser **GUID estável** no cliente 2.5 Anniversary. Se sim:
chavear membros por GUID e reconciliar renomeações (linkar histórico antigo ao novo nome). Senão, **cortar**.

### 7.8 Aceitação
- [ ] Kick por um oficial → evento `kick` com `actor` correto registra e sincroniza.
- [ ] Join/leave/promote/demote/level-up/note aparecem no log.
- [ ] Login após período offline → backfill traz eventos perdidos (sem duplicar).
- [ ] Digest reflete contagens do RosterLog.
- [ ] managementLog antigo migrado uma vez; sem histórico duplicado.
- [ ] Log respeita cap/prune (SavedVariables não cresce sem limite).

---

## 8. Transversais

- **Permissão**: as duas sub-abas e os comandos de escrita são officer-only (`IsOfficerByName` /
  `officerMaxRank`), consistente com a Leadership.
- **API 20505**: `C_Timer`/`C_GuildInfo` via `Compat`; nil-check em todo `GetGuildRosterInfo`;
  `/who` em fila com throttle; `SetWhoToUI(1)` p/ não abrir o Social frame; patterns de system msg
  com fallback PT/EN.
- **SavedVariables**: `banList` e `rosterLog` com cap + prune obrigatórios.
- **Localização**: chaves novas em `enUS` (master) + `ptBR`, `esES`, `deDE`, `frFR`.
- **Resiliência**: hooks dentro de `SafeCall`; erros no ring buffer de sessão.

## 9. Sequência de entrega

1. **BanList (`M`)** — fundação; destrava o gate do auto-invite. Shippa sozinho.
2. **Auto-invite (`S-M`)** — usa `BanList:IsBanned`. Shippa sozinho.
3. **RosterLog (`L`)** — peça grande e independente; entra por último.

Cada fase é um incremento testável e lançável.

## 10. Riscos

- **Cobertura do audit** depende de oficiais-com-addon online (aceito — ver §4).
- **`/who` throttle** pode atrasar auto-invite com filtro; mitigar com fila + fallback claro.
- **Crescimento de SavedVariables** no rosterLog; mitigado por cap/prune.
- **GUID incerto** no 2.5 → reconciliação de nome é stretch, não bloqueia nada.
- **Versão mista na guild**: domínios novos passam pelo envelope v2 (rev/dedup/ACK), então
  clientes antigos simplesmente ignoram; sem corrupção.

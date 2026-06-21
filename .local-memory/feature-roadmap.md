# Guild OS — Feature Roadmap (planejamento pesado)

_Draft: 2026-06-20. Planejamento de novas funções para aumentar a utilidade do
addon para guilds. Cada item traz: valor, encaixe nos módulos atuais,
viabilidade no cliente TBC Anniversary (20505), implicações de sync/permissão e
esforço (S = 1-2 dias, M = ~1 semana, L = 2-3 semanas, XL = 1 mês+)._

---

## 0. Princípios de seleção

Uma feature "encaixa" no Guild OS quando ela:
1. **Aproveita dados que já sincronizamos** (gear, profissões, atunamentos, presença, loot) — valor marginal alto, custo baixo.
2. **Reduz dependência de ferramentas externas** (Google Sheets, Discord raid-helper, sites de DKP). Esse é o maior diferencial competitivo.
3. **Respeita o split oficial/membro** já existente.
4. **É viável na API 20505** (sem calendário nativo garantido, sem leitura de players sem o addon, SendChatMessage a canais exige clique).
5. **Não estoura o SavedVariables** — histórico precisa de cap/prune.

---

## 1. PRÉ-REQUISITO CRÍTICO (bloqueia o Tier S)

> **SyncService v2 — versionamento de protocolo + dedup + revision + ACK**
> (já previsto em ADR-0012 / ADR-0010 / sync-protocol.md "Protocolo v2")

**Por que vem antes:** todas as features-âncora abaixo (DKP, Calendário/Signups,
Guild Bank) **escrevem estado compartilhado entre clientes**. Sem envelope
versionado, dedup por messageId e revision-check, uma guild com versões mistas do
addon pode **corromper dados** (uma award de DKP ou um RSVP chega fora de ordem e
sobrescreve o estado correto). Hoje o protocolo v1 não carrega versão nem revision.

**Escopo mínimo para destravar o Tier S:**
- Envelope v2 (`v, id, av, dom, act, ts, rev, pv, src, data`) — já desenhado.
- Dedup por `messageId` (circular buffer 500).
- `ShouldApply(domain, key, rev)` por revision counter.
- **ACK/NACK para mensagens críticas** (award de DKP, delete de evento) — sem isso, perde-se award em disconnect.
- Enum central de MSG_TYPES (mata as magic strings do ADR-0010).

**Esforço:** L. **É o investimento que habilita 80% do resto.**

---

## 2. TIER S — Features-âncora (alto valor, definem o produto)

### S1. Sistema de Pontos de Loot (DKP / EPGP / Loot Council) ⭐
**O quê:** uma economia de loot real como alternativa/complemento aos rolls MS/OS
do LootMaster. Modos configuráveis: **DKP** (ganha por presença/boss, gasta em
item), **EPGP** (effort/gear ratio) ou **Loot Council** (pontos só informativos).
- Award automático por: boss morto, presença na sessão (já temos RaidTracker), on-time bonus.
- Decay configurável (ex: -10%/semana).
- Standings ordenáveis; histórico de transações com motivo e autor.
- **Integra direto no LootMaster:** ao anunciar item, mostra DKP/EP de cada interessado e a wishlist junto.

**Encaixe:** novo `Modules/Points.lua` + `UI/PointsPanel.lua`; consome
`RaidTracker` (presença/boss) e alimenta `LootMaster` (decisão).
**Viabilidade 20505:** total (lógica local + sync). **Sync:** domínio `points`
(award/spend/decay/snapshot), **officer-only**, **ACK obrigatório**.
**Permissão:** escrita oficial; leitura todos.
**Esforço:** XL. **Depende do SyncService v2.**
**Diferencial:** elimina addons de DKP externos (CEPGP etc.) e centraliza no mesmo hub.

### S2. Calendário de Raids + Signups (RSVP) ⭐
**O quê:** quadro de eventos in-game. Oficial cria raid (data/hora/instância/tamanho);
membros marcam **Yes / No / Tentative** com **spec e role**. Oficial vê a
**composição montada em tempo real** (tanks/heals/dps, buffs/cooldowns faltando via RaidTools).
- Lembrete no login / X horas antes.
- "Confirmados vs faltando atunamento/consumível" puxando do Readiness (S4).
- Export do roster do evento para colar no Discord.

**O problema que resolve:** TBC não tinha calendário nativo confiável; guilds
dependem de bots de Discord. Para quem tem o addon, isso vira nativo.
**Encaixe:** `Modules/Calendar.lua` + `UI/CalendarPanel.lua`; reusa RaidTools (comp) e Readiness (S4).
**Viabilidade 20505:** **verificar `C_Calendar` no cliente 2.5** — se existir, dá
para ler eventos nativos; **independente disso, o board sincronizado via addon é o
caminho robusto** (funciona para todos com o addon, sem depender da API).
**Sync:** domínio `event` (create/update/rsvp/delete), criação **officer-only**, RSVP **todos**, ACK no create/delete.
**Esforço:** L. **Depende do SyncService v2.**

### S3. Rastreador de Banco de Guild (Guild Bank) ⭐
**O quê:** snapshot + log do banco de guild, **pesquisável fora do banco**.
- Inventário completo por aba, busca por nome de item ("temos Flask of Relentless Assault? quantos?").
- **Log de transações** (quem depositou/sacou o quê e quando) — auditoria.
- Histórico de ouro do banco.
- Opcional: "lista de compras" / níveis-mínimo de consumível para raid.

**O problema que resolve:** o banco de guild do TBC não tem busca nem visão fora do prédio.
**Encaixe:** `Modules/GuildBank.lua` + `UI/GuildBankPanel.lua`; scaneia em
`GUILDBANKFRAME_OPENED` / `GUILDBANKBAGSLOTS_CHANGED`.
**Viabilidade 20505:** **alta** — `QueryGuildBankTab`, `GetGuildBankItemInfo/Link`,
`GetNumGuildBankTabs`, `GetGuildBankTransaction` existem no BCC. Coleta acontece
quando **qualquer** membro com o addon abre o banco; o snapshot é compartilhado.
**Sync:** domínio `guildbank` (snapshot) — quem abriu publica; leitura todos.
**Esforço:** L (a UI de grid de itens é o grosso).

### S4. Relatório de Prontidão de Raid (Raid Readiness) ⭐ (melhor custo/benefício)
**O quê:** uma tela única "**a raid está pronta?**" que **agrega dados que já
coletamos**: atunamento da instância-alvo + enchants faltando (GearAudit) +
consumíveis (ConsumableChecker) + spec/talentos (SpecChecker) + iLvl mínimo +
durabilidade/repair. Semáforo verde/amarelo/vermelho por membro e um resumo do grupo.
- "Quem **não** está atunado para BT?" como query guild-wide.
- Botão "**cobrar no /w**" template para os pendentes.

**Por que é o melhor ROI:** é majoritariamente **agregação de módulos existentes** —
pouca infra nova, sem depender do SyncService v2.
**Encaixe:** `Modules/Readiness.lua` (puro agregador) + aba em `AuditPanel`/`RaidToolsPanel`.
**Viabilidade 20505:** alta (tudo local a partir do db já sincronizado).
**Sync:** nenhum novo (lê o que já existe). **Esforço:** M. **Sem dependência de infra. Bom primeiro entregável.**

---

## 3. TIER A — Alto valor, esforço médio

### A1. Analytics de Presença (histórico e tendências)
Gráfico de presença por membro ao longo do tempo, **heatmap de noites de raid**,
streaks, "faltou as últimas N", ranking de presença. Já temos os dados de sessão; falta a visão.
**Encaixe:** estende `RaidTracker` + nova sub-aba. **Esforço:** M.

### A2. Banco/Rotação justa (Bench Manager)
Registra quem ficou de fora e quantas vezes; sugere rotação justa; integra com signups (S2).
**Encaixe:** `RaidTracker`/`Points`. **Esforço:** M.

### A3. Equidade de Loot (Loot Value Report)
A partir do LootTracker: itens recebidos por jogador, "epics por raid", valor relativo,
sinaliza quem está acima/abaixo da média. (Existe penalidade de recebido-no-lockout no
LootMaster — aqui é a visão histórica completa.)
**Encaixe:** `LootTracker` + aba. **Esforço:** M.

### A4. Diretório de Crafting + Quadro de Pedidos
Reverse-lookup "**quem cria [item]**?" (já temos receitas), com lista de reagentes;
**pedido de craft/enchant** que notifica o crafter. Casa com o **Enchant Audit**:
"faltando enchant de costas → pedir ao Encantador X".
**Encaixe:** `RecipeTracker` + `GearAudit` + pequeno sistema de requests (sync `craftreq`).
**Esforço:** M (L se incluir fila de pedidos sincronizada).

### A5. Digest de Login / Notificações
Ao logar: "**Desde seu último login:** 2 novos membros, 3 trials vencendo, 5 itens
lootados, 1 raid agendada para hoje." Centro de notificações com badges nas abas.
**Encaixe:** transversal; novo `Modules/Notifications.lua`. **Esforço:** M.

### A6. Export/Import estruturado (CSV / Discord)
Já existe `ShowExportPopup`. Expandir: export de presença, loot, standings de DKP e
roster em **CSV** (Google Sheets) e em **bloco formatado para Discord**.
**Import** de DKP/roster externo. **Esforço:** S-M. **Sem dependência. Quick win.**

---

## 4. TIER B — Bom valor, oportunista

| # | Feature | Resumo | Encaixe | Esforço |
|---|---|---|---|---|
| B1 | Enquetes / Votação | Oficial cria poll (horário de raid, kick, etc.), membros votam, resultado sincronizado | `Modules/Polls` (sync `poll`) | M |
| B2 | Mural / Avisos no login | Oficiais postam avisos que aparecem ao entrar | reusa OfficerNotes/sync | S-M |
| B3 | Marcos e aniversários | Level 70, atunamento concluído, "entrou há 1 ano" → anúncio opcional na guild | DataCollector + GuildManager | S |
| B4 | Late/leave tracker fino | Hora exata de entrada/saída por snapshot, não só penalidade | RaidTracker | S |
| B5 | Log de mortes/wipes | Primeira morte, repair médio por noite, wipes por boss | novo parser leve (cuidado perf) | M |
| B6 | Custos (repair/consumo) | Estimativa de gasto por raid por membro | LootTracker/RaidTracker | S |
| B7 | Pipeline de recrutamento | Aplicações in-game, templates de /w, status (novo > trial > membro) | estende TrialTracker | M |

---

## 5. TIER C — Polimento / QoL

- **C1. Filtros salvos + colunas customizáveis + presets de ordenação** no roster. (S)
- **C2. Backup/restore do DB** (export/import completo, à prova de wipe acidental). (S)
- **C3. Planner de cooldowns de raid** (rotação de Bloodlust/Battle Rez/Innervate) sobre o RaidHUD. (M)
- **C4. Temas/cores configuráveis** (já há tech-debt de separar Theme em Helpers — bom momento). (S)
- **C5. Command palette / busca global** (`/gos find <qualquer coisa>`). (S)

---

## 6. Sequenciamento sugerido (releases)

| Release | Conteúdo | Racional |
|---|---|---|
| **v0.5 — "Readiness"** | **S4** (Readiness) + **A6** (Export) + **C1/C2** | Entregas de alto valor **sem** depender de infra de sync; ganha tração e feedback. |
| **v0.6 — "Sync v2"** | **Pré-requisito** SyncService v2 (envelope, dedup, revision, ACK) | Investimento de plataforma. Pouco visível mas destrava o resto; reduz risco de corrupção. |
| **v0.7 — "Loot Economy"** | **S1** (DKP/EPGP) + **A3** (equidade) + **A2** (bench) | Feature-âncora #1; transforma o LootMaster em sistema de loot completo. |
| **v0.8 — "Calendar"** | **S2** (Calendário/Signups) + **A1** (analytics) + **A5** (digest) | Substitui o raid-helper de Discord; sinergia com Readiness. |
| **v0.9 — "Vault"** | **S3** (Guild Bank) + **A4** (crafting/pedidos) | Auditoria de banco + economia de profissões. |
| **v1.0** | **B1–B7** selecionados + **C3–C5** + estabilização | Fechamento "comercial". |

> Alternativa "valor primeiro, infra depois": dá para fazer **S4 + A6** já (v0.5)
> porque não tocam no protocolo. Mas **não** comece S1/S2/S3 antes do Sync v2 —
> seria construir sobre fundação que sabemos que vai mudar.

---

## 7. Riscos transversais

1. **Dependência de adoção:** quase tudo sincronizado só funciona para quem tem o
   addon. Mitigar com: digest que incentiva instalação, "X/Y da guild usa Guild OS",
   e features de valor solo (Readiness funciona mesmo só pra você ver seu db).
2. **Crescimento do SavedVariables:** presença histórica, loot, eventos, log de banco
   crescem sem parar. **Cada novo domínio precisa de cap + prune** (já temos `PruneStaleData` para estender).
3. **Versão mista na guild:** sem Sync v2, adições de domínio podem colidir/corromper. (ver §1)
4. **SendChatMessage a canais exige clique** (anúncios de DKP/raid em /1 precisam de popup, como o recrutamento já faz).
5. **Performance de parsers** (log de mortes/wipes): manter leve, gated por "em raid", sem hook pesado de combat log fora de raid.
6. **C_Calendar incerto no 2.5:** não apostar nele; o board sincronizado é o plano A.

---

## 8. Top 3 recomendações (se for escolher pouco)

1. **S4 Readiness** — melhor ROI imediato, zero infra nova, usa tudo que já coletamos.
2. **SyncService v2** — não é "feature" mas é o que torna DKP/Calendário/Banco possíveis com segurança.
3. **S1 DKP/EPGP** — a feature-âncora que mais diferencia de "só um roster bonito" para "o sistema de gestão da guild".

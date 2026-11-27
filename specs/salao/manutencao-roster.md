# Manutenção do roster (comparação com o GRM)

Quatro coisas que o Guild Roster Manager faz e que os oficiais de uma guilda grande pediam: uma auditoria dos dados
de cada membro, o tempo no rank e na guilda, a inatividade contada por jogador (não por personagem) e a busca nas
notas. E, junto, mais colunas na exportação do roster. Tudo é calculado do que o addon já tem e já sincroniza
(histórico de membros #425, vínculos de alt #424, notas que o jogo entrega, apelidos #429): **nada novo é guardado
nem enviado**, nenhum domínio novo no SyncService.

A lógica fica em `Modules/RosterMaint.lua` (sem frames); as telas só chamam o módulo.

## 1. Auditoria de dados (Sala dos Oficiais › Membros › Auditoria de dados)

Entrada nova `audit` em `UI/Rooms.lua` (grupo Membros, depois de "Notas e marcas") e sub-aba em
`UI/ManagementPanel.lua`; a tela é `UI/DataAuditPanel.lua`. Só oficiais (a sala já é dos oficiais, e
`RosterMaint:Audit` devolve vazio para quem não é).

Um card de papel que preenche a tela (`board:Card(..., { fill = true })`): a explicação, os **chips** por problema
com a contagem (Todos, Sem data de entrada, Sem alt vinculado, Data da nota diverge), a **busca** (nome, rank ou
apelido) com "Atualizar", a linha de estado ("N de M membro(s) com algo a corrigir · verificado HH:MM"), o
**cabeçalho de tabela** (Forms/`UI:CreateTableHeader`, Cinzel no vermelho do papel) e a lista virtual
(`UI.MakeVirtualList`, só as linhas que cabem). Linha de 40 px (`Forms.TODO_H`): avatar da classe, nome na cor da
classe com o apelido, rank e nível; embaixo, em tinta suave, o que está errado. À direita: "Entrou" (só a partir de
640 px de lista), "No rank" (dias) e os botões de ação. Clicar na linha abre a janela do membro; passar o mouse
mostra desde quando está no rank, quando entrou e os problemas. Estado vazio: `UI:CreateEmptyState` centrado.

Colunas que ordenam (clique de novo inverte; quem não tem valor vai por último nos dois sentidos): Membro,
No rank, Entrou (`RosterMaint.Sort`).

| Problema | Regra (`RosterMaint.Classify`) | Ação |
|---|---|---|
| Sem data de entrada | o histórico não tem início da passagem atual, ou só tem o "visto pelo Guild OS" (`joinEst`) que não veio de uma nota | **Escrever data**: abre Notas e marcas com o membro já na caixa (`NoteDates:Prefill`) — o fluxo existente de datas nas notas, incluindo "Ler datas das notas" |
| Sem alt vinculado | nem é alt de ninguém nem tem alts (`db.altLinks`) | **Vincular alt…**: abre a janela do membro com o cursor na caixa "Adicionar alt" (`ShowMemberDetail(rec, "alt")`) |
| Data da nota diverge | o histórico tem data real (exata, ou lida de uma nota) e a nota pública ou de oficial traz outro dia (`NoteDates.Parse`) | **Corrigir nota**: `NoteDates:WriteOne(nome, nil, nota)` na nota que diverge, que pergunta antes de substituir |

A nota de oficial só é lida por quem pode (`Compat.CanViewOfficerNote`); sem isso a tela avisa que só as públicas
são comparadas. Uma nota que chega como Secret Value (WoW: Forever) vale "" (`RosterMaint.NoteText`, via
`Compat.IsSecret`).

Em lista estreita (< 640 px) cada linha mostra só uma ação (a do primeiro problema, ou a do chip ativo) e a coluna
"Entrou" sai, para o nome caber.

**Desempenho:** uma passada no roster com consultas em tabela (o índice de alts é montado uma vez, nunca
`GetLinkedChars` por membro, que percorre todos os vínculos). O resultado fica em cache por 20 s enquanto o roster
não muda de tamanho; as ações e "Atualizar" invalidam (`RosterMaint:Invalidate`). Busca e chips só filtram o cache.

## 2. Tempo no rank e na guilda

- **Desde quando no rank** (`RosterMaint.RankSinceOf`): a última mudança de rank do histórico quando é da
  passagem atual; senão, o início da passagem. "~" quando é só quando o Guild OS viu.
- **Membros:** coluna opcional "No rank" (`rankSince`, em Colunas; só oficiais, com o histórico), ordenável, à
  direita, "~" para estimativa. O tooltip da linha diz "No rank desde AAAA-MM-DD (N dias)". Não entra no padrão
  das colunas: o layout do redesenho de Membros não muda.
- **Ações em massa:** regras novas `rankDaysMin` ("No rank há pelo menos") e `tenureDaysMin` ("Na guilda há pelo
  menos", `MemberHistory:TenureDays`, todas as passagens), um par de campos abaixo de Nível/Presença. Tempo
  desconhecido não satisfaz a regra. `BulkActions:Collect` leva `rankDays` e `tenureDays` em cada linha.
- **Predefinição pronta:** "Promover após dias no rank" (`promote_rank_time`: rank, dias no rank e, 0 = sem regra,
  dias na guilda), promoção pela fila das Ações em massa como as outras (nunca trial nem rank de oficial). Semeada
  numa guilda nova e acrescentada uma vez (`modPresetsRankTime`) numa guilda antiga. Os campos da predefinição
  quebram linha quando a tela é estreita; o seletor "+ Novo" também.
- **Sugestões:** card "No rank há N+ dias" (`RosterMaint:StuckInRank`, padrão 90 dias, até 25, o mais antigo
  primeiro), só para quem pode promover; nunca trial, oficial, nem quem subiria para um rank de oficial. Botão
  Promover = `GuildManager:Promote` (fila, um clique).

## 3. Inatividade por jogador

- **Configuração** na tela de Inatividade: "Contar os alts do jogador" (`inactiveCountAlts`, ligada por padrão).
  Ligada, um personagem não é inativo se o principal ou outro alt do mesmo jogador entrou dentro dos N dias
  (`GuildManager:GetInactiveMembers(days, countAlts)`).
- Cada linha da lista diz, embaixo do nome, qual outro personagem do jogador foi visto por último ("principal
  Xyz visto há 2d", `RosterMaint.SeenText`). Linha de 36 px.
- `RosterMaint.GroupSeen`: uma passada, os dois mais recentes de cada grupo; devolve, para cada membro, o outro
  personagem mais recente do grupo e o principal do grupo.
- **Ações em massa / predefinição de expurgo:** a regra de dias lê o jogador quando a configuração está ligada
  (`rules.countAlts`, `m.playerDays`); a fila confere de novo a cada clique (um alt que entrou depois livra o
  personagem).
- **"Remover o grupo inteiro só quando todos os personagens estiverem inativos"** (`bulkWholeGroup`, desligada,
  só aparece na remoção): numa remoção por dias, o grupo de quem casou vai junto, e só se todos os personagens dele
  no roster estiverem fora há os dias; os que vieram pelo grupo ficam marcados (`viaGroup`, "com seu grupo") e a
  cada clique só se confere que o grupo continua todo fora.

## 4. Busca nas notas

O filtro de Membros e a busca global (`Modules/Search.lua`) também casam a nota pública, a nota de oficial (só
para quem pode ler), o nome do principal e o apelido (`MemberMarks:Nick`), por `RosterMaint.MatchVia`. Um resultado
que veio por aí diz por quê: em Membros, uma etiqueta suave depois do nome ("· nota", "· nota de oficial",
"· apelido", "· Alt de Xyz"); na busca global, na linha de contexto, e depois dos que casaram pelo nome.

## 5. Exportação do roster

`Exporter:RosterData` ganha, no fim: `Main` (o principal de um alt), `JoinDate` (AAAA-MM-DD, "~" quando visto),
`DaysInRank`, `PublicNote` e, só para quem lê notas de oficial, `OfficerNote`. Tabulações e quebras de linha das
notas viram espaço (o TSV e o formato do Discord cortam nelas).

## Testes

- `tools/roster-audit.lua` (novo): regras puras (dias, desde quando no rank, grupos, classificação, filtro,
  contagem, ordenação por cada coluna, `MatchVia`), a auditoria no roster (contagens, permissão da nota de oficial,
  cache e invalidação, não-oficial vazio), as ações chamando os fluxos existentes, as regras de tempo, a
  predefinição (semeada uma vez), a sugestão (só com permissão de promover), a inatividade por jogador e o grupo
  inteiro (inclusive a reconferência na fila), a busca global e as colunas da exportação.
- Estendidos: `tools/bulk-actions.lua` (regras de tempo e alts), `tools/mod-presets.lua` (predefinição nova),
  `tools/roster-table.lua` (coluna "No rank", tooltip, busca por nota/oficial/principal/apelido),
  `tools/search-strip.lua` (busca global por nota, permissão), `tools/retail-leftovers.lua` (colunas novas),
  `tools/officer-cards.lua` (a tela nova nas duas larguras). `tools/room-cards.lua` já abre toda entrada de toda sala.

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

## 6. Ex-membros (Sala dos Oficiais › Membros › Ex-membros)

Quando alguém sai, o Guild OS apaga os dados de membro atual (`DropDeparted` em `Core/Utils.lua`: a linha de
`members`, `firstSeen`, profissões, receitas, lista de desejos, aniversário, selo de fundador), mas guarda o histórico
de passagens (`Modules/MemberHistory.lua`: entradas e saídas com como e por quem, mudanças de rank, nota permanente,
classe vista por último), as notas de oficial (ficha e notas datadas), os trials, a lista de banidos, os vínculos de
alt, presença e saque de raide e o registro de auditoria. Até aqui só havia a exportação CSV ("Ex-membros" em
Exportar). Esta tela lê tudo isso; **nada novo é guardado nem enviado**.

Entrada `former` em `UI/Rooms.lua` (grupo Membros, depois de "Auditoria de dados") e sub-aba em
`UI/ManagementPanel.lua`; a tela é `UI/FormerMembersPanel.lua`, a lógica `Modules/FormerMembers.lua` (sem frames).
Só oficiais (`FormerMembers:Rows` devolve vazio para quem não é; as ações também conferem).

**A lista** (`FormerMembers:Rows`): uma linha por chave que o histórico diz que saiu e não voltou
(`MemberHistory:Former()`, a última passagem fechada). Cada linha: nome na cor da classe que o histórico guardou (sem
classe, a tinta do papel), data da última saída ("~" quando só foi vista por um diff) e "há N dias", como saiu
("saiu", "removido por X", "saiu ou foi removido" e, com banimento em vigor na lista de banidos, "banido" ou
"suspenso até DD/MM/AAAA"), número de passagens, dias na guilda somando todas (`MemberHistory:TenureDays`), "tem
notas" (nota permanente, ficha de oficial ou nota datada) e "tem alts" (é alt ou principal de alguém em
`db.altLinks`).

**Chips com contagem**: Todos, Saiu, Removido, Banidos — os três últimos dividem a lista (banimento primeiro, depois
remoção, senão saída; `FormerMembers.KindOf`) — e Com notas, que corta a lista. **Busca** pelo nome, pela nota
permanente, pela ficha e pelas últimas notas datadas. **Ordenação** pelo cabeçalho: Saiu (padrão, a mais recente
primeiro), Membro (nome) e Dias; clicar de novo inverte; quem não tem valor vai por último nos dois sentidos.

**Ações em cada linha** (cada uma é o fluxo que já existe):

| Ação | O que faz |
|---|---|
| Clique na linha | Abre a janela do membro (`ShowMemberDetail`) com um registro de ex-membro (`FormerMembers:Record`, `former = true`) |
| Banir… | Pergunta o motivo; sim bane para sempre o grupo inteiro de personagens (`BanList:AddGroup` com `GetLinkedChars`) |
| Desbanir (no lugar de Banir… quando há banimento) | Pergunta ("Remover o banimento de X?"); sim levanta os banimentos em vigor de todo o grupo (`BanList:RemoveKey`) |
| Convidar de volta | Primeiro `BanList:HoldInvite` (banimento da guilda ou da aliança pede "Convidar mesmo assim"; sem banimento, o chat diz quando foi membro). No WoW: Forever nenhum addon convida: a linha `/ginvite Nome` para copiar (`ActionQueue:OfferTyped`). No TBC Anniversary e no retail, `ActionQueue:Add(..., true)`: o clique é o evento de hardware que `C_GuildInfo.Invite` pede |
| Esquecer | Pergunta pela caixa padrão do addon; sim apaga a entrada do histórico (passagens, ranks, classe e nota permanente) e os registros dela na caixa de saída (`memberHistoryOut`), para o backfill do login não reenviá-los |

**Esquecer é só local, e a pergunta diz isso.** O histórico sincroniza entre oficiais como registros só de
acréscimo (domínio `audit`, ação `hist`) e a nota por revisão (`hnote`): não existe mensagem de apagar, então os
outros oficiais mantêm a cópia deles, e um registro ou nota que mandarem depois pode trazer parte de volta.
Banimentos, notas de oficial e vínculos de alt ficam. Um membro presente nunca é esquecido.

**Janela do membro para quem não está no roster** (`UI/MemberDetail.lua`, mudança mínima): com `data.former`, a chave
é a do registro (`DetailKey`), a linha de informação diz "Ex-membro · classe · Saiu da guilda em DD/MM/AAAA" e,
embaixo, o banimento ou a suspensão em vigor com o motivo. Ficam: presença e saque de raide, trial, passagens e nota
permanente, notas de oficial e ficha, advertências e personagens vinculados (a classe de um alt que saiu vem do
histórico). Saem: talentos, atributos, M+ e cofre, equipamento, profissões, sintonizações, lista de desejos, o botão
Advertir, as regras de disciplina e Promover/Rebaixar alts. Antes, nada abria: `GetMemberRecord` devolve nil fora do
roster.

**Layout:** um card de papel que preenche a tela, como a Auditoria de dados; linha de 40 px com avatar, nome e, embaixo,
como saiu, notas e alts. A partir de 700 px de lista: colunas Passagens e Dias e as três ações (Banir…/Desbanir,
Convidar de volta, Esquecer). Mais estreito (a janela de 800 px): só a coluna Saiu, passagens e dias vão para a linha
de baixo, e duas ações (Desbanir quando banido, senão Convidar de volta; e Esquecer). Estado vazio com
`UI:CreateEmptyState` (ninguém saiu ainda, ou o filtro/busca esconde todos).

**Memória e desempenho** (`memoria.md`): lista virtual (`UI.MakeVirtualList`), linhas e botões criados uma vez e
reaproveitados. Uma passada no histórico com consultas em tabela (o índice de alts montado uma vez); resultado em
cache por 20 s, invalidado pelas ações. A tela soma o seu gancho aos da lista de banidos e do registro de auditoria
(`BanList.uiRefresh`, `RosterLog.uiRefresh`, que são das telas Lista de Banidos e Registro de Auditoria, construídas
antes) e ao `FormerMembers.uiRefresh`: escondida, só marca como desatualizada e desenha no `OnShow`.

## 7. Mais do GRM: lista segura com prazo, data do grupo de alts, formatos de data, recomendações no resumo

### 7.1 Lista segura com prazo (`Modules/MemberMarks.lua`, Notas e marcas)

- `MemberMarks:SetSafe(key, on, until)`: `until` opcional (hora do servidor, no futuro, até 5 anos à frente:
  `UNTIL_MAX`); sem ele a marca é para sempre. Marcar de novo com outro prazo troca o prazo.
- `IsMarkedSafe(key, now)` só conta a marca enquanto `u > now`: daí em diante ela não protege em lugar nenhum
  (`BulkActions.Eligible` via `IsSafe` na prévia e no clique, `GuildManager:GetInactiveMembers`, o resumo). A tag
  `[safe]` na nota continua sem prazo.
- Limpeza preguiçosa: `Prune` (no login, em `SafeKeys`, depois de um `Apply` e antes do `Backfill`) apaga a marca
  vencida e guarda o `at` em `rev`, como uma lápide: nenhuma cópia dela (com ou sem prazo) volta.
- Sincronização: o mesmo domínio "marks", com um campo a mais, `u`. Um cliente antigo ignora o campo (para ele a
  marca é para sempre). Este valida ao receber: `u` tem de ser número finito, depois de `t` e no máximo `UNTIL_MAX`
  depois dele, senão a entrada é recusada; numa marca desfeita `u` é descartado; num apelido não existe. No empate de
  `at` (mesmo autor e valor), vence a entrada com o prazo maior: a cópia sem `u` de um cliente antigo nunca apaga o
  prazo.
- Tela: em Notas e marcas, "Segura por" (Para sempre / 7 / 14 / 30 dias / Até uma data) e a caixa "Até" (lida pelo
  mesmo leitor de datas das notas, `MemberMarks.UntilOf`; os N dias vão até o fim do N-ésimo dia). A lista segura
  mostra "marcado à mão, até 15/01" (o ano só quando não é o atual) e a linha tem tooltip; o tooltip do roster diz
  "Na lista segura até 15/01". Comando: `/gos safe <nome> 14d` ou `/gos safe <nome> 15/01/2027`.
- `GuildManager:GetInactiveMembers(days, countAlts, skipSafe)`: cada linha traz `safe` (na lista agora); com
  `skipSafe` os seguros ficam de fora (a contagem do resumo).

### 7.2 Data de entrada para o grupo de alts (`Modules/NoteDates.lua`)

- Quando a data de um principal é escrita na nota (`WriteOne`/confirmação, inclusive "copiar o texto"), importada
  das notas (`ApplyImport`) ou ao fim de uma gravação da guilda toda (uma vez por gravação, todos os principais
  juntos), `NoteDates:OfferAlts` faz **uma** pergunta: aplicar a mesma data aos alts dele sem data real.
- "Sem data real" = passagem aberta sem início, ou só "visto pelo Guild OS" e não lido de nota, e posterior ao dia
  do principal (`NoteDates.AltTakes`). Só principais com data real (a linha do jogo ou um dia de nota) entram.
  `AltOffers`: uma passada no roster e uma nos vínculos.
- Aceita (`ApplyToAlts`): o histórico de cada alt recebe o dia como dia de nota (`MemberHistory:ImportJoin`; a linha
  exata do jogo ainda o substitui) e as notas vão pelo caminho de sempre: uma gravação só das silenciosas (nota vazia
  ou com espaço, 31 bytes); uma nota que perderia texto não é escrita, fica em "Guilda toda", que pergunta mostrando
  a antiga e a nova. Com outra gravação em andamento, só o histórico muda e o chat avisa.

### 7.3 Mais formatos lidos nas notas (`NoteDates.Parse`)

- Lidos: `aaaa-mm-dd`, `dd/mm/aaaa`, `dd.mm.aaaa`, `dd/mm/aa`, e agora `aa-mm-dd` (três números de dois dígitos
  com hífen). `dd-mm-aa` vem primeiro sempre que é um dia real da era do jogo ("15-01-25" é 15 de janeiro de 2025,
  nunca 2015-01-25: a maior parte das guildas escreve assim); `aa-mm-dd` só quando `dd-mm-aa` é impossível
  ("24-01-29": 2029 passa do ano atual, então 29 de janeiro de 2024; "26-02-30": nenhuma das duas, nenhuma data); `mm/dd/aaaa` num cliente dia-primeiro só quando o dia passa de 12 (a regra de sempre: um
  número acima de 12 decide, o resto segue a ordem do idioma ou a escolha do oficial).
- Mês por nome: inglês sempre e o idioma do cliente (os nomes curtos e longos que `GuildOS:LocalDate` usa, de `L`):
  "15 Jan 2025", "15 de jan 2025", "15 de janeiro de 2025", "Jan 15, 2025", "15th of March 2025", "15-Mar-2025",
  "1er janvier 2025", "15 января 2025" (genitivo: um nome curto de 3+ bytes serve de prefixo). Maiúsculas ASCII,
  latinas acentuadas e cirílicas são dobradas (`NoteDates.Fold`). Mês primeiro só com ano de quatro dígitos.
  Marcas CJK: "2025年1月15日", "2025년 1월 15일" (os nomes de mês com dígito do koKR/zhCN ficam para elas).
- A escrita não muda: os quatro formatos de `FORMATS`.

### 7.4 Recomendações no resumo do login (`Modules/Digest.lua`)

- `Digest:Recommendations()`: para quem pode remover, "N para revisar por inatividade" (a inatividade por jogador,
  sem os seguros; substitui ali a linha antiga "N membro(s) inativo(s)", que continua para quem não pode remover);
  para quem pode promover, "N prontos para promoção" (`RosterMaint:StuckInRank(nil, true)`: todos, não só os 25 do
  card). Só com N > 0, só oficiais.
- Fazem parte do resumo de sempre (`Build` pede `recommend`; a tela Atividade, que chama `Collect`, não): no login
  só ao lado de outras novidades (nunca um popup só para elas), por `/gos digest` sempre; com o resumo desligado,
  nada.
- Cada linha é clicável (um botão sobre ela, do mesmo pool do popup: redesenhar não cria frames): fecha o resumo e
  abre a Sala dos Oficiais em Inatividade ou em Sugestões (`Digest:OpenRecommendation`).

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
- Ex-membros: `tools/former-members.lua` (novo; carrega o addon inteiro sob o cliente de teste de
  `tools/officer-cards.lua`): a lista a partir do histórico, banimentos, notas e alts; contagens, filtros, busca e as
  três ordenações; cache e só oficiais; Banir… no grupo com o motivo, Desbanir, Convidar de volta (Forever: a linha
  para copiar; Anniversary: o convite no clique; banido: retido com "Convidar mesmo assim"), Esquecer (a pergunta diz
  que é local; apaga histórico, nota e caixa de saída; nunca um membro presente); a janela do membro para uma chave
  fora do roster, sem erro e sem as seções de membro atual; a tela (chips, busca, clique na linha, botões, estado
  vazio). Estendidos: `tools/officer-cards.lua` (a entrada `former` nas duas larguras, com ex-membros de exemplo) e
  `tools/frame-leaks.lua` (a tela redesenhada, os ganchos de banimento e de mudança, e a janela do ex-membro aberta
  repetidas vezes: nenhum frame novo).
- Mais do GRM (seção 7): `tools/note-dates.lua` (cada formato novo e as regras de ambiguidade, nomes de mês em
  ptBR/ruRU/frFR, o grupo de alts: quem entra, a pergunta única, só as notas silenciosas, 31 bytes, importação e fim
  de gravação; marcas com prazo: `UntilOf`, fim, tooltip, ações em massa e inatividade, limpeza com `rev`,
  validação do `u` recebido, cópia sem `u` de cliente antigo, backfill, comando), `tools/roster-audit.lua` (prazo
  na inatividade por jogador e na remoção) e `tools/digest-recommendations.lua` (novo: as duas linhas, permissões,
  N = 0, membro, login sem outras novidades, resumo desligado, clique abre a tela, pool sem frames novos).

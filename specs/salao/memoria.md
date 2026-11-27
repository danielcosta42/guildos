# Memória (auditoria de memória)

O mantenedor viu ~150 MB de memória do addon. A causa principal: listas que, a cada redesenho, criavam
frames novos para cada linha e só escondiam os antigos. O cliente nunca libera um frame, uma textura ou um
texto; a lista crescia a sessão inteira, e várias redesenhavam mesmo escondidas.

## A regra

- Uma tela que redesenha reaproveita o que desenhou: um pool por lista (criado sob demanda, reusado pela
  posição, o que sobra escondido) ou partes feitas uma vez e preenchidas de novo.
- Um formulário inteiro só é refeito quando muda de forma (`shapeOf` das Configurações) ou quando o que mostra
  mudou (a assinatura da aba Regra do Saque e das configurações do Core); senão só atualiza os valores.
- Todo gancho `uiRefresh` olha `IsVisible()` (não `IsShown()`, que é verdadeiro sob a janela fechada):
  escondida, a tela não desenha; o `OnShow` desenha o que chegou.
- Um redimensionamento desenha uma vez, quando o tamanho para (0,25 s), não a cada passo do arraste.

## Onde

Conselho de saque (o relógio de 1 s), Raides (sessões e presença), inscrição em cores, Trials, predefinições
de moderação, auditoria, aba Regra do Saque, configurações de pontos, Configurações (uma página por forma,
guardada), Calendário (o dia), ficha do membro (barra de talentos, atributos, ícones, barras), listas de
desejos da guilda, Resumo do login, Análise da guilda, Scanner de recrutamento e Cores.

## Passagem pelo roster

Sem tabela por membro a cada passagem: Chat Tweaks não faz nada desligado e reaproveita as entradas;
TrialTracker roda no máximo uma vez por minuto (como o histórico de membros; um ingresso ouvido no chat
libera a próxima na hora) com tabelas reaproveitadas; `readRoster` e `DropDeparted` reaproveitam as suas.

## Locales

`enUS.lua` continua sendo a lista mestra, mas em jogo só guarda as três entradas cujo inglês difere da
chave; o resto já cai na chave pelo `Locale.lua`. Uma entrada nova com valor diferente da chave vai lá em cima.

## Como ver

`/gos debug mem`: a memória antes e depois de uma coleta de lixo completa, os frames criados na sessão
(`GuildOS.framesMade`, contados por um `local CreateFrame` no topo de cada arquivo; o `CreateFrame` global
nunca é trocado) e o tamanho das maiores tabelas salvas. Um número de frames que sobe com a tela parada é
vazamento.

## O teste

`tools/frame-leaks.lua` abre cada entrada de cada sala, redesenha cada tela acima 25 vezes e dispara os
ganchos com a janela fechada: nenhum frame, textura ou texto novo depois do primeiro desenho.

## Dados salvos compactos (segunda passagem)

A segunda causa de memória eram os dados salvos, que o cliente carrega inteiros a cada login: numa guilda madura
de 1000 membros as receitas da Anniversary chegavam a 20–30 MB, o equipamento a ~12 MB e o histórico de membros
podia passar de 20 MB. Medido em Lua 5.1 (`compact.lua` no rascunho), guilda sintética de 1000 membros:

| O quê | Antes | Depois |
|---|---|---|
| Receitas (100 por membro, 100 mil) | 248 B/receita, 23,6 MB | 40 B/receita, 3,9 MB |
| Equipamento (18 slots) | 13,2 KB/membro, 12,6 MB | 2,3 KB/membro, 2,2 MB (itens repetidos na guilda: 0,8 KB, 0,7 MB) |
| Histórico de membros | teto de 4000 chaves: até 24,6 MB | teto de 1500: até 9,3 MB (típico 2,3 MB) |
| Receitas no Forever/retail (cópia de `db.professions`, não salva) | 248 B/receita em memória | nenhuma cópia |

### Receitas

- **Anniversary**: `db.recipeIds[chave][profissão] = { h = hash, spellId1, itemId1, spellId2, itemId2, …, nm = {…} }`,
  dois números por receita (0 onde o scan não tinha). `nm` guarda só os nomes que o jogo não devolve: todos os dos
  personagens da própria conta (a lista sai de novo pela rede por nome) e, dos outros, os de receita sem spellId.
  O nome de uma receita com spellId é o do cliente (`GetSpellInfo`), como a tela já mostrava.
- `h` é o hash que a rede calcula (nomes ordenados, `RecipeTracker.Hash`), guardado como chegou: o anúncio do
  remetente continua batendo e ninguém pede a lista de novo.
- **Forever e retail**: nenhuma cópia por membro. Os leitores leem `db.professions` pelo catálogo, e os índices
  item→artesãos e receita→artesãos são montados na primeira leitura (`Professions:CraftersOf`,
  `ProfDirectory.CraftersForItem`, `RecipeTracker:BuildItemCrafterIndex`) e descartados a cada mudança.
- **A API**: `RecipeTracker:RecipesOf(chave, profissão)` (iterador `i, spellId, itemId, nome`), `EachList()`,
  `ProfsOf(chave)`, `CountOf(chave, profissão)`, `Put(chave, profissão, lista)`. Painel de receitas, Busca, tooltips
  "Criado por", CraftFinder, CraftNet, Encomendas, diretório da aliança e o aviso de profissão leem por ela; nenhum
  lê `db.recipes`.
- **A rede não mudou**: `RC` e a resposta a `RA` levam o formato antigo (`{ name, itemId, spellId }`), que toda
  versão lê; o que chega no formato antigo (RC, ou o `recipes` de um broadcast de versão anterior à D3) é convertido
  na entrada (`Put`), com a regra do `MergeSpellIds` (nome sem ID ganha o spellId que o membro já tinha).

### Equipamento

- `linha.gc[slot] = "id:encantamento:gema1.gema2.gema3.gema4:sufixo:ilvl:qualidade\tnome[\tlink]"`: uma string por
  slot, o link só nas linhas do próprio cliente. O mesmo item com o mesmo encantamento e gemas é uma string só
  para a guilda inteira (o Lua internaliza strings).
- Ninguém lê a string: `GuildOS:MemberGear(linha)` devolve os slots no formato antigo (`{ link, id, name, quality,
  ilvl, enchantId, gems = { { id } }, suffix }`), decodificados na leitura do slot e não guardados (cache fraco).
  `pairs()` não funciona nessa visão: percorre-se `GuildOS.SlotIDs` ou `Gear.Slots`.
- O broadcast continua mandando o formato antigo; o que chega (de qualquer versão) vira `gc` em `StoreReceivedData`.

### Histórico de membros

- `MAX_KEYS` de 4000 para 1500. A regra fica: membro presente e membro com nota permanente nunca saem; saem
  primeiro os que saíram há mais tempo. Os passos e cargos continuam como tabelas com chave (compactá-los mexeria
  em toda a lógica de fusão, e o ganho com o teto já é o maior).

### Guildas desta conta

- `GuildOSDB` guarda um banco por guilda que um personagem da conta já abriu, todos carregados a cada login.
  Configurações › Dados e suporte lista "Dados de guilda nesta conta" (nome, tamanho estimado, última abertura)
  com Excluir por guilda, atrás da confirmação padrão, nunca a guilda em uso. `db._opened` é carimbado a cada login;
  um banco que esta versão nunca abriu ganha a data em que foi visto pela primeira vez (`_openedEst`: "antes de").
- O Resumo do login avisa uma vez por banco (`GuildOSDB._staleDbTold`) quando há bancos sem abrir há 90 dias, com
  o caminho até a tela. Nada é apagado sozinho.

### Migração

- Versionada em `db.schema` (`recipes = 2`, `gear = 1`, `history = 1`), rodada no `Initialize` de cada módulo.
  Receitas e equipamento são idempotentes e rodam a cada carga: só convertem o que está no formato antigo
  (`db.recipes`, `linha.gear`), que só uma versão anterior escreve. O histórico corta uma vez.
- Sem perda do que algum leitor usa: IDs, hash, nomes próprios e nomes sem spellId ficam; o nome de outro membro
  para uma receita com spellId vem do cliente (num idioma diferente do remetente aparece no idioma do leitor, como a
  tela já fazia). Os campos do item vão todos na string.
- **Backup**: o Backup (Configurações › Dados e suporte) exporta o banco inteiro; restaurar um backup de antes desta
  versão roda a migração na carga seguinte, porque `db.schema` vai junto.
- **Voltar para uma versão anterior**: os campos novos têm outro nome (`recipeIds`, `gc`), então a versão antiga não
  quebra: vê as receitas e o equipamento vazios até o próximo scan ou sync, e escreve de novo no formato antigo.
  Voltando para esta versão, o que ela escreveu é convertido na carga (ou na primeira leitura, no caso das receitas).
  O histórico cortado não volta.

### O teste

`tools/memory-compact.lua`: dados no formato antigo → formato novo → cada leitor responde o mesmo que a versão
anterior respondia (registrado rodando o `RecipeTracker.lua` anterior sobre o mesmo `db.recipes`); segunda rodada
não muda nada; lista no formato antigo vinda da rede é guardada compacta e não é pedida de novo; o broadcast do
equipamento sai igual; o teto do histórico; a lista de guildas e o aviso do Resumo. `/gos debug mem` mostra o
tamanho de cada armazenamento compacto, por linha, e quantas linhas ainda estão no formato antigo.

## Lixo por minuto (terceira passagem)

O mantenedor mediu em jogo (WoW: Forever, guilda de 180): 166,7 MB de memória do Guild OS, 36 MB depois de uma
coleta completa. Uns 130 MB eram lixo: o addon alocava mais depressa do que o coletor incremental do cliente
limpava, e o contador do cliente inclui o que ainda não foi coletado. A regra desta passagem:

- Um caminho quente (evento frequente, ticker, `OnUpdate`, filtro de chat, gancho de tooltip) não cria tabela nem
  closure por chamada: reaproveita a sua (`into`/pool por chave), usa uma função feita uma vez e sai cedo quando
  não há nada a fazer (recurso desligado, tela escondida, ninguém para desenhar).
- Um evento que vem em rajada (o `GROUP_ROSTER_UPDATE` de uma raide, o `GUILD_ROSTER_UPDATE`) passa pelo
  `GuildOS:Coalesce`; uma contagem que percorre o roster inteiro tem validade (60 s) em vez de ser refeita a cada
  evento.
- Uma lista que só mostra N itens só lê N (o histórico do servidor, o log de 1.100 linhas).

### Medido

`tools/alloc-budget.lua` com `ALLOC_PROFILE=1` sob `lua5.1` (o Lua do jogo), guilda sintética de 180 (35 online),
1.100 linhas de log em meio ano, 120 membros com equipamento; KB alocados por minuto simulado, antes → depois:

| Cenário | Antes | Depois |
|---|---|---|
| Parado na cidade, janela fechada | 597 | 44 |
| Janela aberta na aba Membros | 5.946 | 344 |
| Raide de 20, Salão aberto, chat movimentado | 27.122 | 1.449 |

Os maiores, por gatilho (MB/min, antes → depois):

1. **Card do chat do Salão** (`UI/Salao.lua` `fillChat`, a cada linha de /g pelo `CHAT_MSG_GUILD` e de novo pelo
   `CLUB_MESSAGE_ADDED`): lia 200 linhas do histórico do servidor e copiava tudo duas vezes por linha. 12,1 → 0,54.
   Agora: só as 40 que o card mostra (`GuildChat:Entries(stream, max)`, `Merge` corta antes), um desenho por rajada
   (0,3 s depois da primeira), nada se a versão do chat (`GuildChat.version`), o tamanho e o dia não mudaram, e as
   linhas em tabelas reaproveitadas.
2. **Contagens do oficial no título da janela** (`UI/Window.lua`, `Agora:OfficerCounts` → `GuildManager:GetInactiveMembers`,
   `RosterMaint.GroupSeen`): ~250 KB a cada `GROUP_ROSTER_UPDATE`, `GUILD_ROSTER_UPDATE` e a cada 10 s. 6,0 → 0,19.
   Agora `Agora:RosterCounts` guarda as duas contagens por 60 s (uma linha do log de roster as zera), as linhas de
   `GetInactiveMembers` são reaproveitadas e as abas só são revistas a cada 2 s numa rajada de grupo.
3. **A lista de Membros redesenhada sob qualquer aba** (`GuildOS:RefreshRosterUI` → `RosterFrame:BuildMemberList`):
   ~700 KB por atualização do roster com a janela aberta em qualquer aba. 4,2 → 0 sob outra aba, 0,13 na própria.
   Agora a lista escondida só marca `rosterDirty` e desenha no `OnShow`; as entradas são uma por membro, por chave,
   reaproveitadas; `Marks.Scan`, o índice do card (`RosterCard.NewIndex(links, into)`) e os números dos cartões
   (`GuildOS:TrueRosterCounts`) também.
4. **Refresh de 15 s do Salão**: a contagem regressiva montava o relatório inteiro de prontidão (decodificando o
   equipamento de todos) e a Atividade formatava as 1.100 linhas do log. 3,4 → 0,34. Agora `Readiness:LevelRows` (só
   chave e nível) e a Atividade pula o que é mais velho que a janela antes de formatar.
5. **PugInspector** (`GROUP_ROSTER_UPDATE`): classificava o grupo inteiro a cada evento mesmo com a janela fechada e
   a abertura automática desligada. 0,80 → 0. Agora só com a abertura automática, e só quando os membros mudam.
6. **Mapa da guilda, tick de 1 s** (`Modules/GuildMap.lua`): refazia uma tabela por membro do roster a cada
   atualização e lia `C_Map.GetMapInfo` (uma tabela nova por chamada) toda vez. 0,35 → 0,01. Agora o roster é
   preenchido no lugar, e `MapInfo`, a zona de cada mapa e o tamanho em jardas ficam guardados até a próxima troca de
   zona; o grupo é lido em tabelas reaproveitadas (`Compat.GroupUnits(into)`).
7. **Pontos no minimapa, 10 vezes por segundo** (`UI/GuildMap.lua` `RefreshDots`): uma closure e quatro vetores por
   chamada, mesmo sem ninguém para desenhar. 0,22 → 0. Agora sai antes de qualquer leitura de mapa sem ninguém vivo, e
   a função por ponto é feita uma vez.

Também: `GuildOS:LocalDate` sem closure por chamada (e sem `date("*t")` num formato sem nomes), `GuildChat` sem
closure por linha, `CompareVersions` sem closure por comparação.

### Memória retida

- **Fotos da raide** (`RaidTracker`): cada `GROUP_ROSTER_UPDATE` de uma raide gravava uma foto com uma tabela por
  raider na sessão aberta (que fica nas variáveis salvas até a noite acabar). Agora no máximo uma a cada
  `ROSTER_SNAP_GAP` (30 s), a última mudança nunca perdida; as de 5 em 5 minutos seguem iguais.
- Sem crescimento sem limite: 40 minutos simulados com 3.000 desconhecidos diferentes (canal de troca, sussurros,
  linhas do mesh e da guilda tocadas de volta) estabilizam (+10 KB a cada 10 min depois do aquecimento); os caches
  por remetente (`ChatTweaks._authors`, `SyncService.seenIds`, `CommSystem.syncStats.senders`) têm limite.
- Os dados salvos ocupam em Lua cerca de 1,9× o que `EstimateBytes` diz (972 KB contra 520 KB no harness): os
  ~3,6 MB que `/gos debug mem` estima para os 4 bancos são uns 7 MB carregados, mais ~11 MB de código e estrutura.
  Bancos de guildas que não se usa mais saem em Configurações › Dados e suporte.
- `db.bulletin.seen` cresce um id por aviso (pequeno; fica anotado).

### Bibliotecas

O mesh compartilhado (`Libs/LibChehulMesh.lua`, `Modules/ChehulNet.lua`) não é um alocador grande: 0,02–0,05 KB por
linha recebida e ~1,5 KB por beacon de 180 s. O caro por mensagem é a sincronização da guilda: um envelope `SV`
custa ~12 KB para decodificar (LibDeflate `DecompressDeflate` ~6 KB, LibSerialize ~5 KB) e um `BC` ~30 KB. Mandar sem
compressão o que é curto cortaria isso, mas muda o protocolo (um cliente antigo não lê); fica para quando todos
tiverem a versão.

### Como ver

`/gos debug mem rate`: lê a memória do Guild OS uma vez por segundo durante 10 s, sem forçar coleta, e diz quantos
KB/s (e MB por minuto) ele alocou. Uma leitura menor que a anterior é o coletor trabalhando: só as subidas contam,
então o número é um piso.

### O teste

`tools/alloc-budget.lua` carrega o addon inteiro (o TOC) num cliente WoW: Forever falso com relógio de verdade:
`OnUpdate` a 60 quadros por segundo, timers e tickers, os eventos de uma guilda de 180, os filtros de chat em dois
quadros de chat por linha, os ganchos de tooltip ao passar o mouse, o histórico do servidor (`C_Club`) e cada
mensagem de addon que este cliente manda tocada de volta como se viesse dos outros usuários. Orçamentos (KB por minuto
simulado; o teste mede ~40–120 parado, ~350–600 na aba Membros e ~1.450–1.850 na raide, conforme o interpretador):
parado 600, aba Membros 1.500, raide com o Salão aberto 4.000; a memória retida entre dois trechos parados não sobe
mais que 256 KB. Também confere que o que agora é reaproveitado responde igual ao que era novo (roster, marcas,
índice do card, contagens, inativos, níveis, roster do mapa) e que uma tempestade de 20 eventos de grupo num minuto
grava no máximo 3 fotos da raide.

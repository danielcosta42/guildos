# A Regra de Loot (épico danielcosta42/guildos-web#518)

Quem leva um item deixa de ser código e vira dado. Toda forma de distribuir loot que as guildas usam
(MS > OS, +1, soft reserve, SR+, wishlist, conselho, DKP de preço fixo ou de lance, soma zero, EPGP,
Suicide Kings, karma, lista ranqueada) percorre o mesmo caminho a cada item; o que muda é quase só a
ordem dos critérios de desempate.

## O modelo

Dois cadernos, que guardam o que a guilda sabe antes do item cair:

- **Contas** (`Modules/Points.lua`): um número por personagem. Tipos: saldo, contador, posição em fila,
  bônus de rolagem. Cada conta tem motivos de ganho (valor e teto semanal próprios), valor inicial,
  teto, piso, decaimento e quando zera.
- **Listas**: wishlist, prioridade dos oficiais, reserva da noite, reserva fixa, fila de lendário.

Seis blocos, que decidem cada item (`Modules/LootRule.lua`):

| Bloco | Campo da regra | Pergunta |
| --- | --- | --- |
| Quem pode | `filters` | Quem entra na disputa, e com que resposta |
| Como pede | `responses` | Os botões, e o que cada um pede (rolagem, lance, nota) |
| Ordem | `order` | Lista de critérios: compara pelo primeiro, empatou vai ao seguinte |
| Quem decide | `decide` | Automático, master looter, conselho, dono do item |
| Efeitos | `effects` | O que o prêmio muda nas contas e nas listas |
| Exceções | `exceptions` | Itens que trocam um ou mais blocos |

Nenhum bloco aceita fórmula escrita: tudo é escolha em lista, número ou ordem. É o que mantém a regra
legível, validável e segura de sincronizar. Uma regra que o cliente não lê inteira não é aplicada em
parte (`LootRule:Validate`).

## Invariantes

- **Guilda atual não muda.** Cada sistema de antes (`rolls`, `tmb`, `wishlist`, `dkp`) é uma regra pronta,
  derivada do sistema e dos ajustes que a guilda já tinha (`LootRule:FromLegacy`). `tools/loot-rule.lua`
  compara a ordem da regra com a do código de antes em toda combinação.
- **Uma ordem só.** A janela do master looter, o fim da rolagem e o TradeCouncil leem a mesma ordem.
- **Empate total** é decidido pelo nome, para dois clientes lerem sempre a mesma ordem.
- **Tetos:** 10 critérios, 10 filtros, 10 respostas, 6 contas por regra.
- **Fora:** GDKP, fórmula livre, parses automáticos.

## Fatias

1. #333 o motor: `filters` e `order` lidos da regra.
2. #309 e #319: contas (motivos, tetos, decaimento, devolução, EPGP).
3. #334: respostas configuráveis, +1, resposta pelo addon, lance fechado.
4. guildos-web#516: a regra no site.
5. #335: exceções por item.
6. #336 e guildos-web#517: conselho com registro, o porquê de cada prêmio, simulador.
7. #337: fila, karma, pontuação somada.

## O contrato da regra (v1)

O mesmo formato no addon (tabela Lua) e no site (JSON). Campo ausente = comportamento padrão.
Chaves curtas porque a regra viaja pelo `GOSROST1` e pela sincronização da guilda.

```jsonc
{
  "v": 1,
  "model": "rolls",            // de que modelo pronto a regra nasceu; "custom" depois de editada à mão
  "time": 30,                  // segundos para responder (5 a 300)

  // Como pede: até 10 respostas, na ordem de prioridade. "PASS" existe sempre e não se declara.
  "responses": [
    { "key": "MS", "label": "Main spec", "ask": "roll", "plus": true,  "cost": 1 },
    { "key": "OS", "label": "Off spec",  "ask": "roll", "plus": false, "cost": 0.5 }
  ],
  // key: 1 a 8 de [A-Z0-9]. ask: "roll" | "bid" | "none". plus: conta para o contador +1.
  // cost: multiplicador do preço (0 = não paga). note: true exige uma nota.

  // Os lances, quando alguma resposta pede "bid": fechados ou abertos, o lance mínimo e o passo.
  "bid": { "sealed": false, "min": 10, "step": 1 },

  // Quem pode: até 10 filtros. act "block" tira da disputa; "downgrade" troca a resposta from -> to.
  "filters": [
    { "k": "attendance", "min": 50, "act": "downgrade", "from": "MS", "to": "OS" },
    { "k": "account", "acct": "dkp", "min": 4, "act": "block" },
    { "k": "reserved", "act": "block" },          // precisa ter reservado o item
    { "k": "received", "max": 2, "act": "block" } // limite de itens por noite
  ],

  // Ordem: até 10 critérios. band agrupa em faixas. Cada k no máximo uma vez, exceto "account".
  "order": [
    { "k": "response" }, { "k": "hardres" }, { "k": "softres" }, { "k": "prio" }, { "k": "wishlist" },
    { "k": "received" }, { "k": "attendance", "band": 10 }, { "k": "points" },
    { "k": "account", "acct": "plus1", "dir": "low" },   // dir: "high" | "low" vem primeiro
    { "k": "ratio", "num": "ep", "den": "gp" },
    { "k": "bid" },
    { "k": "roll", "bonus": "karma" },                    // rolagem + saldo da conta, se a resposta pediu
    { "k": "upgrade" },
    { "k": "score", "parts": [ { "k": "wishlist", "w": 1 }, { "k": "attendance", "w": 0.1 }, { "k": "account", "acct": "wait", "w": 1 } ] }
  ],

  // Quem decide.
  "decide": { "by": "auto", "council": { "ranks": [0, 1], "names": [], "anon": false, "self": false, "note": false, "quorum": 2 } },
  // by: "auto" | "ml" | "council" | "holder"

  // Efeitos do prêmio, aplicados em ordem. Até 10.
  "effects": [
    { "k": "charge", "acct": "dkp", "price": "fixed", "value": 10 },  // price: "fixed" | "table" | "bid" | "second" | "fraction" | "all"
    { "k": "entry", "acct": "dkp", "value": 4, "refund": 0.5 },       // todos pagam para disputar; quem perde recebe a fração de volta
    { "k": "add", "acct": "plus1", "value": 1 },                      // soma na conta do vencedor
    { "k": "bottom", "acct": "sk" },                                  // vencedor vai para o fim da fila
    { "k": "split", "acct": "dkp" },                                  // o que foi cobrado é dividido entre os presentes
    { "k": "reset", "acct": "wait" }                                  // zera a conta do vencedor
  ],

  // Exceções: até 20. A mais específica vence: item, chefe, categoria, raide.
  "exceptions": [
    { "on": { "items": [19019] }, "name": "Thunderfury", "set": { "order": [ { "k": "account", "acct": "tf", "dir": "low" } ], "decide": { "by": "ml" } } },
    { "on": { "cat": "recipe" }, "to": "bank" },   // to: "bank" | "de": destino fixo, sem disputa
    { "on": { "cat": "unclaimed" }, "to": "de" }
  ],
  // cat: "tier" | "legendary" | "mount" | "recipe" | "boe" | "trash" | "unclaimed". on.boss: id do encontro. on.raid: id da instância.

  // Contas: até 6. A conta "dkp" é a de pontos de sempre (Points); "ep" e "gp" são as do EPGP.
  "accounts": [
    { "key": "dkp", "type": "balance", "name": "DKP", "start": 0, "cap": 25, "floor": 0,
      "decay": { "pct": 10, "round": "up" },      // round: "up" | "down" | "near"
      "reset": "never",                            // "never" | "night" | "lockout"
      "earn": [
        { "key": "boss",   "auto": "boss",      "value": 3 },
        { "key": "ontime", "auto": "ontime",    "value": 2 },
        { "key": "late",   "auto": "late",      "value": 1 },
        { "key": "stayed", "auto": "stayed",    "value": 2 },
        { "key": "left",   "auto": "leftearly", "value": 1 },
        { "key": "raid",   "auto": "raid",      "value": 5 },
        { "key": "mats",   "name": "Material donation", "value": 1, "weekly": 5 }   // sem auto: lançamento manual
      ] }
  ]
  // type: "balance" | "counter" | "queue" | "bonus". key: 1 a 8 de [a-z0-9].
  // Numa conta "queue": "frozen": true (quem está ausente guarda a posição) e "newcomer": "bottom" | "random".
}
```

## Cada core com o seu sistema, a sua regra e as suas contas (#338)

O sistema de loot e a regra em vigor são os do core ativo da raide (`CoreManager:GetActiveName()`);
sem core ativo, os da guilda. A ordem de quem fala:

1. a regra própria do core (`core.lootMaster.rule`);
2. o sistema de loot próprio do core (`core.lootMaster.lootSystem`), pela regra pronta dele;
3. a regra da guilda (`settings.lootRule`);
4. o sistema de loot da guilda (`settings.lootSystem`), pela regra pronta dele.

Um core que não escolheu nada segue a guilda. O campo `lootMethod` de antes, que nenhum código lia, não
é migrado. `GuildOS:GetLootSystem(coreName)` e `LootRule:For(coreName)` respondem por um core pelo
nome; `""` é a guilda. `LootRule:Set(rule, coreName)` e cada função do editor de respostas recebem o
core por último; sem ele, mexem na regra da guilda.

- **Sincronização:** a escolha de um core (sistema e regra, sob um carimbo só, `lootAt`) viaja entre
  oficiais no domínio `core.roster`, ação `loot`: `{ coreName, sys = <chave> | false, rule = <regra> |
  false }`, `rev = lootAt`. Carimbo mais novo vence; sistema que este cliente não oferece ou regra que
  ele não lê inteira é recusado inteiro (nem o sistema que veio junto entra). Um cliente de antes
  ignora a ação, que não leva `members`. A mensagem não cria core: ele chega com o roster.
- **Item anunciado:** guarda a regra e o sistema com que foi anunciado (`activeLoot.rule`,
  `activeLoot.system`). Trocar o core ativo, ou um oficial salvar outra regra, muda o próximo item,
  nunca a rolagem em curso.
- **Contas:** o contador mora no pool de pontos, que já é por core; cada lançamento leva o core.
- **Tela:** o que o sistema mostra (janela de pontos, acesso à wishlist) segue o core ativo.

## O que o addon lê do contrato (#334, guildos-web#516)

`LootRule:Validate` aceita só o que este cliente aplica. Uma regra com um campo que ele não conhece, em
qualquer nível, é recusada inteira. Uma regra do contrato que pede uma peça ainda não aplicada é
recusada com o motivo `unsupported: <peça>` (`LootRule:Unsupported`, `LootRule:UnsupportedText`).

- **`responses`** em objeto, `time` e `bid`. `label` tem até 24 bytes, sem `|`, `;` nem caractere de
  controle (viaja no anúncio e vira texto de botão). `cost` vai de 0 a 10. Campo ausente: `ask = "roll"`,
  `plus = false`, `cost = 1`, `label = key`. O bloco `bid` é do addon; o site não o emite.
- **`filters`**: `attendance { min }`, `account { acct, min }`, `reserved`, `received { max }` e o
  `points { min }` que este cliente escrevia antes do contrato (igual a `account` em `dkp`). Todo
  filtro aceita `act = "block"` (fora da disputa) ou `"downgrade"` (`from` vira `to`). `received` conta
  os itens da noite (desde o início da sessão de raide). Um pass não é barrado por filtro nenhum. Uma
  resposta rebaixada ainda passa pelos filtros seguintes.
- **`order`**: `response`, `hardres`, `softres`, `prio`, `wishlist`, `received`, `attendance`, `points`,
  `bid`, `roll` (com `bonus`, a conta de bônus somada), `account` (qualquer conta, `dir` `high` ou `low`;
  numa fila, a posição), `ratio` (`num` / `den`, o divisor nunca abaixo de 1), `score` (soma de partes)
  e o `pr` do addon (a prioridade do pool, EPGP de antes).
- **`accounts`**:
  - `counter`: `key`, `name`, `reset`, `start` (só 0) e `earn` com `auto` `raid` (uma vez por raide
    para quem esteve nela, dita uma vez por mais oficiais que a encerrem) ou `boss` (a cada chefe, pelo
    cliente do líder da raide). Teto, piso, decaimento, ganho manual ou por outro `auto`: recusados.
  - `bonus` e `queue` (#337): ver "As contas raras" abaixo.
  - `balance`: só `dkp` (o saldo do pool de pontos), `ep` (o que foi ganho) e `gp` (o que foi gasto).
    As três chaves valem mesmo sem declaração. O que a regra diz de como elas enchem entre um item e
    outro (`earn`, `decay`, `cap`, `start`, `floor`) é lido e **não aplicado**: continua valendo o que
    os pontos têm configurado no jogo. A exceção é `gp.start`, o GP base pelo qual o `ratio` da regra
    divide.
- **`decide`**: `auto`, `ml` e `holder` são lidos e terminam igual: a ordem diz o vencedor e o clique
  do master looter entrega o item, que não volta. `council` (#336) abre uma votação quando as respostas
  fecham: ver "O conselho" abaixo. `decide.council` é validado campo a campo com qualquer `by`:
  `ranks` (até 10 índices de 0 a 9), `names` (até 20 nomes; sem vírgula, sem espaço nas pontas nem dois seguidos: um espaço no meio é o do "Nome Sobrenome" do WoW: Forever), `anon`, `self`,
  `note` e `quorum` (1 a 40); um campo que o cliente não conhece recusa a regra.
- **`effects`**, aplicados na ordem:
  - `charge` nos pontos (`dkp` ou `gp`; no máximo um): `table` (o preço do item, o padrão), `fixed`,
    `bid`, `second` (o maior lance vencido na mesma resposta mais um passo, nunca acima do lance do
    vencedor; sozinho, o lance mínimo), `fraction` (a fração `value` do saldo do vencedor) e `all`.
    Num contador: `fixed`, `fraction` ou `all`, nunca mais do que ele tem. Todo preço é multiplicado
    pelo `cost` da resposta.
  - `entry { acct = "dkp", value, refund }`: todos pagam para disputar e quem perde recebe a fração
    de volta. Sem ele vale o custo de entrada configurado nos pontos, como antes.
  - `add` num contador, quando a resposta vencedora tem `plus = true`; `reset` zera o contador do
    vencedor, qualquer que seja a resposta. O Desfazer devolve os dois.
  - `bottom` numa fila e `split` nos pontos (#337): ver "As contas raras" abaixo.
- **Recusado, com motivo próprio:** `upgrade` (a linha do candidato não tem o dado), conta `balance` fora das três (`balance`), contador com início, teto, piso
  ou decaimento (`counter`) e ganho que um contador não recebe (`earn`).
- **`exceptions`** (#335): ver "As exceções por item" abaixo.
- Modelos prontos novos em `GuildOS.LOOT_SYSTEMS`: `plus1`, `dkpbid`, `dkpsealed`, desde a #337 `sk`
  (Suicide Kings) e `karma`, e desde a #336 `council` (fora do retail, que não tem master looter).
  Escolher um sistema de loot volta à regra pronta dele.
- Uma regra com conselho, fila, conta de bônus ou `score` é jogada inteira (`LootRule:PlaysWhole`): o
  item é anunciado direto na disputa aberta, sem os atalhos de wishlist dos sistemas de antes.

Os 14 modelos do site com as respostas padrão (`tools/data/loot-rule-models.json`,
`tools/loot-contract.lua`) são lidos e jogados: `rolls`, `plus1`, `softres`, `srplus`, `hardres`,
`wishlist`, `council`, `dkp`, `dkpbid`, `zerosum`, `epgp`, `sk`, `karma`, `ranked`. Nenhum é recusado.
Uma regra do contrato com `upgrade` segue recusada inteira.

### As contas raras (#337)

- **Qual resposta "conta".** O contrato não tem um campo que diga qual resposta usa o bônus ou desce
  na fila. Os modelos do site marcam a resposta principal com `plus = true` e a secundária com
  `plus = false` (e `cost = 0` no karma e no SK). O addon lê `plus` como "esta resposta conta": é ela
  que soma o bônus à rolagem, que paga a `charge` de uma conta de bônus, que leva o `add` e que manda
  o vencedor ao fim da fila (`bottom`). `reset` segue valendo para qualquer resposta.
- **Conta de bônus** (`type = "bonus"`): guardada como um contador (`pool.accounts`, ação `cdelta`).
  Começa em 0 (`start` e `floor` só 0), aceita `cap` inteiro (o ganho por `auto` `raid` ou `boss` e o
  `add` de um prêmio somam só o que cabe sob o teto) e `reset`. `{ k = "roll", bonus = "<conta>" }`
  soma o saldo à rolagem de quem respondeu com uma resposta que conta e tem rolagem; a janela do
  master looter mostra `rolagem +bônus = total` e a linha do vencedor diz os dois. `charge` nela
  (`fixed`, `fraction`, `all`, vezes o `cost` da resposta) só é cobrada quando a resposta vencedora
  conta (karma: perde metade). O `srplus` do site é jogado como ele emite: +10 por raide até 50,
  bônus na rolagem de MS, `reset` do vencedor. O site não emite "cresce para quem reservou e não
  levou", então o addon não faz isso.
- **Conta de fila** (`type = "queue"`): uma lista ordenada por pool (`pool.queues[conta] = { seq, op,
  list }`). O critério `account` nela lê a posição (`dir = "low"`: o primeiro da fila vem primeiro;
  quem não está na fila vem depois de todos). Só aceita `key`, `name`, `frozen` e `newcomer`.
  - `bottom`: o vencedor vai ao fim, quando a resposta conta. Sem `frozen`, todos abaixo sobem uma
    posição. Com `frozen = true` (a regra clássica do Suicide Kings), só quem está na raide sobe:
    ausentes guardam a posição absoluta e o vencedor fica na posição do último presente abaixo dele.
  - `newcomer`: quem a fila nunca viu entra no fim (`"bottom"`, o padrão; vários de uma vez, por
    nome) ou numa posição sorteada (`"random"`). A raide inteira entra quando um item é anunciado;
    quem responde sem posição entra na hora.
  - Sincronização: cada mudança é uma entrada no log dos pontos, ação própria `qset` (cliente de
    antes ignora), com a ordem inteira e o número de sequência seguinte. Sequência maior substitui a
    ordem, menor chega atrasada e não muda nada, igual decide pelo `op`: todos terminam na mesma ordem
    em qualquer ordem de chegada. O snapshot leva `queues` e vale a mesma comparação. Até 200 nomes.
  - Desfazer: o prêmio guarda o movimento (`from`/`to`, ou as posições que participaram quando há
    ausentes no meio) e o desfaz exatamente; se a fila mudou no meio, só o vencedor volta à posição.
- **`score`** `{ k = "score", parts = [{ k, w, acct? }] }`: soma de até 6 partes, cada uma vezes o seu
  peso (`w` de -100 a 100, nunca 0), maior primeiro. Partes: `wishlist` e `prio` (posição virada em
  pontos: 1º lugar 10, cada lugar seguinte um a menos, do 11º em diante ou fora da lista 0),
  `attendance` (0 a 100), `received` (itens da noite) e `account` (o que a conta guarda). Sem fórmula
  escrita. A janela mostra o total e, no tooltip da linha, cada parte (`LootRule:ScoreOf`).
- **`split`** `{ k = "split", acct = "dkp" }`: o que o vencedor pagou pelo item (a `charge` nos pontos,
  não o custo de entrada) é dividido em partes iguais entre quem está na raide no momento, o vencedor
  inclusive (soma zero), resto descartado. Cada parte é uma entrada do log (`kind = "split"`), sem
  teto. O Desfazer tira as partes de volta. Só o cliente de um oficial divide.
- **Telas:** a janela de pontos ganha um botão que troca a lista entre os pontos e cada conta da regra
  em vigor (fila por posição, bônus e contador por saldo) e é oferecida também quando a regra tem fila
  ou bônus; o editor da regra mostra as duas opções da fila.

### As exceções por item (#335)

Até 20. `on` diz quais itens: `items` (até 40 ids), `boss` (id do encontro), `cat` ou `raid` (id da
instância); com mais de um campo, o item precisa ser todos. Ou `to = "bank" | "de"` (destino fixo, sem
disputa) ou `set` com os blocos que troca (`order`, `decide`, `responses`, `effects`, `filters`),
validados pelas mesmas funções da regra. A mais específica vence (item, chefe, categoria, raide); entre
iguais, a primeira da lista (`LootRule:ExceptionFor`, `LootRule:ForItem`).

- **Categorias que o cliente reconhece sem tabela digitada:** `recipe` (classe do item), `mount`
  (classe Diversos, subclasse Montaria), `boe` (vincula ao equipar), `legendary` (qualidade), `trash`
  (qualidade abaixo do limiar de loot dos ajustes) e `tier` (lista de ids por versão do jogo,
  `LootRule.TIER_ITEMS`, que nasce **vazia**: só entra id conferido no jogo). `unclaimed` (ninguém
  pediu) só é lida no fim da rolagem. "Não veio de chefe" não faz parte de `trash`: o cliente não
  distingue isso com a certeza que um item entregue exige.
- **O item:** `LootMaster:ItemFacts` lê id, qualidade, classe, subclasse e vínculo do item, o limiar
  de loot, a instância da raide e, só enquanto o item está na janela de loot aberta até 10 minutos
  depois de um chefe morto, o encontro. Item rolado da bolsa não tem chefe.
- **Destino fixo:** o item vai ao personagem do banco (ajuste novo, ao lado do desencantador, por
  core como ele) ou ao desencantador, sem abrir disputa, com uma linha na raide que diz qual exceção
  valeu, e ninguém é cobrado. Sem personagem definido, o master looter é avisado e nada é entregue.
- **Blocos trocados:** o item é anunciado e decidido pela regra com aqueles blocos trocados, em
  disputa aberta a todos, e a linha do anúncio diz qual exceção valeu. O item guarda essa regra até
  ser entregue.
- **Ninguém pediu:** com uma exceção `unclaimed`, o cliente do master looter manda o item ao destino
  no fim da rolagem. Sem ela nada muda: a raide é avisada e o botão "Send to Disenchant" segue como
  era, com o desencantador e o limiar de sempre.
- **Editor:** lista compacta no editor da regra (guilda e core): alvo (categoria, ids de item, id do
  chefe, id da raide), destino (banco, desencantador, outra ordem) e, para outra ordem, os critérios
  escolhidos em sequência (`LootRule:AddException`, `LootRule:RemoveException`).

### A regra da noite (GOSROST1 v5)

O site manda a regra da raide em `lootRule`, junto do roster. `CompanionImport.ReadLootRule` guarda uma
cópia limitada em profundidade, número de campos e tamanho de texto (a caixa de entrada é entrada não
confiável); o que não é regra nenhuma fica como recusado.

- Vale acima da regra do core e da guilda (`LootRule:Night`, lido por `LootRule:Active`), quando o
  cliente está numa raide e o roster em mãos é o de agora: de 2 horas antes do início a 8 horas depois.
- Tomada, fica congelada pela noite (`db.lootNight`, uma cópia): o mesmo roster importado de novo com
  outra regra não muda nada. Acaba quando a janela termina ou quando o roster em mãos é o de outra
  raide de agora.
- Com a regra da noite em vigor, `GuildOS:GetLootSystem()` responde o sistema de antes de que ela mais
  se aproxima (`LootRule:SystemOf`), para o anúncio e para o que as telas mostram, e o item é anunciado
  direto na disputa aberta, sem os atalhos de wishlist dos sistemas de antes.
- Regra inválida ou com peça que este cliente não aplica: recusada inteira, a da guilda segue valendo,
  e a janela do plano diz em uma linha que a regra de loot desta raide precisa de um GuildOS mais novo
  (com a peça, quando conhecida). Lida, a janela mostra o nome do modelo e se já está em vigor.
- Guilda ou core em "external" não toma regra do site.

### A resposta pelo addon

Tudo sob o prefixo do LootMaster. Quem respondeu é sempre o remetente que o jogo informa.

| Mensagem | De quem | O quê |
| --- | --- | --- |
| `ASK\|sid\|<tempo>,<o\|s\|->,<mín>,<passo>;KEY=<a>Rótulo;...` | master looter, RAID | Os botões, logo antes do anúncio. `<a>`: `r` rolagem, `b` lance, `n` nenhum; maiúscula exige nota |
| `ANNOUNCE\|link\|segundos\|itemId\|0ou1` | master looter, RAID | O anúncio de sempre, sem mudança |
| `ANS\|sid\|KEY\|lance\|nota` | raider | RAID; WHISPER ao master looter quando o lance é fechado |
| `ROLL\|sid\|nome\|KEY\|rolagem` | master looter, RAID | A rolagem que o cliente dele sorteou |
| `BID\|sid\|nome\|KEY\|lance` | master looter, RAID | Um lance aberto aceito |
| `ACK\|sid\|nome\|KEY` | master looter, RAID | Resposta recebida (lance fechado, sem rolagem, pass) |
| `NO\|sid\|nome\|motivo\|número` | master looter, RAID | Resposta recusada |

Versões misturadas: um cliente de antes ignora `ASK` e mostra o popup MS / OS do `ANNOUNCE`, cujo
`/roll` o master looter novo ainda lê do chat (1-100 é a primeira resposta da regra, 1-99 a segunda);
um cliente novo que ouve só o `ANNOUNCE` (master looter de antes) mostra o popup de antes, por `/roll`.

### O contador (+1)

Mora no pool de pontos (`pool.accounts[conta] = { rs, per, v }`) e viaja no mesmo log de operações, sob
a ação própria `cdelta` (um cliente de antes não a lê como pontos), e no snapshot. Cada lançamento diz
o período em que foi feito: a sessão de raide (noite), a semana do lockout, ou nenhum. Um lançamento de
período mais novo zera a conta antes de somar; um de período mais velho chega atrasado e não soma.

### O conselho (#336)

`decide = { by = "council", council = { ranks, names, anon, self, note, quorum } }`
(`Modules/LootCouncil.lua`, janela em `UI/LootCouncil.lua`; fora do retail).

- **Quem vota:** quem tem um dos índices de rank em `ranks`, lido do roster da guilda de cada cliente,
  ou está em `names`. Sem `ranks` e sem `names`, os oficiais da guilda (ranks 0 até o limiar de
  oficial). Membro por nome não precisa ser da guilda; todo voto precisa vir de quem está na raide.
- **A votação:** quando as respostas fecham com mais de um candidato, o cliente do master looter abre a
  sessão (o id é o da rolagem do item), manda os candidatos já na ordem da regra (até 10) e anuncia
  à raide que o conselho vota, no lugar da linha do vencedor. Com um candidato só não há votação.
  Dura `time` da regra, no mínimo 30 segundos.
- **O voto:** um por membro por item; um voto novo substitui o anterior e `0` retira o voto (a
  abstenção é não ter voto: não conta para o quórum nem entra no registro). `self = false` (o padrão):
  um membro que é candidato não vota naquele item. `anon = true`: o voto vai por WHISPER ao master
  looter (como o lance fechado), a raide ouve só os totais e o registro não guarda quem votou em quem.
- **O fim:** ao atingir `quorum` votos, ou quando o master looter encerra (botão, ou ao clicar Award
  com a votação aberta), o candidato com mais votos é proposto; empate vai para quem a ordem da regra
  põe primeiro. O master looter confirma com Award. Tempo esgotado sem quórum: ninguém é proposto, o
  master looter decide e o registro diz `decidedBy = "ml"` com os votos que houve. Sem `quorum` na
  regra a votação só fecha pelo master looter ou pelo tempo, e então propõe o mais votado, se houve
  voto.
- **`note = true`:** toda resposta precisa de nota (o `ASK` manda a letra maiúscula em todos os
  botões e a resposta sem nota é recusada), só enquanto quem decide é o conselho.
- **Entrada não confiável:** só o master looter da raide (o que o jogo aponta em `GetLootMethod`) abre
  e fecha sessão, e um cliente não lê essas mensagens de mais ninguém; o voto é de quem o jogo diz que
  mandou, nunca de um nome dentro da mensagem; voto de fora da raide, de fora do conselho, de outra
  sessão ou para um candidato que não existe não conta. Cliente de antes ignora tudo.
- **Editor e seletor:** seção "Who decides" no editor da regra (ordem, master looter, conselho; ranks
  por botão, nomes, anônimo, candidato vota, nota, quórum). "Loot council" no seletor de sistema dá a
  regra pronta: respostas sem rolagem, ordem resposta, wishlist, menos itens recebidos, presença em
  faixas de 10, oficiais votam, quórum 2, 60 segundos.

| Mensagem | De quem | O quê |
| --- | --- | --- |
| `COPEN\|sid\|segundos\|flags\|quórum\|ranks\|link` | master looter, RAID | Abre a votação. flags: `a` anônimo, `s` candidato vota, `-` nenhum; ranks em dígitos |
| `CMEM\|sid\|nome,nome` | master looter, RAID | Os membros por nome |
| `CCAND\|sid\|i\|nome\|KEY\|rolagem\|lance\|presença\|recebidos\|pontos\|wishlist\|prio\|reserva\|contas\|nota` | master looter, RAID | O candidato na posição `i` |
| `CVOTE\|sid\|i` | membro | RAID; WHISPER ao master looter quando o conselho é anônimo. `0` retira o voto |
| `CTALLY\|sid\|i=n,i=n` | master looter, RAID | Os votos até agora |
| `CWHO\|sid\|votante\|i` | master looter, RAID | Quem votou em quem (nunca com `anon`) |
| `CNO\|sid\|votante\|motivo` | master looter, RAID | Voto recusado: `member`, `self`, `unknown`, `closed` |
| `CCLOSE\|sid\|motivo\|i` | master looter, RAID | Fim: `q` quórum, `m` master looter, `t` tempo, `x` cancelado; `i` o proposto, 0 nenhum |

O item equipado no slot não vai na linha do candidato: a linha do master looter não tem esse dado (só
a do TradeCouncil, no retail, tem).

## O registro do prêmio (why)

Todo prêmio guarda por que o vencedor levou o item, quem quer que decida (`LootRule:Why`). Fica na
entrada do histórico de loot (`db.lootHistory[i].why`), só nas 200 entradas mais novas que têm
registro (`LootTracker:PruneWhy`), some com o Desfazer junto da entrada, e sobe ao site como campo
aditivo `why` de cada entrada de `loot` do GOSCOMP1 (a versão do payload segue 16; no máximo 200
entradas com `why` por envio; `Companion.LootWhy` reescreve campo a campo, então nada fora do formato
sai). Entrada sem registro não leva o campo: prêmio de antes, prêmio ouvido de outro oficial pela
mensagem `AWARD` (só o cliente de quem entregou tem o registro) e loot pessoal do retail.

```jsonc
"why": {
  "v": 1,
  "rule": "softres",            // rule.model, ou "custom"
  "ruleAt": 1791000000,         // carimbo da regra em vigor (0 quando vem do sistema de loot)
  "decidedBy": "softres",       // chave do critério | "council" | "ml" | "only" (candidato único)
  "exception": "Thunderfury",   // nome da exceção que valeu; ausente sem exceção
  "candidates": [               // na ordem da regra, vencedor primeiro; no máximo 10
    { "name": "Chehul", "answer": "MS", "roll": 41, "bid": 0, "values": { "softres": 1, "account:plus1": 0, "attendance": 96 } },
    { "name": "Rias", "answer": "OS", "asked": "MS", "roll": 12, "bid": 0 }   // "asked": só quando um filtro trocou a resposta
  ],
  "votes": { "anon": false, "quorum": 2, "cast": [ { "by": "Kawa", "for": "Chehul" } ], "tally": { "Chehul": 2, "Rias": 1 } }   // ausente sem conselho
}
```

Com `anon`, `cast` é omitido e só o `tally` vai.

- **`ruleAt`:** o início da noite (`startsAt`) para a regra da noite; quando um oficial salvou pela
  última vez a regra própria do core (`lootAt`) ou da guilda (`lootRuleAt`); 0 para a regra pronta de
  um sistema de loot.
- **`decidedBy`:** a chave do critério que pôs o vencedor à frente do segundo quando o vencedor é o
  primeiro da ordem (`response`, `hardres`, `softres`, `prio`, `wishlist`, `received`, `attendance`,
  `points`, `pr`, `bid`, `roll`, `account`, `ratio`, `score`); `only` com um candidato só; `council`
  quando o vencedor é quem o conselho propôs; `ml` quando o master looter (no retail, o oficial ou o
  dono do item) deu o item a outro, decidiu por falta de quórum, entregou sem disputa (direto da
  janela de loot, ou destino fixo de uma exceção) ou quando todos os critérios empataram e nada na
  regra separou os dois.
- **`candidates`:** quem pediu (pass fica de fora), na ordem da regra, com o vencedor sempre em
  primeiro. `answer` é a chave da resposta, `""` quando o vencedor não respondeu (item entregue sem
  disputa: ele é então o único candidato). `roll` e `bid` vão sempre, 0 quando não houve. `name` é o
  nome curto do personagem; no retail é a chave `Nome-Reino`.
- **`asked`** (opcional, string, até 48 bytes como `answer`): a chave da resposta que o candidato
  clicou, antes de um filtro da regra lê-la como outra (presença abaixo do mínimo: MS vira OS).
  `answer` é sempre a resposta depois dos filtros, a que a ordem comparou. O campo só é escrito quando
  as duas diferem; ausente, `asked` = `answer`. É o que o simulador do site usa para refazer o prêmio
  sob outra regra a partir do que foi pedido. Quem um filtro deixou fora da rolagem não é candidato
  e não aparece.
- **`values`:** o que cada critério da ordem comparou além da resposta, da rolagem e do lance, que têm
  campo próprio. Chave = a do critério; `account:<conta>` para uma conta (para a conta de bônus da
  rolagem, o que ela somou). `softres` e `hardres`: 1 ou 0. `prio` e `wishlist`: a posição, ausente
  para quem não está na lista. `received`, `attendance`, `points`: o número. `pr`, `ratio`, `score`:
  com duas casas. Uma fila: a posição, ausente para quem não está nela. Ausente quando a ordem só tem
  resposta, rolagem e lance. Os valores são os de antes de o prêmio mexer em qualquer conta.
- **`votes`:** só quando um conselho votou naquele item. `quorum` é 0 quando a regra não pede um.
  `cast` em ordem de quem votou, só os votos válidos no fim (um voto retirado não aparece). `tally` por
  nome do candidato, só quem teve voto; **ausente quando ninguém votou** (o codificador escreve mapa
  vazio como lista, então mapa vazio nunca sai; o mesmo vale para `values`).
- **Limites:** nomes e chaves com até 48 bytes, 12 valores por candidato, 10 candidatos, 40 votos em `cast`: os mesmos da porta do site (guildos-web#517), que descarta o registro que passar deles.
- **`values` leva mais do que a regra comparou:** depois do que a ordem leu, entram os fatos que a linha do candidato já tem (reserva, lugar nas listas, itens recebidos, presença, pontos), até os 12. É o que deixa o simulador do site refazer o prêmio sob outra regra.

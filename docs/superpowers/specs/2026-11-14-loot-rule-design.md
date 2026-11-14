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

## O que o addon lê do contrato (#334)

`LootRule:Validate` aceita só o que este cliente aplica; o resto do contrato entra com a sua fatia.

- **`responses`** em objeto, `time` e `bid`. `label` tem até 24 bytes, sem `|`, `;` nem caractere de
  controle (viaja no anúncio e vira texto de botão). `cost` vai de 0 a 10. Campo ausente: `ask = "roll"`,
  `plus = false`, `cost = 1`, `label = key`.
- **`order`**: os critérios de antes, `bid` e `account` (com `acct` de uma conta declarada e `dir`).
- **`accounts`**: só `type = "counter"` (`key`, `name`, `reset`). As chaves `dkp`, `ep` e `gp` são dos
  pontos e não se declaram.
- **`effects`**: `add` numa conta contador, aplicado quando a resposta vencedora tem `plus = true`, e
  no máximo um `charge` com `price` `table` (o preço do item, o padrão), `fixed`, `bid` ou `second`.
  `second` é o maior lance vencido na mesma resposta mais um passo (`bid.step`), nunca acima do lance
  do vencedor; sozinho na resposta, o lance mínimo. Todo preço é multiplicado pelo `cost` da resposta.
- Modelos prontos novos em `GuildOS.LOOT_SYSTEMS`: `plus1`, `dkpbid` e `dkpsealed` (fora do retail,
  que não tem master looter). Escolher um sistema de loot volta à regra pronta dele.

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

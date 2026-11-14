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

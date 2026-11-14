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

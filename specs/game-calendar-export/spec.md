# Calendário do jogo e RSVPs no export do companion (`gameCalendar`)

Pedido por vários usuários (Excsuze, Volo, Paisley): ver no guildos.me os eventos da guilda que estão no
calendário do próprio jogo, e quem respondeu a cada um.

## Por quê

O site já recebe as raids que ele mesmo marcou (`GOSROST1`) e as põe no calendário do jogo
(specs/075, `GameCalendar`). O caminho inverso não existia: um evento criado direto no calendário do
WoW: Forever, e as respostas dadas pelos botões do jogo, nunca chegavam ao site.

## O quê

1. **Onde**: WoW: Forever apenas (`Compat.CalendarAvailable`). No TBC Anniversary e no retail o campo
   nunca aparece.
2. **Quem lê** (`Modules/CalendarSnapshot.lua`): o cliente de quem exporta, em segundo plano, guarda em
   `GuildOS.db.gameCalendar` o que o jogo mostra a esse jogador. O export é montado no logout, quando o
   jogo já não pode ser consultado: por isso a leitura é antecipada e guardada.
   * **A lista**: os eventos da guilda (`GUILD_EVENT`, com inscrição, e `GUILD_ANNOUNCEMENT`; nunca
     feriados nem eventos pessoais), de um dia atrás até 28 dias à frente, no máximo 40.
   * **Limite de chamadas**: a lista é pedida só por `Compat.CalendarRequest` (no máximo uma vez por
     minuto), numa passada a cada 15 minutos, a primeira 45 s após o login.
   * **Os detalhes** (descrição, criador, convites): o jogo só os entrega com o evento aberto. Um evento
     por vez, 5 s entre um e outro, no máximo 3 por passada, de novo só depois de 30 min; nunca em
     combate, nunca com a janela de calendário do jogo aberta, nunca com um evento aberto pelo Guild OS
     (a atualização em dois cliques do `GameCalendar`), nunca esperando outra resposta. Uma abertura sem
     resposta em 8 s é abandonada. Um evento diferente aberto no meio do caminho nunca é lido como este.
   * **A chave estável**: `e<id>` quando o cliente dá o id do evento (`eventID` do dia), senão
     `t<início>:<título>`. Uma nova leitura encontra o mesmo evento; um evento que sumiu da lista sai;
     um que ficou mantém os detalhes já lidos.
   * **O papel (role)**: o convite do jogo não traz papel. Quando a descrição tem a marca de uma raid do
     site (`guildos:<id>`, `GameCalendar.RaidIdIn`), vale o papel da inscrição no site
     (`Calendar:WebSignups`); se o cliente algum dia trouxer `role` no convite, ele vale primeiro. Sem
     nenhum dos dois, o campo fica ausente.
   * **Segredos**: um valor que o cliente marca como secreto (Secret Values) é deixado de fora; um
     convite com nome secreto não é listado.
3. **No export** (`GOSCOMP1`, payload **17**, sem mudar a versão): o campo `gameCalendar`, aditivo e
   ausente até o calendário ter sido lido neste cliente. Um site de antes nunca o lê; nada no resto do
   payload muda. Nunca vai no pacote do próprio personagem (`BuildSelf`). Se montar o bloco falhar, ele
   fica de fora e o resto sobe (`optional`, vai para `/guildos errors`).

## Contrato

Datas em segundos UTC (epoch). Textos já limpos de caracteres de controle (a descrição mantém `\n`),
cortados sem partir um caractere multibyte: título 64 bytes, descrição 512, nomes 64.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "goscomp/v17/gameCalendar",
  "type": "object",
  "required": ["at", "events"],
  "additionalProperties": false,
  "properties": {
    "at": { "type": "integer", "description": "quando a lista foi lida neste cliente (UTC)" },
    "events": {
      "type": "array", "maxItems": 40,
      "description": "o mais próximo primeiro (startsAt, depois key)",
      "items": {
        "type": "object",
        "required": ["key", "title", "startsAt", "calendarType", "guildEvent"],
        "additionalProperties": false,
        "properties": {
          "key": { "type": "string", "pattern": "^(e.+|t-?[0-9]+:.*)$", "description": "chave estável" },
          "eventId": { "type": "string", "description": "id do evento no jogo, quando o cliente dá" },
          "title": { "type": "string", "maxLength": 64 },
          "startsAt": { "type": "integer" },
          "calendarType": { "enum": ["GUILD_EVENT", "GUILD_ANNOUNCEMENT"] },
          "guildEvent": { "type": "boolean", "description": "true: evento da guilda com inscrição" },
          "eventType": { "type": "integer", "description": "Enum.CalendarEventType (0 raid, 1 dungeon, 2 PvP, 3 reunião, 4 outro)" },
          "description": { "type": "string", "maxLength": 512 },
          "creator": { "type": "string", "maxLength": 64 },
          "invitedBy": { "type": "string", "maxLength": 64 },
          "detailsAt": { "type": "integer", "description": "quando descrição, criador e rsvps foram lidos; ausente: ainda não" },
          "rsvps": {
            "type": "array", "maxItems": 200,
            "description": "ausente enquanto os detalhes não foram lidos; [] lido e sem convites",
            "items": {
              "type": "object", "required": ["name", "status"], "additionalProperties": false,
              "properties": {
                "name": { "type": "string", "maxLength": 64, "description": "como o jogo escreve (pode trazer o reino)" },
                "status": { "enum": ["invited", "accepted", "declined", "confirmed", "out", "standby",
                                     "signedup", "notsignedup", "tentative", "unknown"] },
                "role": { "type": "string", "description": "papel da inscrição no site (TANK, HEALER, DPS...), quando conhecido" }
              }
            }
          }
        }
      }
    }
  }
}
```

O mesmo em Lua, como `CalendarSnapshot:ForExport()` devolve:

```lua
gameCalendar = {
    at = 1795813200,
    events = {
        { key = "e4401", eventId = "4401", title = "Onyxia", startsAt = 1795896000,
          calendarType = "GUILD_EVENT", guildEvent = true, eventType = 0,
          description = "Fire resist.\nguildos:r42", creator = "Chehul", invitedBy = "Chehul",
          detailsAt = 1795813200,
          rsvps = {
              { name = "Chehul", status = "signedup", role = "TANK" },
              { name = "Mira-Costa", status = "declined", role = "HEALER" },
              { name = "Tess", status = "tentative" },
          } },
        { key = "t1795979700:Social night", title = "Social night", startsAt = 1795979700,
          calendarType = "GUILD_ANNOUNCEMENT", guildEvent = false },
    },
}
```

`status` vem de `Enum.CalendarStatus`: 0 invited, 1 accepted (Available), 2 declined, 3 confirmed,
4 out, 5 standby, 6 signedup, 7 notsignedup, 8 tentative; outro valor é `unknown`.

## Como o site deve ingerir

* Cada upload traz o que **aquele** jogador vê. Dois oficiais podem mandar listas diferentes: junte por
  `key` e fique com o bloco de `at` mais novo para a lista; para `rsvps`, com o de `detailsAt` mais novo.
* Um evento ausente de um upload com `at` mais novo, dentro da janela (um dia atrás a 28 dias), saiu do
  calendário do jogo. Fora da janela, nada se conclui.
* `rsvps` ausente não é "ninguém respondeu": é "não lido ainda". Mantenha o que havia.
* Uma raid do próprio site aparece aqui também (a descrição traz `guildos:<id>`): ligue pelo id, não a
  duplique.

## Testes

`tools/game-calendar-export.lua`: nada antes de o jogo ler o calendário; o pedido passa por
`Compat.CalendarRequest` (uma vez por minuto); feriado fora, chave pelo id ou por início e título,
bandeira de evento da guilda; um evento aberto por vez, lido e fechado; papéis do site numa raid do
site; nome secreto fora; detalhes novos não são relidos; nunca em combate, com a janela do jogo aberta
ou com um evento aberto pelo Guild OS; evento que sumiu sai, o que fica mantém as respostas; abertura
sem resposta é abandonada; outro evento aberto no meio nunca é lido como este.
`tools/companion-payload.lua`: o bloco ausente sem leitura, presente com os eventos em ordem, sem
`where`, e o JSON como o site lê.

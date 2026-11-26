# Convites, /who e sussurros: o que precisa de tecla (#449)

O jogo só deixa um addon fazer certas ações dentro de um **evento de hardware**: uma tecla ou um clique do
jogador. Vindo de um evento (um sussurro chegou) ou de um timer, a chamada é descartada em silêncio ou dá
`ADDON_ACTION_BLOCKED`. O Guild OS junta tudo isso numa **fila de ações do oficial** (`Modules/ActionQueue.lua`):
uma ação por tecla, ou por clique no aviso "Pressione [tecla] (ou clique) para convidar Fulano · N mais".

## O que diz a documentação

- [C_GuildInfo.Invite](https://warcraft.wiki.gg/wiki/API_C_GuildInfo.Invite): `#hwevent` em todos os clientes. O
  global `GuildInvite` saiu em 2.5.5, 1.15.2 e 10.2.6; `Compat.GuildInvite` usa `C_GuildInfo.Invite` e cai no global.
- [C_FriendList.SendWho](https://warcraft.wiki.gg/wiki/API_C_FriendList.SendWho): `#hwevent` desde 1.13.2.
- [SendChatMessage](https://warcraft.wiki.gg/wiki/API_SendChatMessage): sussurro e canal saem de timer no
  Anniversary; no WoW: Forever e no retail o jogo descarta (medido no #61, `Compat.NeedsClick`).
- [C_GuildInfo.Promote](https://warcraft.wiki.gg/wiki/API_C_GuildInfo.Promote) (e Demote, Uninvite): `#protected`.
  Só um botão seguro clicado roda `/gpromote`, `/gdemote`, `/gremove` (Ações em massa, `GuildOSBulkNext`).

## Por cliente

| Ação | TBC Anniversary | Retail | WoW: Forever |
|---|---|---|---|
| Convite de guilda (palavra-chave, chat Alt+clique, roster, pedidos) | automático (como antes) até o probe dizer o contrário | **tecla/clique** por convite | **impossível**: a linha `/ginvite Nome` para copiar |
| /who do filtro da palavra-chave | **tecla** (depois o convite) | **tecla** | não há filtro (a cópia é a checagem) |
| Convite de grupo (Raid Tools, "inv" nos Grupos) | automático | **tecla/clique** | **tecla/clique** |
| Sussurros do scanner, boas-vindas na guilda | automático | **tecla/clique** | **tecla/clique** |
| Promover, rebaixar, remover | botão seguro / tecla | botão seguro / tecla | a linha para digitar |

"Automático" é a suposição de `Compat.NeedsHardware`; o probe a substitui para a build medida.

## Impossível no WoW: Forever

O Forever 1.60.1.70790 recusa convite de guilda a addons por qualquer caminho (#256): a chamada
(`ADDON_ACTION_FORBIDDEN`, até de um clique), um botão seguro com `/ginvite` (`MACRO_ACTION_BLOCKED`) e a linha
deixada na caixa de chat (bloqueada, e a caixa fica contaminada até um `/reload`). Por isso, depois do sussurro com a
palavra-chave, abre uma janelinha com `/ginvite Nome` já selecionado: **Ctrl+C, Enter, Ctrl+V, Enter**. Nada é
escrito na caixa de chat.

## A tecla

Em **Teclas de atalho > AddOns > Guild OS**: "Guild OS: next in the queue" (`CLICK GuildOSQueueNext:LeftButton`,
`Bindings.xml`), ao lado de abrir/fechar a janela. Ou `/gos queue bind <tecla>` (`SetBindingClick`, nunca em
combate). Cada pressão faz **uma** ação: a próxima da fila; sem nada na fila, o próximo passo das Ações em massa; ou um
sussurro que a WhisperQueue segurava para um clique. A tecla aparece no aviso, no card de convite automático e nas
Ações em massa. `/gos queue` diz o que espera; `/gos queue clear` esvazia.

O aviso é uma janela flutuante do Kit, móvel (lembra o lugar), fechável (volta com a próxima ação), aberto por
`GuildOS:ShowWhenClear` e escondido em combate.

## O probe: `/gos debug probe invite`

Mede, por cliente e build, se convite de guilda, convite de grupo, /who, sussurro e linha de canal funcionam (a)
da tecla (o Enter do comando) e (b) de um timer 6 s depois. Ninguém é convidado nem sussurrado: convites e sussurro vão
para um nome que nenhum personagem pode ter (letras e dígitos, "Gosprobe4821"), e a resposta "não encontrado" com esse
nome prova que a chamada rodou; o /who pede esse nome (vale o `WHO_LIST_UPDATE`); a linha de canal vai para um canal
temporário só seu. No Forever o convite de guilda não é tentado (proibido; a tentativa mostraria o erro). Resultado:
`true` (respondeu), `false` (bloqueado) ou `"silent"` (sem resposta), em `GuildOSDB.probeInvite`, que
`Compat.NeedsHardware` lê **só na mesma build**. Guarda também quais APIs de tabardo existem.

## O tabardo no brasão

O brasão da barra de título desenha o tabardo da guilda: primeiro o desenho do próprio jogo
(`SetLargeGuildTabardTextures`, mascarado redondo com `SetMask` e a arte `circle`), senão as cores e o emblema de
`C_GuildInfo.GetGuildTabardInfo` ou `GetGuildLogoInfo`; sem nada, a inicial. Redesenha em `PLAYER_GUILD_UPDATE` e
`GUILD_ROSTER_UPDATE`. `/gos debug probe` imprime `tabard: <API usada ou "none: motivo">`.

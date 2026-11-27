# Teste da aliança em jogo, com duas guildas (#449)

Um roteiro curto para o primeiro teste com as duas guildas. Ele segue o que `tools/alliance-two-guilds.lua` já
simula: as duas guildas, os oficiais com o companion, membros sem o companion, reload, relog e a troca de chave.

## Antes de começar

- **Todos na mesma versão do Guild OS.** Os clientes desta versão falam o protocolo 2 no canal (cada linha leva o
  nome da guilda). Uma versão anterior não lê essas linhas e entra noutro canal. Confira com
  `/gos ally status`: a primeira linha termina em `protocol 2`.
- **Quem precisa do companion:** pelo menos um oficial de cada guilda, com o companion ligado e sincronizado depois
  que a aliança foi criada no guildos.me. Os membros não precisam: o código chega a eles por um oficial que esteja
  online.
- **No guildos.me:** a aliança criada, as duas guildas dentro dela, e o companion de cada oficial atualizado
  (ele traz o `GOSGILD1` com o código e o `GOSALLY1` com o diretório e as raides abertas). Depois, `/reload` no jogo.

## Guilda A (Filhos da Horda) e guilda B: os mesmos passos

1. **O oficial com o companion** faz `/reload` e espera uns 30 segundos.
   - `/gos ally status` deve mostrar `source: site`, `key version: N` e `joined: yes`.
   - Salão › Aliança mostra o nome da aliança e as duas guildas pelo nome.
   - Sala dos Oficiais › Aliança diz "From guildos.me" com o nome da aliança, sem campo para colar.
2. **Um membro sem o companion** entra (ou faz `/reload`) com o oficial online.
   - Em até um minuto, `/gos ally status` mostra `source: relay` e `joined: yes`.
   - Sem nenhum oficial online, o Salão diz que o código chega quando um oficial com o companion entrar. Quando o
     oficial entrar, o código chega sozinho, sem novo reload.
3. **O /g compartilhado.** Alguém de A escreve no /g: `oi pessoal da ordem`.
   - Em A, a linha aparece uma vez, como sempre.
   - Em B, ela aparece **uma vez** no chat da guilda, com o nome real da guilda na frente:
     `[Guild] [Filhos da Horda] Duda: oi pessoal da ordem`.
   - Nunca `[Allied guild]` / `[Guilda aliada]`. Se aparecer, anote quem falou e mande o status (abaixo).
   - Responda de B e confira o mesmo em A, com `[Nome da guilda B]`.
   - Com vários membros de A online, B continua vendo a linha uma vez só.
4. **Linha longa e link.** Cole um link de item e escreva até encher a caixa de texto. Em B, a linha chega em duas
   partes, com o link inteiro e clicável. Acentos (ç, ã) não quebram.
5. **A sala da aliança** (Salão › Aliança › Sala da aliança). Escreva de A e de B. Cada lado vê a linha uma vez,
   com o nome e a guilda de quem falou. A sala é separada do /g: nada dela aparece no chat da guilda.
6. **O botão "Allied /g"** (cada jogador). Desligue num membro de B: o /g de A some só para ele, a sala continua,
   e o /g dele ainda chega a A. Ligue de novo. Pelo chat: `/gos ally gchat off` e `/gos ally gchat on`.
7. **Bloquear uma guilda** (oficial). Em A, Sala dos Oficiais › Aliança › bloqueie a guilda B (maiúsculas não
   importam). O /g e a sala de B somem nesta conta. Desbloqueie e confira que voltam.
8. **Online agora.** O Salão de A mostra os de B que falaram no canal, e, com o diretório do site, também quem entrou
   no canal. Quem sai do jogo some da lista.
9. **Raides abertas e banimentos** (oficial com o companion). As raides abertas de B aparecem no Salão de A, com "as
   of" e quem lidera. Convidar para a guilda alguém que B baniu e compartilhou mostra o aviso antes.
10. **Reload e relog.** Um membro faz `/reload` no meio da conversa: o /g compartilhado continua sem esperar. Outro
    sai e volta: em até um minuto `joined: yes` de novo.
11. **WoW: Forever:** um personagem com sobrenome (também com hífen no sobrenome) fala no /g e na sala. Do outro
    lado aparece o nome inteiro, `Ana Lima`, e não só `Ana`. A própria linha dele não aparece duas vezes na sala.
    **TBC Anniversary:** um personagem de outro reino aparece como `Nome-Reino`, e um homônimo de outro reino não é
    confundido com você.

## Troca de chave (tirar B da aliança no site)

1. No guildos.me, remova B da aliança. O site gera uma chave nova (`key version` sobe).
2. O oficial de A sincroniza o companion e faz `/reload`. Em A, todos (com e sem companion) passam ao canal novo:
   o status mostra outro `channel:` e a versão nova.
3. O oficial de B sincroniza e faz `/reload`. O status de B mostra `alliance: none`; o Salão de B diz que a guilda
   não está numa aliança. Os membros de B online saem do canal em seguida.
4. Um membro de B que estava offline e volta sem nenhum oficial de B online fica sozinho no canal antigo: o /g dele
   não chega a A, e ele não vê A. Quando um oficial de B entrar, ele sai da aliança.
5. Teste rápido: um de B escreve no /g; ninguém de A vê.

## Código colado (sem o site)

Para um teste só de chat: um oficial de cada guilda cola o **mesmo** código em Sala dos Oficiais › Aliança e salva.
Os membros recebem pela guilda. O /g compartilhado e a sala funcionam, com as guildas pelo nome; membros, artesãos,
raides e banimentos só vêm do guildos.me.

## Se o canal não entrar

As telas dizem o motivo e o que fazer:
- **chave recusada** (`WRONG_PASSWORD`): as guildas não têm o mesmo código. Confira no site ou cole o mesmo código.
- **nome recusado** (`INVALID_NAME`): use uma tag mais curta, só letras e números.
- **sem resposta** (`NO_ANSWER`): `/reload`; se continuar, mande o status.

## O que mandar ao mantenedor se algo falhar

Em cada personagem envolvido (quem falou e quem não recebeu):

1. `/gos ally status` — copie todas as linhas. Exemplo:

   ```
   alliance: Pacto da Horda [FDH] · source: relay · key version: 1 · protocol 2
   channel: GOSAFDHk3x9qa · joined: yes (#5)
   shared /g: shown · room: on · sent 3 · unsent 0 · heard 12 · shown 9 · dropped 0
     Ordem do Dragão: last /g line 42s ago from Caio (protocol 2)
   ```

   O status nunca mostra a chave. `unsent` conta as linhas que não cruzaram por bloqueio de chat (combate no
   Forever); `dropped`, as linhas do canal que não eram de nenhuma guilda conhecida.
2. `/gos debug probe channel` e `/gos debug errors`.
3. A hora, a versão do jogo (Forever ou Anniversary), quem tem o companion, e o texto exato que apareceu (ou não).

# Alts: como um vínculo nasce, se confirma, viaja e se desfaz (#449)

## Por quê

O mantenedor: "a pergunta para vincular um alt fica aparecendo sem parar". O aviso de login ("Encontramos N
personagens seus nesta guilda. Vincular como alts de X?") voltava a cada login, a cada /reload e em cada
personagem da conta ("Agora não" valia só para a sessão); um "Não perguntar de novo" valia para aquele conjunto
exato de personagens, então um alt novo trazia de volta o grupo inteiro. Cinco personagens, login e /reload em
cada um, três dias de "Agora não": **30 avisos**. Agora: **3** (um por dia, no máximo três), os cinco num só.

## De onde vem um vínculo

1. **A própria conta** (`AltAutoDetect`): cada personagem grava-se em `GuildOSDB.accountChars` (a raiz do
   SavedVariables, comum à conta). Os da conta que estão na guilda e ainda não formam um grupo são a pergunta.
   Só os próprios alts: nenhuma API revela a conta de outro jogador.
2. **A ficha do membro**, seção "Personagens vinculados": um campo **Adicionar alt** (sugere o nome do roster),
   **Definir como main** e **Desvincular** em cada linha; o oficial ainda tem **Promover alts** / **Rebaixar
   alts**. No seu próprio cartão, **Detectar meus alts** (`/gos myalts`).
3. **O oficial** em qualquer cartão (`LinkAlt`, `SetMain`, `UnlinkAlt`). Não há leitura de nota de oficial
   ("alt de X") nem heurística de nome.

## A pergunta (uma só)

"Estes personagens estão na sua conta: A, B, C." / "Vincular como alts de [main ▾]" — **Vincular todos** ·
**Escolher...** (um visto por personagem, então **Vincular selecionados**) · **Agora não** · **Não perguntar de
novo**. O fechar e o Esc são um "Agora não".

- O main sugerido é o grupo que a conta já tem (o com mais personagens dela), senão o de maior nível (empate:
  a chave). Escolher outro main põe o sugerido na lista.
- Vincular sob um personagem que é alt: o grupo todo passa para ele (um re-main, nunca alt de alt).
- As respostas são **da conta e por par de personagens** (`GuildOSDB.altAsk.pairs["a|b"]`): `d = "link"`
  (vinculados aqui), `"no"` (Não perguntar de novo, ou sem visto em Escolher...), `"linked"` (vistos num grupo),
  `"gone"` (perguntado três vezes sem resposta). `n`/`at`: quantas vezes **apareceu** e quando. Aparecer conta,
  não responder: um /reload com a janela aberta é um "Agora não".
- Um par volta no máximo **uma vez por dia** e **nunca mais de 3 vezes**. Um personagem já respondido (ou já num
  grupo) fica de fora quando há um nunca perguntado: um alt novo é perguntado sozinho.
- **Nunca reabre** um par decidido: troca de main, renomear, sync de outro oficial (um desvínculo do oficial é a
  palavra dele), sair e voltar à guilda, um `/gos reset`. O "Não perguntar de novo" antigo (por grupo) vira pares.
- No máximo uma vez por sessão, 20 s depois do login, pela fila de popups (`GuildOS:ShowWhenClear`): nunca em
  combate, depois dos popups do login, um de cada vez. Quando chega a vez é recalculada: o que mudou na espera não
  é perguntado e não conta.
- **Detectar meus alts** / `/gos myalts` pergunta por todos fora de um grupo, seja qual for a resposta, sem contar.
  `/gos myalts reset` esquece as respostas.

## Quem confirma, como viaja

- **Oficial**: escreve direto no `AltSync` (uma entrada por alt, revisão `max(agora, última + 1)`, lápide no
  desvínculo, domínio `alt` do SyncService; specs/alt-links). A edição mais nova vence em todo cliente; dois
  oficiais ao mesmo tempo no mesmo alt chegam à mesma resposta; uma cadeia (A diz que B é main de X, B diz que C é
  main de B) é achatada (X e B sob C) e um laço fica com a menor chave como main, igual em todos.
- **Membro**: aplica na própria vista e manda um pedido (`SELF_ALT`) com o grupo inteiro, que tem de incluí-lo;
  o pedido espera (30 dias, reenviado uma vez por sessão com um oficial online) até a lista dos oficiais o ter
  ou uma edição mais nova de oficial o recusar. Um alt pode desvincular um irmão do mesmo main (antes era recusado
  e reenviado por 30 dias).
- **O site** (`CompanionExport`, `main` de cada membro) lê a vista dos oficiais (`AltSync:BaseView`), nunca o
  pedido de um membro ainda não aceito: o site vê o que todo oficial vê, quem quer que exporte.

## Lacunas fechadas

- **Adicionar alt** procura o nome no roster (qualquer caixa; no WoW: Forever "Chehul-Costa" do chat é "Chehul
  Costa"; homônimos de reinos conectados: o do reino do cartão) e recusa quem não está na guilda. No cartão de
  um alt, vincula ao main do grupo (o `LinkAlt` recusava; o pedido do membro era descartado pelos oficiais).
- **Renomeado**: o mesmo GUID com outro nome; os vínculos e as respostas passam ao nome novo (oficial escreve;
  membro pede). Transferência de reino troca o GUID: é um personagem novo, perguntado como qualquer outro.
- **Main fora da guilda** sem ninguém ter visto a saída: no login de um oficial, com o roster inteiro, o primeiro
  grupo assim recebe a mesma pergunta de "um main saiu" (Definir A como main / Desvincular / Manter), uma vez por
  sessão, no máximo 3 vezes; "Manter" é para sempre neste cliente. A saída vista ao vivo continua no
  `AltDeparture` (#426). Nada é promovido sozinho.
- **Contagem única**: o roster ("jogadores reais"), os cores e os aniversários leem `db.altLinks` já achatado;
  um alt cujo main saiu continua contado como um jogador. Presença e DKP são por personagem (não deduplicam).

## Limites conhecidos

- Um cliente sem o SavedVariables (outro PC, pasta WTF nova) não conhece as respostas: pergunta de novo, com o
  mesmo limite (uma vez por dia, três no máximo), e só depois de dois personagens da conta logarem nele.
- O pedido de um membro só é aplicado quando enviado por um personagem do grupo; os outros esperam o próximo
  login num deles.

## Testes

`tools/alt-prompt.lua` (contagem de avisos, recusa durável, limite, pergunta única, Escolher..., renomeado,
Adicionar alt, main fora da guilda, exportação), `tools/alt-sync.lua` §14 (cadeia, laço, desvínculo propagado,
desvínculo de irmão), `tools/alt-autodetect.lua`, `tools/room-cards.lua` (a janela).

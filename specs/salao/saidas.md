# Saídas e retornos (issue #449, sugestão de um apoiador)

O mantenedor aprovou a sugestão: quando alguém sai ou é removido, os oficiais decidem ali mesmo o que fazer com o
jogador; quando alguém volta, a guilda o reconhece ("bem-vindo de volta", não "bem-vindo, novato").

## 1. A janela de saída (`Modules/Departure.lua`, `UI/DeparturePopup.lua`)

- **Quem vê:** todo oficial online com o Guild OS (o limiar de oficial da guilda), em todo cliente. Um membro nunca.
- **O que dispara:** a linha do jogo lida pelo Roster Log ("saiu" / "foi removido por") e, quando ninguém neste
  cliente viu a linha, o diff do roster do MemberHistory ("não está mais na guilda").
- **Um acontecimento, uma janela:** o mesmo membro dentro de `Departure.SAME` (15 min, a mesma regra de
  `ROSTER_SAME` da atividade do Salão, `UI/Agora.lua`) é o mesmo acontecimento, venha primeiro a linha ou o diff;
  a linha de remoção depois de um diff só acrescenta quem removeu. Várias saídas de uma vez: uma janela só, com
  "1 de 3" e o botão Próximo.
- **A janela:** flutuante do Kit (`Kit:Float`), no topo central, móvel, lembra o lugar (`departurePopupPos`),
  aberta só por `GuildOS:ShowWhenClear` (nunca em combate, uma de cada vez). Cabeçalho "<Nome> saiu da guilda" /
  "<Nome> foi removido por <oficial>".
- **Os personagens do jogador:** pelos vínculos de alt (`GuildOS:GetLinkedChars`), o principal primeiro, cada um
  na cor da classe (a classe vem do roster; de quem já saiu, da linha de membro enquanto existir e depois da
  classe guardada no histórico, `MemberHistory:ClassOf`), com "na guilda" / "já saiu" e uma caixa marcada para
  quem ainda está na guilda (o próprio personagem do oficial nunca).
- **Remover selecionados:** entra na fila de remoção das Ações em massa, um membro por clique do Próximo
  (ADR-0038); o addon nunca chama a API protegida. No WoW: Forever, onde nenhum addon remove ninguém
  (`Compat.SecureGuildMacro`), a janela mostra as linhas `/gremove Nome` para copiar, uma de cada vez, como a
  janela do `/ginvite`. Sem permissão de remover: o motivo (`BulkActions:WhyText`).
- **Nota permanente dos oficiais:** gravada no histórico durável do membro (`db.memberHistory[key].note`), vista
  na seção de histórico da janela do membro e no cartão da folha dos oficiais (de qualquer personagem do jogador,
  `MemberHistory:NoteFor`). Vai só pelo canal OFFICER (domínio `hnote`, como a folha dos oficiais); sem esse
  canal (Forever) fica neste cliente. A revisão mais nova vence; o backfill de login reenvia as 40 mais novas.
- **Marcação:** "Sem marcação / Banir para sempre / Suspender por [N] dias" (1 a 365): `BanList:AddGroup` para
  todos os personagens do jogador, com o motivo "Banido ao sair" / "Suspenso por N dias ao sair". O ban então
  avisa no convite e na entrada como qualquer ban.
- **Salvar / Dispensar:** Salvar grava, bane e avisa os outros oficiais (`audit` ação `dh`, pelo GUILD, sem texto
  livre: membro, momento, marcação e dias); na janela deles aparece "Resolvido por <oficial>" e, depois de
  `Departure.LINGER` segundos, ela passa ao próximo ou fecha. Dispensar só fecha neste cliente. As resoluções
  ficam 30 dias (`db.departure.handled`) e as 15 mais novas vão no backfill: o oficial que entra depois não é
  perguntado sobre o que já foi resolvido.
- **Chave liga/desliga:** Sala dos Oficiais › Marcas › "Lista segura e apelidos": "Perguntar quando alguém sai ou é
  removido" (configuração deste cliente, `departurePopup`, ligada por padrão).
- Com a janela ligada, a pergunta antiga "alts ainda na guilda" (`AltDeparture`, só no cliente de quem removeu)
  não aparece: seria a segunda janela sobre a mesma remoção. A pergunta "um principal saiu" continua.

## 2. Bem-vindo de volta

- **Detecção:** o MemberHistory já sabe quem foi membro (`rejoin` no Roster Log). `MemberHistory:ReturnInfo` dá a
  data da saída, os dias fora e os dias de guilda antes, lido antes de a entrada abrir uma passagem (a linha do
  jogo, o diff) ou logo depois (a mensagem de boas-vindas).
- **Aviso aos oficiais:** janela "Bem-vindo de volta: <Nome>": "saiu em <data> e voltou depois de X dias; foi
  membro por Y dias antes", a última remoção e a nota permanente. Banido ou suspenso: o título vira o aviso em
  vermelho ("<Nome> está suspenso até <data>" / "está banido") com o motivo, e o resto embaixo. A linha antiga no
  chat continua.
- **Mensagem da guilda:** Sala dos Oficiais › Recrutamento › cartão Boas-vindas: uma segunda lista "Para membros
  que voltam", com `{name}`, `{guild}`, `{days}` (dias fora) e `{since}` (data da saída). Vazia: vale a de
  sempre. Várias entradas de uma vez: a de sempre para todos.
- **Janela do membro:** a seção "Membro · N dias na guilda" já lista cada passagem; agora com a nota permanente
  no topo.
- **Durabilidade:** o histórico vive fora do Roster Log (90 dias) e da linha de membro (que sai com o membro,
  #203); chave pelo nome do roster (o "Nome Sobrenome" inteiro no Forever, com o reino no retail). O teto de
  4000 membros nunca descarta quem tem nota.

## 3. A mensagem de boas-vindas é da guilda (pedido do mantenedor)

- O interruptor, as mensagens (as normais e as de quem volta), o Discord e o final "/gos rules" viajam juntos
  como uma foto nas configurações de oficial (`guildcfg` ação `welcome`, pelo GUILD, que o Forever tem),
  assinada pelo oficial (o SyncService confere), carimbo mais novo vence; carimbo igual, o autor de nome menor.
  Vai na mudança, no envio periódico dos oficiais e na resposta a um pedido de sync.
- Primeira vez: um oficial cujo cliente tem boas-vindas que a guilda nunca carimbou as compartilha com o carimbo
  mínimo (`MIGRATE_REV`), e qualquer mudança real vence.
- O cartão diz "Compartilhado com os oficiais · última mudança por <oficial>, <hora>".

## 4. Uma mensagem de boas-vindas por entrada (pedido do mantenedor)

Causas das duplicadas: o desempate antigo comparava nomes com e sem reino/sobrenome escritos de jeitos
diferentes em cada cliente; a intenção ia em NORMAL atrás do tráfego de sync e chegava depois dos 2 s; cada
cliente lia a linha do jogo num momento; um /reload esquecia que já tinha dado as boas-vindas.

Agora, sem corrida: cada cliente lê o mesmo roster e ordena os oficiais online pelo nome sem reino, em
minúsculas (o "Nome Sobrenome" do roster); o primeiro envia `WELCOME_FIRST` (1 s) depois da linha, cada um dos
seguintes `WELCOME_STEP` (5 s) depois do anterior e só se nenhum aviso chegou (o primeiro está offline de um jeito
que o roster ainda não mostrou, não roda Guild OS, ou roda uma versão antiga). Aviso e intenção vão em ALERT; a
intenção continua indo para o desempate das versões antigas. Um aviso enviado ou ouvido marca o membro como
recebido por 10 min (`welcomedAt`, guardado no db: vale depois de um /reload). O diff do roster nunca dá
boas-vindas, só a linha do jogo. No Forever (o clique envia), dois oficiais que se acharam primeiros se acertam
pelos avisos, o nome menor fica com a janela.

## Testes

- `tools/departure.lua`: um acontecimento por saída (linha dupla, diff, remoção depois do diff, fora da janela de
  15 min), a lista de personagens, a fila um-por-clique, as linhas do Forever, o motivo sem permissão, a nota
  (limpa, só pelo OFFICER, só para oficiais, no alt também), a suspensão pelo BanList, "Resolvido por" fechando a
  janela do outro oficial, o backfill para quem entra depois, a chave desligada, o bem-vindo de volta (aviso, ban,
  placeholders, volta à mensagem normal), a durabilidade e o sobrenome na chave.
- `tools/welcome-election.lua`: três oficiais (sobrenomes, um com clique, latências diferentes), o primeiro
  offline, o primeiro sem Guild OS, um oficial em versão antiga (primeiro ou último), dois que se acham primeiros,
  a linha repetida e o /reload: sempre uma mensagem; e as boas-vindas compartilhadas (primeira vez, edição, carimbo
  velho, texto recusado).

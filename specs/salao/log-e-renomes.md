# Log da guilda, renomes e filtros do Registro (pacote 2, inspirado no Guild Roster Manager)

Quatro melhorias no que os oficiais sabem sobre quem entra, sai, muda de cargo ou de nome, e no que o chat mostra.

## 1. O log de eventos da guilda do jogo (`Modules/GuildEventLog.lua`)

O Roster Log ouve as linhas de sistema só enquanto o oficial está online; o diff do roster (`MemberHistory:Scan`)
vê o que mudou desde o último login, mas não quem fez. O jogo guarda o próprio "Log da guilda" (convite, entrada,
promoção, rebaixamento, remoção, saída), cada linha com "há quanto tempo" em anos, meses, dias e horas.

- **API:** `QueryGuildEventLog()`, resposta em `GUILD_EVENT_LOG_UPDATE`; `GetNumGuildEvents()` e
  `GetGuildEventInfo(i)` → `tipo, jogador1, jogador2, cargo, anos, meses, dias, horas` (tipo `invite`, `join`,
  `promote`, `demote`, `remove`, `quit`; o tempo é "atrás"). Tudo passa por `Core/Compat.lua`
  (`Compat.HasGuildEventLog`, `Compat.QueryGuildEventLog`, `Compat.GuildEventLog`), que procura primeiro em
  `C_GuildInfo` e depois nos globais e responde nil/false quando o cliente não tem: nesse caso nada acontece e
  nada é dito. `tools/compat-guard.lua` proíbe os globais fora do Compat.
- **Clientes:** o evento `GUILD_EVENT_LOG_UPDATE` consta nos builds standard 12.1.5, forever 1.60.1, mists 5.5.4,
  tbc 2.5.6 e vanilla 1.15.9 (warcraft.wiki.gg). As funções globais são as da UI clássica (wowprogramming.com);
  o varejo manteve os globais. `/gos debug probe` grava `guildEventLog` e imprime "guild event log: sim/não";
  as três funções estão no inventário do probe e o evento na lista de eventos.
- **Quando:** uma pergunta por login, no cliente de um oficial, na guilda do banco carregado, depois de o roster
  assentar e o primeiro diff rodar (`MemberHistory.SETTLE_SECONDS` + 15 s; espera o diff até 6 × 30 s). Em
  combate não pergunta: pergunta ao sair do combate. Uma resposta que chega em combate é guardada e lida depois.
  Só a resposta à própria pergunta é lida (a janela do jogo ou outro addon também pedem o log).
- **Mesclagem no Registro (audit log):**
  - tempo aproximado = agora − "há quanto tempo" − 30 min (o meio da hora do jogo); tolerância de 2 h quando o
    jogo diz horas/dias, 3 dias quando diz meses (um mês contado como 30 dias);
  - uma linha já existente da mesma ação e do mesmo membro dentro da tolerância (uma linha do diff, vista depois
    do fato, vale de 30 dias antes até a tolerância depois) recebe o oficial que faltava: quem convidou uma
    entrada, quem removeu um "Sumiu" (que vira "Removido"), quem mudou o cargo. O histórico do membro segue
    (`MemberHistory:FromLog`): a saída ganha o tempo e o autor, o cargo ganha o autor, a passagem ganha `inv`;
  - o que ninguém aqui viu entra como evento aproximado (`approx = true`, `tol`), mostrado com "~" depois da hora,
    e vai aos oficiais como qualquer evento que este cliente acrescenta (domínio `audit`, ação `add`);
  - a cópia que outro oficial manda da mesma linha do jogo (tempos uma hora diferentes) se funde com a daqui
    (`RosterLog:_Insert`, regra dos aproximados): não há duplicata entre oficiais nem no próximo login;
  - linhas com mais de 90 dias (o limite do Registro) são ignoradas, para o log antigo de uma guilda quieta não
    voltar a cada login.
- **"Convidado por X"** aparece na seção de histórico da janela do membro (`UI/MemberDetail.lua`), em cada
  passagem cujo convite o log informou.

## 2. Renomes de qualquer membro (`Modules/MemberRename.lua`)

Uma troca de nome paga mantém o personagem e muda a chave; tudo que o Guild OS guarda por chave ficaria com um
nome que ninguém mais tem.

- **Detecção, no mesmo diff do roster** (`MemberRename.Pairs`, linear no tamanho do roster):
  - **GUID** (17º retorno de `GetGuildRosterInfo`, via `Compat.GuildRosterGUID`; o instantâneo do roster guarda
    `g` e a classe `c`): mesmo GUID com outro nome → renome, migrado na hora, sem perguntar. Transferência de
    reino muda o GUID: é saída e entrada;
  - **sem GUID** dos dois lados: exatamente um "sumiu" e um "novo" no mesmo diff, mesma classe, mesmo cargo,
    nível ±1 e nota pública ou de oficial idêntica e não vazia → provável renome. Uma pergunta ao oficial, pela
    fila de janelas (`GuildOS:ShowWhenClear`, nunca em combate, uma de cada vez), uma vez por sessão para o par:
    "Xyz parece ser Abc com outro nome. Mover o histórico, os alts, o banimento e as marcas de Abc para o novo
    nome?" Enquanto não há resposta, as duas chaves ficam fora do diff e do instantâneo. **Mover** migra tudo;
    **Não é o mesmo** (ou fechar) é lembrado 180 dias (`db.memberRenames.declined`) e o diff seguinte registra a
    saída e a entrada como sempre.
- **O que migra** (`MemberRename:Apply`):
  - pela API do próprio módulo, sincronizado com revisão/tombstone: vínculos de alt (`AltAutoDetect.PlanRename`
    + `AltSync:Commit`, o mesmo plano do renome do próprio jogador em `AltAutoDetect:CheckRename`), ban
    (`BanList`: o novo nome banido igual, o antigo levantado por tombstone, a nota do oficial mantida), marca de
    lista segura e apelido (`MemberMarks`), ficha do oficial (`OfficerNotes:SetSheet`, a antiga esvaziada), teste
    (`TrialTracker`, a antiga vira tombstone e as duas são enviadas), aniversário (`Birthdays`, a antiga vira
    tombstone);
  - neste cliente (cada oficial vê o mesmo diff e migra o seu): histórico do membro (passagens, cargos, nota
    permanente, classe; somado ao que a chave nova já tivesse), notas datadas dos oficiais, presença em raide
    (sessões e presença calculada), "visto pela primeira vez", data de fundação (Forever), dados do membro
    (`db.members`), raiders;
  - o Registro ganha uma linha "Renomeado": "Xyz renomeado de Abc" (deste cliente).
- **Fora do escopo:** o registro disciplinar (`Discipline`, avisos sincronizados por id) e as contas de pontos
  continuam na chave antiga.

## 3. Filtros do Registro de Auditoria (`UI/ManagementPanel.lua`, `BuildLogSub`)

- **Chips com contagem** acima da busca: Entradas, Saídas (inclui "Sumiu"), Remoções, Mudanças de cargo, Níveis,
  Notas (pública e de oficial), Retornos, Renomeações, Todas. A busca estreita as contagens também.
- **Apagar linha** (oficiais): o botão aparece ao passar o mouse na linha, no lugar da coluna "Por". O domínio
  `audit` é só de acréscimo, sem tombstone: a linha some **só neste cliente** (uma nota no cartão diz isso), e o
  cliente lembra dela (`db.rosterLog.hidden`, até 500) para recusá-la quando um backfill ou o log do jogo a
  trouxer de volta.
- **Memória:** a lista agora é virtual (`MakeVirtualList`): só as linhas que cabem existem, reaproveitadas a cada
  rolagem, busca, filtro e redimensionamento. Antes, cada atualização criava uma linha de frames por entrada (até
  1500) e só escondia as antigas, e o `RosterLog.uiRefresh` disparava em todo evento mesmo com a aba escondida
  (~150 MB relatados no jogo). Agora um evento com a aba escondida só marca a lista como desatualizada; ela é
  redesenhada no `OnShow`.

## 4. Marca de main/alt em sussurros, grupo e raide (`Modules/ChatTweaks.lua`)

- Configurações › Chat e alertas: "Também em sussurros de membros da guilda" e "Também no chat de grupo e raide"
  (desligadas por padrão), já existentes desde o #429; o mesmo prefixo de guilda/oficiais.
- Só para remetentes conhecidos: membros da guilda e os personagens ligados a eles pelos vínculos de alt (mesmo
  fora da guilda, só com a marca de alt).
- Desempenho: nenhuma tabela por mensagem. A chave do autor e o prefixo de cada remetente ficam em cache por
  atualização do roster; o prefixo é refeito quando muda uma configuração, um apelido ou um vínculo de alt
  (`ChatTweaks:Invalidate`, chamado por `MemberMarks:Refresh` e `AltSync:Refresh`).

## Testes

`tools/guild-event-log.lua` (API ausente, mesclagem com autores, deduplicação, sem duplicata no login seguinte,
combate, linha apagada, cópia de outro oficial, membro não pergunta), `tools/member-rename.lua` (pares, GUID
migra sozinho, heurística pergunta uma vez, migra no sim e não no não, cada store migrado),
`tools/member-history.lua` (convidado por, aproximados, apagar), `tools/note-dates.lua` (prefixo em sussurro,
grupo e raide só quando ligado, cache por remetente, alt fora da guilda), `tools/engagement-panel.lua` (lista
virtual: 50 eventos com a aba escondida criam 0 frames, atualizações e digitação na busca criam 0 frames, chips
contam e filtram), `tools/probe.lua` (72 eventos, linha do log da guilda).

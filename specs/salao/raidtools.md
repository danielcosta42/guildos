# Raides › Ferramentas de raide (#449)

## Por quê

A tela antiga contava classes dos membros **online da guilda** e listava bônus e cooldowns: não respondia nada
do que o líder de raide precisa às 21:58. O mantenedor pediu a ferramenta inteira para os quatro momentos da
noite, com uma regra: **o que aparece em combate é mínimo, escondível, e as pessoas têm que querer usar**.

## A tela

Um card escuro no topo com o título e "· origem · N jogadores", e nele:

- **Origem**, escolhida na hora: *Grupo atual* / *Raide do site* (a próxima ou a escolhida, do companion:
  `GOSROST1`, `CompanionImport:RosterOf/ActiveRoster`) / *Membros online*. Fica salva.
- **Raide**: as raides do site (título · data) quando a origem é o site; senão as raides deste jogo (TBC: Kara,
  ZA 10; Gruul, Mag, SSC, TK, Hyjal, BT, SWP 25. Forever: Onyxia 40, a única que o `RaidTracker` conhece; as
  outras chegam pelo site e usam as metas do tamanho). Sem nada escolhido: a instância onde estou, ou o tamanho
  principal do jogo.
- **Pílulas** das quatro partes: Montar · Grupos · Prontidão · Luta.

Embaixo, na madeira, cards em duas colunas (uma sob a outra abaixo de 620px de conteúdo).

| Parte | Esquerda (papel) | Direita (escuro) |
|---|---|---|
| **Montar** | Quem vem: nome na tinta da classe, função (`*` = palpite pela classe), inscrição (inscrito / reserva / talvez / sem resposta / não inscrito), grupo (G3) ou "Convidar · faltando" | Funções em blocos "x de meta" (vermelho quando falta), metas − / + por raide, **Convidar quem falta** (primário), Anunciar o que falta; card de bônus e cooldowns |
| **Grupos** | Os grupos como caixas de nomes (pílulas) com o que cada um traz: totens, aura, grito; o que falta em vermelho. Clique num nome e depois no grupo; dois nomes trocam | Aplicar (primário), Sugerir, Anunciar, Como está |
| **Prontidão** | Por pessoa: estado, consumíveis, encantos, sintonização da raide, resistência da luta (SSC natureza, TK arcano, BT sombra), addon | Resumo, Ready check (primário), Role check, Checar consumíveis, Anunciar o que falta |
| **Luta** | Chefe; linhas marca · tarefa · jogador · ×; Anunciar (primário), Adicionar linha, Voltar ao plano | Pull 10s/15s, marcar meu alvo, interruptor do HUD e a prévia dele |

## Regras

- **Funções**: o slot da inscrição no site, depois o Raiders (`RaiderRoster:EffectiveRoles`), depois a vaga num
  core, depois a classe quando só tem uma (palpite). Contam inscritos e extras no grupo; reserva, talvez e sem
  resposta não.
- **Metas**: 25 → 3 tanks, 7 healers (Gruul/Mag 6); 10 → 2 e 3; Onyxia 3 e 9; editáveis por raide
  (`db.raidTools.targets[chave]`).
- **Convites** (`RaidTools:InviteStep`): só inscritos fora do grupo; nunca banidos (guilda ou aliança: `BanList`),
  offline ou chamados há menos de um minuto; sozinho 4, em grupo os lugares livres, grupo pequeno demais vira
  raide primeiro, em raide todos. **No Forever um convite por clique** (`Compat.NeedsClick`). O "Convidar" de uma
  linha passa por `BanList:HoldInvite` ("Convidar mesmo assim").
- **Grupos**: sugestão com tanks juntos no 1º, depois corpo a corpo, caçadores, casters, healers; um xamã por
  grupo (corpo a corpo primeiro), um paladino por grupo (tanks primeiro); nunca mais de 5. Aplicar só líder ou
  assistente, em raide, fora de combate, com `Compat.SetRaidSubgroup/SwapRaidSubgroup`; só move quem está fora
  do lugar.
- **Anúncios**: 1 a 3 linhas de até 240 bytes, no /raide (no /grupo em grupo), cada tipo no máximo a cada 8 s.
- **Tarefas por chefe**: salvas por raide (`db.raidTools.assign[raide][chefe]`, até 12 linhas); sem nada salvo,
  vêm do plano do site (`roster.plan.assignments`, o mesmo que `RaidPlan` lê); sem plano, Tanque principal,
  Tanque secundário, Cura dos tanks, Interromper. Anúncio: "Chefe: tarefa Nome {skull} · …".
- **Pull**: `C_PartyInfo.DoCountdown` onde existe; senão "Pull em N" como aviso de raide (o "Pull!" depois só
  onde um timer pode falar: não no Forever).

## Em combate: o HUD (`Modules/RaidHUD.lua`)

196px, cabeçalho de 18px ("Cooldowns", – recolhe, × esconde até a próxima raide), uma linha por cooldown que
alguém da raide tem: ícone, nome curto, prontos/total (verde/vermelho), quando volta o próximo. Arrastável,
posição salva. **Em combate só isso**: o link "Ferramentas de raide" some. Aparece em raide, para líder e
assistentes, com o interruptor ligado (o recurso "Raid CD Tracker" das Configurações, ou a caixa na parte Luta);
desligado nunca aparece, nem em combate. Só TBC Anniversary (lê o log de combate, ADR-0014). Nada mais da tela
abre sozinho: o resto segue a regra do `GuildOS:ShowWhenClear`.

## Testes

`tools/raid-tools.lua` (lógica: funções × metas, origem, convites, grupos, anúncios, prontidão, tarefas, HUD,
Forever). Renders do harness em `scratchpad/render-raidtools/` (`b.sh NOME PARTE [L A] [origem]`).

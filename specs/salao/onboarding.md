# Onboarding: Novidades, tours, primeiros passos e central de ajuda

Status: implementado para a 2.0.0 ("2.0 · o Salão"). Mockup aprovado: `onboarding-mockup.html`
(artefato "Onboarding" no claude.ai). Substitui o assistente de 7 passos de `UI/Onboarding.lua`.

## 1. Objetivo

Quem atualiza da 1.x precisa entender o Salão (salas em vez de abas); quem chega agora precisa saber o que é o
Guild OS, como abrir e o que é compartilhado. Oficiais precisam de um caminho curto até a guilda estar
configurada. Tudo isso sem atrapalhar quem joga: nada em combate, nada dentro de instância ou grupo de raide,
no máximo um popup de onboarding por login.

## 2. Peças

| Peça | Arquivo | O que faz |
|---|---|---|
| Dados e estado | `Modules/Onboarding.lua` | Sem frames. Cartões das Novidades/Bem-vindo, as três trilhas (membro 4 capítulos/18 passos, oficiais 5/21, Mestre da Guilda 4), filtros por cliente, predicados dos primeiros passos, guias, entradas da busca, comandos e o estado. |
| Motor do tour | `UI/Tour.lua` | Escurece a janela com um buraco no alvo, anel dourado, balão de pergaminho (largura fixa 320, cresce só na altura; na faixa de vigia, 452 px, encaixa embaixo ou em cima). Âncoras por `UI:RegisterTourAnchor` / `UI:TourAnchor`. |
| Novidades / Bem-vindo | `UI/Onboarding.lua` | Janela flutuante (Kit) 560×452 (estreita: 436×480), figura desenhada com as texturas de `Media/Salao` (`UI.Picture`), pontos, título, texto, botões. |
| Central de ajuda | `UI/HelpPanel.lua` | Página Configurações › Ajuda (formulário do `UI/SettingsPanel.lua`) e a janela de guia. |
| "?" | `UI/Window.lua` | Ferramenta redonda entre a busca e a engrenagem; ponto vermelho; Shift-clique abre a ajuda da tela. Também a pílula "▶" no rodapé. |
| Primeiros passos dos oficiais | `UI/Salao.lua` | Cartão "Primeiros passos" no topo da coluna esquerda do Salão, no lugar do antigo "Set up Guild OS". |
| Linha dos membros | `UI/Salao.lua` (`Salao:ForYou`) | "Primeiros passos n/5" em Para você. |
| Entrada | `UI/Rooms.lua` | `{ id = "help", feature = "settings", sub = "help" }` na sala de Configurações. |
| Comandos | `Core/Commands.lua` | `/gos tour [member\|officer\|gm]`, `/gos whatsnew` (alias `news`), linhas no `/gos help`. |
| Busca | `Modules/Search.lua` | Indexa tours, Novidades e os 12 guias ("tour", "tutorial", "help", título do guia). |

## 3. Quem vê o quê

- `O:Arrival()`: "whatsnew" se a conta já usou o Guild OS (`settings.onboarded` nesta guilda ou em qualquer
  base de guilda da conta, ou `_onboard.seen`/`welcomed`), senão "welcome".
- Novidades: até 6 cartões. Cartão 3 troca por papel (Sala dos Oficiais para oficial, Membros para membro);
  cartão 5 é o mapa/fogueiras no WoW: Forever e o banco nos outros; o Mestre da Guilda ganha um cartão próprio
  na 6ª posição (o último sai). Bem-vindo: 4 cartões (o que é, como abrir com a escolha do botão da guilda,
  funções de raide com o seletor, dados e privacidade). Sem passo de estilo: há um estilo só.
- Botões: "Fazer o tour" (último cartão) marca como visto e inicia o tour de membro; "Depois"/✕/Esc conta
  um "depois" (mostra de novo no próximo login, no máximo 3 vezes; depois só o ponto vermelho no "?", que some
  ao abrir a ajuda); "Não mostrar de novo" fecha para sempre (`never`). Aberto pelo jogador (ajuda,
  `/gos whatsnew`), "Depois" não conta.
- Teclas: Enter/→ avança, ← volta, Esc = Depois.

## 4. Regras de exibição

- Login: `GuildOS:MaybeShowOnboarding()` (6 s após o login) passa por `GuildOS:ShowWhenClear("onboarding")`
  (ordem 2, nunca em combate) e pelo novo guarda `Onboarding:Clear()`: fora de instância e fora de grupo de
  raide. Se não estiver livre, espera `ZONE_CHANGED_NEW_AREA`, `GROUP_ROSTER_UPDATE` ou `PLAYER_REGEN_ENABLED`.
- No máximo um popup de onboarding por login (`Onboarding.session.shown`).
- Tour: combate esconde e volta no mesmo passo depois de `PLAYER_REGEN_ENABLED`; janela fechada pausa e o
  rodapé oferece "▶ Retomar o tour". Esc pula (o progresso fica para retomar em ? › Tours), Enter/→ avança,
  ← volta (`OnKeyDown`, propagação desligada só para essas teclas).
- Cliques fora do balão são bloqueados pelas quatro faixas escuras; o alvo no buraco continua clicável.

## 5. Tours

Cada passo: sala, entrada, lista de âncoras (a primeira que existir na tela), título, texto, nota opcional,
figura opcional. O tour abre a sala e a entrada sozinho. Passo cuja tela não abre (módulo desligado, cliente sem
o recurso, entrada sem painel) é tirado da lista; passo cuja âncora não aparece é pulado. Passos "figura"
(janela do membro, mapa da guilda) mostram a figura no balão, centrados.

Textos por cliente (do mockup): Forever sem convites por addon e sem escrita de notas; Anniversary escreve
notas; Retail tem conselho de saque em vez de mestre do saque; diário de vitórias e fogueiras só no Forever.

Âncoras registradas:

- `UI/Window.lua`: `tool.search`, `tool.help`, `tool.gear`, `tool.fold`, `window.content`, e os prefixos
  `door.<sala>` (na vigia vira o seletor de salas; em "»n" vira o botão »n), `entry.<sala>.<entrada>` e
  `side.<entrada>` (barra lateral da Sala dos Oficiais; na vigia, as pílulas).
- `UI/Salao.lua`: `salao.setup`, `salao.foryou`, `salao.board`, `salao.fire`, `salao.wall`, `salao.chat`.
- `UI/CalendarPanel.lua`: `raids.signup`. `UI/GroupsPanel.lua`: `groups.cards`. `UI/RosterFrame.lua`:
  `roster.search`, `recruit.ad`, `recruit.post`, `recruit.welcome`, `recruit.invite`. `UI/LootWindow.lua`:
  `loot.wishlist`. `UI/WebPanel.lua`: `web.site`, `web.link`. `UI/SettingsPanel.lua`: `settings.roles`,
  `settings.font`, `settings.minimap`, `settings.officerRanks`.
- Pendente: `bank.cleanup`, `bank.points`, `bank.tax` em `UI/GuildBankPanel.lua` (hoje caem na pílula da entrada).

Diferenças do texto do mockup, por fidelidade ao que existe: "Rank rules" virou "Ranks" (a tela é a lista com
promover/rebaixar; o tempo no cargo vem do log de eventos); "Perto da lareira" abre o menu do membro (não a
janela); o quadro de avisos fala de eventos fixados e avisos novos.

## 6. Primeiros passos

Nenhum tique é guardado: cada item é um teste sobre dados que o Guild OS já tem.

- Membro (linha em Para você, lista em Configurações › Ajuda): funções de raide (`GetMyRoles`), alts
  (vinculado como alt ou main, ou nenhum outro personagem da conta na guilda), inscrição (qualquer RSVP meu no
  calendário), lista de desejos (`Wishlist:GetMyList`), Companion (`GuildOSDB.__companionAt`).
- Oficiais (cartão no Salão): anúncio com texto, uma boas-vindas, regras de cargo (uma predefinição salva ou
  "Promovemos à mão"), regras de alerta (lista salva pelos oficiais com uma regra), site (Forever: os cinco
  passos da `Modules/Activation.lua` como pílulas, feito quando ativada; outros: o site respondeu,
  `CompanionImport:GuildBlock()`). Mestre da Guilda, antes: cargos de oficial salvos (`officerMaxRankAt`) e taxa
  do banco decidida (`bankTaxAt`, ligada ou desligada).
- "Mostre-me" abre a tela e roda um tour de um passo no alvo. Tudo feito: aviso único ("A guilda está
  configurada"), o cartão sai do Salão no dia seguinte. "Ocultar por 30 dias" (também cala o lembrete da
  ativação no resumo).

## 7. Central de ajuda

Tours com progresso (anel, porcentagem, Começar/Retomar/Repetir, cada capítulo em pílula), Novidades,
primeiros passos, 12 guias com figura (os 2 de oficiais só para oficiais) que abrem uma janela com "Mostre-me"
(o capítulo do tour) e o link do manual, e "Mais ajuda": caixas de copiar para https://guildos.me,
https://guildos.me/manual e https://discord.gg/8XA6gmNjja, `/gos help` e "Mostrar dicas de novo" (pede
confirmação, apaga `_onboard` da conta e mostra as Novidades). Shift-clique no "?" abre o capítulo do tour ou o
guia da tela atual (`Onboarding:HelpFor`).

## 8. Armazenamento

- `GuildOSDB._onboard` (conta): `seen`, `welcomed`, `later`, `never`, `dotSeen`,
  `tours = { member|officer|gm = { step, done, chapters } }`, `chars["Nome-Reino"].gs.hidden`.
- `db.settings.gettingStarted` (guilda): `hidden`, `byHand`, `doneAt`, `celebrated`.
- `db.settings.onboarded` mantido (true ⇒ usuário antigo ⇒ Novidades).
- Nada é sincronizado pelo ChehulNet.

## 9. Testes

- `tools/onboarding.lua`: trilhas por papel e cliente, pulos, transições (Novidades → Depois ×3 → ponto →
  nunca → reset), armazenamento por conta, cada predicado, a fusão com a ativação no Forever, comandos, busca,
  guardas (combate, instância, raide).
- `tools/tour.lua`: posicionamento dentro da janela em 1000 e 452 px, âncoras, tour inteiro, pulo de passo
  sem âncora, teclas, pausa/retomada em combate, janela fechada, "?" e ponto vermelho, Shift-clique, Novidades,
  um popup por login, central de ajuda e o cartão do Salão.
- `tools/frame-leaks.lua`: Novidades, tour completo (1250 e 452), Mostre-me, ajuda e o cartão sem criar frames
  novos depois do primeiro desenho.
- Ajustados: `settings-panel` (oito sub-abas, "Mostrar dicas de novo"), `window-shell` (ferramenta "?",
  pílula do rodapé), `style` (sem passo de estilo), `commands-in-ui` (`tour`, `whatsnew`).

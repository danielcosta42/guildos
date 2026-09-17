# Pedido para o Claude Design — GuildOS: nova interface do addon (WoW Forever)

> Como usar: cole este arquivo inteiro como prompt para o Claude Design (skill `design`). Ele deve produzir **um canvas único** com os artboards listados na seção 8, nos tamanhos reais em pixels.

---

## 1. O que é o produto

**GuildOS** é um addon de gerenciamento de guild para World of Warcraft que substitui o painel de guild da Blizzard. Hoje roda em TBC Anniversary; a versão que você vai desenhar é a do **World of Warcraft: Forever**.

Ele não é um addon de combate. É um sistema de gestão: roster com inspeção de equipamento peça por peça, controle de presença em raide, distribuição de loot (master loot, DKP, wishlist), attunements, recrutamento, trials, federação entre guildas aliadas e um companion web em `guildos.me` que publica o que o jogo anotou.

Três superfícies formam um laço: **o addon anota → o bot do Discord organiza → o site diz quem veio.** O addon é a ponta que vive dentro do jogo, e é a única das três que hoje não parece parte da mesma marca.

**Quem usa:** líderes e oficiais de guild (o uso pesado — leem tabelas densas, tomam decisão com 24 pessoas esperando) e raiders (uso leve — conferem a própria presença, marcam item na wishlist, respondem chamada de loot).

**Onde é usado:** sobreposto ao jogo, frequentemente durante raide, às vezes em combate. Fundo atrás da janela pode ser qualquer coisa — Durotar ao meio-dia ou uma masmorra preta.

---

## 2. O problema a resolver

A interface atual do addon usa um tema próprio chamado "Obsidian": superfícies quase pretas com tinta fria, acento violeta dessaturado e um dourado champagne para a marca. É competente, mas foi desenhado isolado — **não conversa com o site novo do `guildos.me` nem com a direção do WoW Forever.**

O objetivo é uma **pele nova, unificada**: quem sai do site e entra no jogo tem que reconhecer o mesmo produto.

---

## 3. Identidade a herdar — o site novo (`guildos.me`)

Estes são os tokens reais extraídos do CSS do site em produção. **Eles são a fonte da verdade da marca.** Sua entrega deve derivar deles, não reinventá-los.

### Cor

| Papel | Token do site | Hex | RGB 0-1 (formato do WoW) |
|---|---|---|---|
| Fundo base | `--ink` | `#100f16` | `0.063, 0.059, 0.086` |
| Superfície elevada | `--ink-2` | `#17161f` | `0.090, 0.086, 0.122` |
| Superfície mais alta | `--ink-3` | `#1d1b26` | `0.114, 0.106, 0.149` |
| Linha / borda | `--line` | `#2a2733` | `0.165, 0.153, 0.200` |
| Texto primário ("papel") | `--paper` | `#ece7e0` | `0.925, 0.906, 0.878` |
| Texto suave | `--soft` | `#a9a2b0` | `0.663, 0.635, 0.690` |
| Texto secundário | `--muted` | `#97909f` | `0.592, 0.565, 0.624` |
| Texto apagado | `--dim` | `#6f6878` | `0.435, 0.408, 0.471` |
| Texto fantasma | `--faint` | `#4b4553` | `0.294, 0.271, 0.325` |
| **Acento / marca** | `--gold` | `#d9a94f` | `0.851, 0.663, 0.310` |
| Texto sobre dourado | `--ink-gold` | `#17130a` | `0.090, 0.075, 0.039` |
| Épico (violeta) | `--epic` | `#a86fe0` | `0.659, 0.435, 0.878` |
| Sucesso / presente | `--ok` | `#7dd88f` | `0.490, 0.847, 0.561` |

Observações importantes:

- O **dourado é o único acento de marca**. Ele aparece em botão primário, wordmark, régua fina sob métricas e pouco mais. Não é cor de fundo de card.
- O **violeta não é mais o acento da interface** — no site ele significa "épico" (qualidade de item). No addon ele volta a ser só isso. Quem hoje é violeta (hover de linha, aba ativa, borda de foco) migra para dourado ou para `--line` mais claro.
- O sistema é **quase monocromático com um acento**. Semântica (vermelho de perigo, verde de online) entra só onde carrega informação, nunca como decoração.
- Você precisa propor **vermelho e azul** que faltam na paleta do site, coerentes com ela (o addon precisa de "ausente/penalidade" e de "informação/link"). Entregue-os como extensão do sistema, marcados como novos.

### Tipografia

| Papel | Fonte | Licença |
|---|---|---|
| Display e corpo | **Spectral** (serifada) | OFL — pode ser embarcada no addon |
| Meta, rótulos, números | **IBM Plex Mono** | OFL — pode ser embarcada |

Hierarquia observada no site:

- H1: Spectral Regular (400), 78px, tracking −1.57px, cor `--paper`
- H2: Spectral Regular (400), 51px, tracking −0.77px
- H3: Spectral **Bold** (700), 21px
- Corpo: Spectral, 18px, cor `--paper`
- Navegação, rótulos, chips de estatística, breadcrumbs: **IBM Plex Mono 400, caixa baixa, cor `--muted`** — esse é o detalhe mais característico da marca
- Micro-rótulos em mono, caixa baixa, com ponto médio como separador: `addon · bot do discord · site · tbc classic`

### Forma e superfície

- Raio de canto: `--radius` 14px, `--radius-lg` 20px
- Cards: fundo levemente acima do fundo base, borda de 1px em `--line`, sem sombra pesada
- Botão primário: fundo `--gold`, texto `--ink-gold`, raio 12px, padding 13/26px, **glow dourado difuso** (`rgba(gold, 0.8) 0 14px 40px -12px`) — não é sombra, é luz
- Link secundário: texto `--muted` em mono com sublinhado fino de 1px
- Chip de métrica: texto em mono com régua dourada fina de 1px abaixo (não é caixa, é sublinhado)
- Fundo do hero: gradiente radial quase imperceptível, quente no canto superior esquerdo, frio no direito — atmosfera, não cor

### Voz

Português coloquial e preciso ao mesmo tempo. Frases declarativas curtas, caixa baixa nos rótulos, zero linguagem corporativa, zero emoji. Exemplo do site: *"o jogo anota, o site diz quem veio"*. Rótulos de UI seguem isso: `quem veio`, não `Relatório de Presença`.

---

## 4. Identidade a herdar — World of Warcraft: Forever

O Forever é a Azeroth original reconstruída com renderização moderna. A direção declarada pela Blizzard é *"Azeroth como você lembra"*: **a arte vanilla é mantida deliberadamente**, e o que muda é a luz — névoa volumétrica com vento, sombras dinâmicas que respondem à posição do sol, iluminação global no lugar da luz assada, água que reflete o mundo. Cada zona ganha reforço da própria identidade (Durotar fica mais quente e sufocante, não diferente).

**A tradução disso para a interface é a tese central deste pedido:**

> Forma antiga, luz nova. Nada de ouro filigranado, madeira, pergaminho rasgado ou moldura de taverna — isso é cosplay de vanilla. O que se herda é a **atmosfera**: profundidade por luz, não por textura; calor vindo de uma fonte, não de uma cor de fundo; contraste alto e limpo como o de uma cena bem iluminada.

Concretamente:

- Profundidade vem de **gradiente e de uma única fonte de luz implícita no topo**, como o brilho do hero do site. Não de bisel, não de emboss, não de sombra interna.
- O dourado é **luz de vela**, não metal. Ele brilha (glow difuso), não reflete (gradiente metálico).
- Superfícies são **opacas**. A janela não é vidro: ela está sobre um mundo que pode estar em qualquer cor e precisa ser legível às 3h de raide.
- Zero skeumorfismo. Zero neon. Zero glassmorphism.

---

## 5. Restrições técnicas — leia antes de desenhar

Isto não é uma página web. A UI do WoW é composta de `Frame`, `Texture` e `FontString`, posicionados por âncora em pixels. **O design só existe se puder ser construído com estas primitivas.** Cada item abaixo já eliminou uma ideia boa antes.

**O que não existe:**

- Não há CSS, não há layout automático, não há flexbox. Toda posição é uma âncora com offset em pixels inteiros.
- **Não há `border-radius`.** Canto arredondado só existe como arte: uma textura 9-slice com as quatro quinas desenhadas. Quanto maior o raio, mais pesada a arte. Assuma **canto reto ou raio máximo de 6px**, e desenhe assumindo que o raio de 14px do site **não vem junto** — a marca precisa sobreviver a isso. Se você quiser raio, entregue a arte da quina como spec explícita.
- **Não há blur, backdrop-filter, box-shadow nem sombra projetada real.** Sombra é uma textura de gradiente pré-renderada atrás do frame (o addon já tem `UI:CreateDropShadow`). O glow dourado do botão primário precisa virar uma textura aditiva radial — descreva-a.
- **Não há controle de letter-spacing.** O tracking negativo dos títulos do site é irreproduzível. Não construa hierarquia que dependa dele.
- **Não há peso falso.** "Bold" só existe se o arquivo `.ttf` daquele peso for embarcado. Liste exatamente quais arquivos de fonte o addon precisa carregar (ex.: Spectral Regular, Spectral SemiBold, IBM Plex Mono Regular, IBM Plex Mono Medium) — cada um pesa no pacote, então justifique.
- **Não há máscara arbitrária.** Avatar circular exige textura de anel pré-recortada (o addon já faz isso no botão do minimapa).
- Contorno de texto só tem três estados: nenhum, `OUTLINE`, `THICKOUTLINE`. Não há sombra de texto sutil.
- Animação existe via `OnUpdate`, mas custa frame em raide. Assuma **mudança de estado instantânea**, com fade de alpha de ~0.1s no máximo. Nada de transição de cor ou de posição.
- Gradiente só linear, dois pontos. Nada de gradiente radial em textura de frame (só como imagem pré-renderada).

**O que é sagrado e você não pode reestilizar:**

- **Cores de classe** (Warrior bege, Paladin rosa, Priest branco, etc.) e **cores de qualidade de item** (verde/azul/roxo/laranja). Jogadores leem isso mais rápido que texto. Você pode emoldurá-las, dar-lhes espaço, colocá-las em contexto — não pode alterá-las nem substituí-las por cor da marca.
- **Ícones de habilidade e item** vêm de `Interface\Icons\*`: quadrados 64x64 com borda embutida feia. A prática é cortar 8% de cada lado (`SetTexCoord`) e dar uma moldura própria. Especifique essa moldura.

**Restrições de layout:**

- Toda janela é **redimensionável entre um mínimo e a tela inteira**. Os mínimos estão na seção 8 e são reais — foram calibrados na largura em que a tabela ainda lê.
- Tabelas degradam **soltando colunas por prioridade**, não com scroll horizontal e não encolhendo tudo igual. O addon já tem esse resolvedor. Para cada tabela, entregue a **ordem de descarte das colunas** e quais são obrigatórias.
- Tudo é renderizado num grid de 1px após a escala de UI. Desenhe em escala 1.0, use **ritmo de 2px**, nada de meio pixel.
- Texto abaixo de 10px é ilegível em escala 1.0. **Serifada abaixo de 14px vira borrão** — por isso Spectral só em títulos e nomes; toda tabela densa e todo número usam IBM Plex Mono.

---

## 6. Design system a entregar

Antes das telas, entregue as fundações. Elas são o deliverable mais importante: as 20 telas se derivam delas.

**Artboard "Fundações":**

1. **Paleta completa**, cada cor com nome semântico, hex e RGB 0-1, e a regra de uso em uma linha. Inclua o vermelho e o azul novos.
2. **Escala tipográfica**: cada estilo com fonte, tamanho em px, peso, cor, contorno, e para que serve. Mínimo: wordmark, título de janela, título de seção, legenda de seção (mono caixa baixa), corpo, nome de membro, número de tabela, rótulo de métrica, texto apagado, badge.
3. **Escala de espaçamento** em múltiplos de 2px, com o padding padrão de painel, o gap entre seções e a altura de linha de tabela.
4. **Sistema de elevação em 4 níveis** (poço → base → painel → popup), definido por cor de superfície e por borda, já que não há sombra real.
5. **Sistema de régua e borda**: quando 1px `--line`, quando régua dourada, quando separador, quando nada.
6. **Matriz de estados**: repouso, hover, pressionado, ativo/selecionado, desabilitado, foco de teclado — para linha de tabela, botão, aba e checkbox. Explicite o que muda em cada um, sabendo que a transição é instantânea.

**Artboard "Componentes":** botão primário / secundário / fantasma / perigo; botão de ícone; checkbox; radio; campo de texto; dropdown; aba principal; sub-aba; barra de rolagem; badge; barra de progresso; chip de métrica com régua dourada; legenda de seção; linha de tabela nos 5 estados; cabeçalho de tabela ordenável; avatar/ícone de classe; ponto de status online/offline/ausente; tooltip; estado vazio; estado de carregando; banner de erro; ícone de item com moldura de qualidade.

---

## 7. Princípios que a UI precisa respeitar

1. **Densidade é a funcionalidade.** Um oficial olha 60 linhas de roster. Espaço em branco generoso de site não cabe. Ache o ponto: respirável o suficiente para não cansar, denso o suficiente para caber a guilda.
2. **Legível sobre qualquer coisa.** Painel opaco, contraste alto, nada de transparência que deixe Azeroth vazar para dentro da tabela.
3. **A informação urgente aparece sem clique.** O hub responde "o que está acontecendo" e "o que precisa de mim" sem abrir nada.
4. **Decisão em raide é de 10 segundos.** Popup de loot, HUD de raide e chamada de presença são desenhados para serem lidos de canto de olho, com 24 pessoas esperando.
5. **O oficial vê mais, não uma interface diferente.** Ferramentas de oficial são a mesma linguagem com mais colunas, nunca um tema separado.
6. **Nada de emoji, em lugar nenhum.**

---

## 8. Telas a desenhar

Cada artboard no **tamanho real em pixels**. Onde há mínimo, entregue também o estado mínimo lado a lado — é onde o layout quebra.

### P0 — a espinha (entregue primeiro)

| # | Tela | Tamanho | O que é |
|---|---|---|---|
| 1 | **Hub** | 430 × ~300, e o estado recolhido | A porta de entrada. Trilho de features à esquerda (150px) e coluna viva à direita: online agora, próxima raide, o que precisa de mim. Toda linha clica para a janela dona da resposta. |
| 2 | **Shell da janela expandida** | 1000 × 620 | Barra de título com wordmark, barra de abas, área de conteúdo, alça de redimensionar. É o chrome que todas as telas abaixo herdam. |
| 3 | **Home / Dashboard** | 1000 × 620 | Visão geral da guilda: contagem, atividade recente, contagem regressiva da próxima raide, atalhos. |
| 4 | **Roster** | 1000 × 620 + mínimo 520 × 380 | A tela mais usada. Tabela de membros com nome (cor de classe), nível, classe, item level, presença, última vez online, notas. Filtros, busca, ordenação. **Especifique a ordem de descarte de colunas** — no mínimo de 520px só sobram MEMBRO, NÍVEL, CLASSE, ILVL. |
| 5 | **Detalhe do membro** | 420 × 620 | Inspetor: cabeçalho com ícone de classe, equipamento peça por peça com qualidade e encantamento, attunements, presença, notas de oficial. Coluna alta e rolável. |
| 6 | **Popup de loot (roll)** | proponha | O momento mais crítico. Item caiu, 24 pessoas esperando, o mestre de loot decide. Precisa ser lido em 5 segundos. |

### P1 — o núcleo de gestão

| # | Tela | Tamanho | O que é |
|---|---|---|---|
| 7 | **Raids** | 780 × 540, mín 560 × 360 | Cinco sub-abas: sessões, raiders, cores, auditoria, ferramentas de raide. |
| 8 | **Loot** | 680 × 470, mín 480 × 320 | Histórico de loot por boss, por membro, por item. |
| 9 | **DKP** | 620 × 440, mín 440 × 300 | Saldos, ganhos, gastos. Tabela numérica pura. |
| 10 | **Wishlist** | 680 × 470, mín 480 × 320 | O que cada um quer, por raide e por boss. |
| 11 | **Leadership** | 900 × 560, mín 560 × 380 | Oito sub-abas em uma linha a 900px. A tela mais carregada de todas — resolva a navegação de sub-abas aqui e ela serve para o resto. |
| 12 | **Guild** | 720 × 520, mín 500 × 360 | Sub-abas: calendário e atividade. |
| 13 | **Settings** | 560 × 520, **não redimensionável** | Lista de toggles por feature, escala de UI, preferências. |

### P2 — o entorno

| # | Tela | Tamanho | O que é |
|---|---|---|---|
| 14 | **Alliance** | 900 × 600, mín 620 × 420 | Federação entre guildas: roster compartilhado, lista de banidos, chat entre guildas. |
| 15 | **Recruitment** | 720 × 560, mín 460 × 340 | Coluna rolável: candidatos, beacon, scanner. |
| 16 | **Trials** | 620 × 420, mín 440 × 300 | Progresso de membros em teste. |
| 17 | **Recipes** | 700 × 500, mín 400 × 300 | Quem sabe craftar o quê. |
| 18 | **Web** | 460 × 440, mín 380 × 320 | A ponte para o `guildos.me`. **Esta tela é onde as duas marcas se encostam** — é a que mais precisa parecer o site. |
| 19 | **Raid HUD** | 420 × altura automática | Flutuante, aparece em combate, cooldowns e checagem de consumíveis. Mínimo absoluto de peso visual. |
| 20 | **Botão do minimapa + menu** | 31 × 31 e o menu | O wordmark reduzido ao menor tamanho possível. |
| 21 | **Onboarding** | proponha | Primeira execução: o que o addon faz e o que ele publica. |
| 22 | **Tooltip** | proponha | Aparece por cima de tudo, em qualquer canto da tela. |

---

## 9. O que entregar

- **Um canvas** com os artboards acima, na ordem P0 → P1 → P2.
- Cada tela com **conteúdo real e plausível** — nomes de personagem brasileiros e de guild de verdade, item levels na faixa certa, datas coerentes. Nada de "Lorem" e nada de placeholder genérico.
- Cada tela nos **estados que importam**: cheia, vazia, carregando, e o estado de largura mínima onde houver.
- Anotações onde o design depende de uma decisão técnica (arte de quina, textura de glow, arquivo de fonte, ordem de descarte de coluna).
- Ao final, uma **tabela de mapeamento de tokens**: cada token novo com o nome que ele terá em `BRutus.Colors` e em `BRutus.Fonts`, para a implementação em Lua ser mecânica.

## 10. Anti-requisitos

Não entregue nada que contenha: emoji; moldura dourada filigranada, madeira, couro ou pergaminho; glassmorphism ou transparência sobre o jogo; neon ou cor saturada fora da semântica; violeta como cor dominante (violeta é só qualidade épica); sombra pesada empilhada em card; navegação só de ícone sem rótulo; título longo com subtítulo explicativo; texto serifado abaixo de 14px; qualquer coisa que dependa de blur, transição de cor ou letter-spacing.

---

## Referências rápidas

- Site de produção: `https://guildos.me` (home, `/guilds`, `/g/[guild]`, `/dashboard`)
- Tema atual do addon a ser substituído: "Obsidian" — preto quase neutro com tinta fria, acento violeta dessaturado `#8F7AD1`, dourado champagne `#EDCC7A`
- Direção do jogo: World of Warcraft: Forever, anunciado na BlizzCon 2026 — arte vanilla preservada, renderização moderna (névoa volumétrica, iluminação global, sombras dinâmicas, água reflexiva)

# O Salão, fase 3: o visual do protótipo (#449)

## Por quê

O mantenedor testou a fase 2 no jogo: nada quebrou, mas a janela parecia "arte genérica do Forever por cima
de um painel moderno". Três causas:

1. **O pintor "forever"** (`Core/Style.lua`) desenhava a moldura de metal, o botão vermelho, as abas e a
   caixa de seleção com os atlas `-c60` do cliente WoW: Forever. É o visual de qualquer janela do jogo, não o
   do protótipo, e só existia num dos três clientes.
2. **A fonte do jogo** (fase 1 forçou `Style.gameFont = true`) e, antes dela, a IBM Plex: uma dava o ar de
   janela do jogo, a outra o de dashboard técnico.
3. **A estrutura de dashboard**: uma barra de título fina, uma segunda fileira de abas para as salas, uma
   terceira para as entradas, tudo chapado num fundo escuro.

## O que mudou

- **Uma arte própria, a mesma nos três clientes.** O pintor "forever" saiu. `Core/Style.lua` desenha com
  texturas do addon (`Media/Salao`), em 9 pedaços (caixa com cantos redondos), 3 (botão, pílula) ou 1, e
  tinge com `SetVertexColor` onde a cor varia (classe, estado). Nenhum atlas do cliente decide o visual.
  `/gos style preview` mostra as texturas.
- **Paleta do protótipo** (`Core/Data.lua`): madeira, metal (`lineHi` #6b5326, `metal2` #c9a24a), ouro do jogo
  e ouro suave (`gold2` #ffd77a), carmesim do botão primário, papel (#f3e4c2, tinta #3a2a17, suave #6f5a3c,
  título #6b1d0e).
- **A casca** (`UI/Window.lua`): moldura de metal de 3px; **uma** barra de título de 50px com o brasão
  redondo, o nome da guilda em Cinzel dourado e "N online · reino" embaixo; as **salas como portas** na mesma
  barra (a aberta em madeira com borda de metal e nome dourado em negrito; a Sala dos Oficiais em ouro
  suave, com a contagem vermelha do trabalho pendente); ferramentas redondas à direita (busca, engrenagem,
  recolher, fechar vermelho). As **entradas da sala viram pílulas** numa faixa sob a barra; a Sala dos
  Oficiais mantém a lista lateral, no estilo `.side-nav` (grupos em Cinzel, item aberto em pílula dourada,
  contagem vermelha). Fundo de **tábuas de madeira com o brilho do fogo** no canto; no Winter Veil, neve nas
  tábuas e a guirlanda sob a barra. **Rodapé**: "Bem-vindo de volta, <nome>." e "● Atualizado: …" (clicar
  sincroniza). Os links do rodapé saíram: guildos.me e /gos help estão no tooltip da engrenagem e em
  Configurações › Dados; a janela de guilda da Blizzard virou um botão ali.
- **Os primitivos** (`UI/Helpers.lua`), herdados por todas as telas: `CreateCard` (papel, ou escuro com
  `dark`), botões primário (carmesim, borda dourada, texto amarelo), secundário (escuro na madeira, creme
  "quiet" no papel), fantasma (link sublinhado), perigo e `chip` (pílula); campos arredondados (escuro na
  madeira, claro no papel); abas como pílulas; avatar redondo de classe (`CreateAvatar`), glifo
  (`CreateGlyph`), contagem vermelha (`CreateCount`), ferramenta redonda (`CreateToolButton`), seleção de
  linha em degradê dourado (`CreateRowSelection`); cabeçalho de tabela em Cinzel (ouro na madeira, vermelho
  escuro no papel); KPI como bloco escuro pequeno. As chamadas `SetBackdropColor` das telas antigas caem na
  arte arredondada (`Style:Hand`).
- **Salão › Início** (`UI/Salao.lua`) como `salao-inicio.png`: Configure (oficial, enquanto a ativação não
  terminou), Para você (quadrado colorido com número, linha e linha menor com a sala, botão à direita; o
  primeiro carmesim, os outros creme), Quadro de avisos como bilhetes presos (alfinete vermelho, 3 por
  linha, a resposta do jogador contorna o bilhete em verde, âmbar ou vermelho; o aviso mais novo embaixo);
  Perto da lareira (card escuro, avatares de 40px em 4 colunas e o disco tracejado "+N fora"); Mural da
  guilda (glifo, linha, hora). Os dados e o comportamento são os de antes.
- **Membros** (`UI/RosterFrame.lua`) como `membros-lista.png`: blocos KPI escuros; um card escuro "Membros"
  com busca, Todos/Online/Da aliança como pílulas, Mostrar offline, Colunas, Análises; cargos e classes como
  pílulas logo abaixo (a barra lateral saiu); tabela com avatar redondo e nome na cor da classe, linha
  selecionada em degradê dourado.

## Arte (`Media/Salao`, 438 KB)

Gerada por `python3 tools/salao_art.py` (Pillow, semente fixa; `--check` confere). TGA 32-bit, sem
compressão, origem topo-esquerda, lados potência de dois. `tools/salao-art.lua` confere cada arquivo que o
código nomeia.

| Arquivo | Tamanho | Uso |
|---|---|---|
| `wood.tga` | 128x256 | tábuas verticais, repetidas nos dois sentidos |
| `grain.tga` | 128x128 | grão do papel, repetido |
| `glow.tga` | 128x128 | brilho do fogo (alfa), canto inferior direito |
| `titlebar.tga` | 16x64 | degradê da barra de título |
| `card.tga`, `card-line.tga` | 32x32 | caixa redonda (preenchimento e linha de 1px) em 9 pedaços: cards, janela, campos, portas, bilhetes |
| `shadow.tga` | 64x64 | sombra suave do papel e dos bilhetes |
| `button.tga`, `button-soft.tga`, `button-line.tga` | 64x32 | botão em 3 pedaços (luz forte, luz suave do creme, linha) |
| `pill.tga`, `pill-line.tga` | 64x32 | pílula em 3 pedaços: entradas, filtros, distintivos, contagens |
| `orb.tga` | 64x64 | esfera iluminada: brasão, fechar, alfinete, glifos |
| `disc.tga`, `ring.tga`, `ring-dash.tga`, `halo.tga` | 64x64 | avatar: disco na cor da classe, anel dourado, anel tracejado do "+N", brilho |
| `circle.tga` | 32x32 | disco liso: ferramenta redonda, ponto do rodapé |
| `fade.tga` | 64x8 | degradê da linha selecionada |
| `snow.tga`, `garland.tga` | 64x64, 64x16 | Winter Veil: neve nas tábuas, guirlanda sob a barra |
| `icon-search.tga`, `icon-gear.tga` | 32x32 | ícones das ferramentas |

Alfinete, botão redondo de fechar, ferramenta e brasão são composições dessas peças, não arquivos próprios.

## Fontes: a decisão da fase 1, revertida de propósito

A fase 1 pôs a fonte do jogo em tudo para "um visual em todo cliente". Com a arte do jogo, isso era
exatamente o visual genérico do Forever. A fase 3 volta a fontes próprias, as do protótipo, todas OFL
(`Media/Fonts`, com as licenças): **Cinzel Bold** (títulos), **Alegreya Sans** regular/médio/negrito
(interface) e **Alegreya** regular (leitura). Cinzel e Alegreya são variáveis; o WoW só lê a instância padrão
de uma fonte variável, então os arquivos são instâncias estáticas (fontTools `instancer`: Cinzel 700,
Alegreya 400). A IBM Plex saiu do pacote. `Style.gameFont` fica `false`; o antigo `GuildOSDB.font = "game"`
é ignorado (não há mais escolha). Alegreya Sans desenha um tamanho pedido 1px maior (corpo menor que o da
Plex), nunca abaixo de 11px; título nunca abaixo de 10px.

**Fallbacks** (conferidos no cmap): nenhuma das três tem Hangul ou Han, então em **koKR, zhCN e zhTW** tudo usa
as fontes do cliente (título: a fonte dos títulos de missão do cliente, `QuestTitleFont`; o resto:
`STANDARD_TEXT_FONT`). **Cinzel não tem cirílico**: em **ruRU** os títulos usam a fonte de título do jogo
(Morpheus cirílica); Alegreya e Alegreya Sans têm cirílico e ficam. Um título com texto de jogador fora do
latim (nome de guilda ou de evento em cirílico num cliente enUS) troca para a Alegreya Sans Bold
(`GuildOS:SetTitleText`). Nenhuma das três tem "●": o ponto do rodapé é textura.

## Espaçamento

O mantenedor, no jogo: "um pouco mais de espaço (problema geral nessas telas), densidade de opções e uso do
espaço". O padrão abaixo vale para Raides › Cores e Grupos desde já (`SP` em `UI/CorePanel.lua` e
`UI/GroupsPanel.lua`) e vira global depois, nos primitivos.

- **Unidade 4.** Toda medida é múltiplo de 4 (2 só para linhas finas e ajuste ótico).
- **Card:** padding 16; 14 entre cards; o conteúdo nunca encosta na borda. Título de seção **15 serifado**
  (Cinzel), 8 acima do conteúdo; entre seções de um card, **18**.
- **Formulário:** campo com **26** de altura, rótulo 4 acima do campo, campos 12 entre si.
- **Tabela:** linha de **28** (32 com avatar), célula com 10 de respiro.
- **Texto:** corpo **13**; nunca abaixo de 11, e 11 só em linha de meta (tempo, contagem, legenda). Número de
  KPI **22**.
- **Alvo de clique** mínimo de **24**.
- **Uso do espaço:** cards em grade de 2 colunas a partir de 900 px de tela; listas crescem até o fim da altura
  disponível; estado vazio é um bloco centrado e ilustrativo (glifo ou ícone, uma linha e a ação principal),
  nunca uma linha cinza no canto superior esquerdo.
- **Teste:** todo descendente visível de um card fica dentro do card (`isCard`; `tools/groups-panel.lua` e a
  parte de Cores de `tools/loot-window.lua` conferem pelas âncoras).

## O que o WoW não reproduz do protótipo

- Sombras e degradês são texturas fixas: a sombra do papel não acompanha cantos de raio diferente, e o
  degradê de um botão é só vertical e de luminância (a cor de baixo é a de cima escurecida).
- O grão do papel não "multiplica": é uma textura de pontos escuros com alfa por cima.
- Linhas de 1px em cantos redondos ficam um pouco mais suaves que no navegador quando o canto é desenhado
  abaixo de 8px (botões).
- Ícones do protótipo em emoji/símbolo (★ ◆ ✂ ♥ ✓) não existem nas fontes: os glifos do mural usam a
  inicial da linha; os quadrados do Para você, a contagem ou a inicial.
- Telas além de Salão e Membros herdam os primitivos, mas a composição delas (títulos de seção em
  maiúsculas, layouts próprios) fica para a segunda passada.

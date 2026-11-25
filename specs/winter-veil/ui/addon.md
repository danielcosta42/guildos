# 122 · Telas do evento: o addon

Protótipo: `prototipo-addon.html` (nesta pasta). Segue as specs 119 (regras, §7 raridade, §10 Chaminé) e 121 (Frimm, neve).
É desenho e especificação de assets, não código de produção. Nada no addon foi alterado.

## O que foi lido e o que isso fixou

- A janela é a pele própria do GuildOS (`Core/Data.lua`, `UI/Window.lua`), não a moldura da Blizzard: 1000×620 por padrão,
  barra de título de 30, régua de abas de 28, rodapé de 22, margem de 12. Fundo `#100f16`, painel `#17161f`, ouro `#d9a94f`
  como único acento, IBM Plex Sans e Mono. O protótipo usa exatamente esses valores.
- A aba de hoje (`UI/WinterVeilPanel.lua`) tem a Chaminé como uma barra de 6 px e a Coleção como lista de linhas.
- A neve (`UI/Snow.lua`) são 20 quadrados brancos, um OnUpdate a 20 Hz, parado com a janela fechada. Fica como está.
- Os globos em `Media/Globes` têm 128 px e **fundo opaco** (`#0b0a10` com vinheta): sobre o painel aparece um quadrado, e
  qualquer brilho atrás do globo é cortado por ele. `closed.tga` mostra a árvore por baixo da fita.

## Decisões

1. **A Chaminé é a coluna esquerda da aba, sempre à vista** (264×512), não uma barra. Duas texturas com o mesmo desenho, fria
   e em brasa; a quente aparece de baixo para cima por recorte (`SetTexCoord` + `SetHeight`, a técnica de barra de status).
   A neve do topo "derrete" sozinha, porque a textura quente não tem neve. Fogo, brasas e fumaça crescem com o nível.
   Antes do sorteio ela fica apagada (a spec 119 §10 diz que sem sorteio não aparece: aqui aparece fria, com "acende no sorteio").
2. **100% é comunicado três vezes:** a placa vira "CHEIA", a barra de chances embaixo anima de 60/25/12/3 para 20/50/24/6
   com o título "CHANCES EM DOBRO", e o Frimm avisa num aviso. Uma varredura de luz e estrelas marcam o instante.
3. **Abertura em três sacudidas do jogador e degraus de raridade.** 1ª: a fita cai. 2ª: o vidro desembaça e a cena aparece.
   3ª: o globo sobe de nível à vista (madeira, prata, ouro, cristal), uma pausa trêmula e um pulso por degrau, parando na
   raridade sorteada. Usa as 4 texturas da cena que já existem; nenhuma arte a mais por raridade.
4. **A cerimônia não espera a rede.** A raridade vem do site pelo companion (1 a 5 min). O botão "Abrir" faz o pedido e o
   Frimm "vai buscar"; a cerimônia toca uma vez quando o globo aberto chega ao cliente e a aba está visível.
5. **Globo fechado = vidro embaçado, sem cena.** O receptor não vê nem a cena antes de abrir (119 §9).
6. **Coleção = prateleira** de 3 colunas de 128 px com moldura na cor da raridade e detalhe à direita (globo de 192, de quem,
   bilhete em cartão). Lendária e épica ganham raios girando só no detalhe.
7. **Frimm:** retrato redondo, três caras (apressado, feliz, ops). Personagem original, vetor simples.
8. **Teaser:** a caixa de neve de 72 px ganha um pacote no chão e o gorro do Frimm, que sobe no hover. Mesmo texto da 121.

## Assets

| Arquivo | Tamanho | Quadros | Para quê | Como gerar | Peso (TGA 32 bits) |
|---|---|---|---|---|---|
| `Globes/<cena>-<raridade>` | 128² | 20 arquivos | prateleira, listas, botões de cena (a 64) | existe; refazer com fundo transparente | 1,31 MB |
| `Globes/256/<cena>-<raridade>` | 256² | 20 arquivos | prévia, abertura, detalhe | `render-globes.js` com `SIZE = 256` e alfa | 5,24 MB (1,75 MB em BLP DXT5) |
| `Globes/closed`, `closed-256` | 128², 256² | 1 + 1 | globo embaçado, sem fita | three.js: mesmo globo, vidro fosco | 0,33 MB |
| `Veil/chimney-cold` | 256×512 | 1 | Chaminé fria com neve | canvas/SVG + playwright | 0,52 MB |
| `Veil/chimney-hot` | 256×512 | 1 | a mesma em brasa, revelada por recorte | mesmo desenho, paleta quente | 0,52 MB |
| `Veil/veil-fx` | 512² | 8 fogo + 4 neve + 9 peças | tudo o que se move | canvas + playwright (o gerador do protótipo) | 1,05 MB |
| `Veil/frimm` | 512×128 | 3 caras (+1 livre) | retrato | SVG rasterizado | 0,26 MB |

**Total novo:** cerca de 7,9 MB com tudo em TGA; 4,4 MB com os globos de 256 em BLP. Hoje `Media/Globes` pesa 1,4 MB.
Molduras, prateleira, placa, barra de chances e flocos são `SetColorTexture`: zero bytes.

Atlas `veil-fx` (512²): linhas 1 e 2, fogo, 8 quadros de 128 px (4×2); linha 3, neve do sacudir, 4 quadros de 128 px;
linha 4, raios 128, anel 128, clarão 128, fumaça 64, estrela 32, brasa 32, floco 32, fita 32, laço 128×64. Peças brancas,
tingidas com `SetVertexColor` pela cor da raridade.

Geração: tudo que é 3D (globos, globo fechado) sai do protótipo three.js por playwright, como hoje. O renderizador precisa de
`alpha: true` e fundo limpo; para o protótipo os 20 globos foram renderizados a 256 pelo mesmo caminho e o fundo recortado
por máscara. Chaminé, atlas e Frimm são 2D: uma página HTML com canvas/SVG, capturada pelo mesmo playwright e gravada com a
função `tga()` que já existe no script.

## Desempenho

- Teto: **64 texturas em movimento**, com a janela aberta na aba. Típico: 35 a 45.
  Neve 20 · fogo 2 · brilho da boca 1 · brasas 3 a 14 · fumaça 2 a 4 · estrelas 8 (só a 100%) · lendárias na prateleira 1 cada ·
  raios do detalhe 1 ou 2 · poeira 8 (só lendária aberta).
- Pico: revelação lendária, +30 texturas por cerca de 3 s (anéis 2, clarão 1, raios 2, escurecer 1, estrelas 18, fita 3, neve 1).
- **Dois OnUpdate ao todo:** a neve (20 Hz, já existe) e o flipbook do fogo (10 Hz, um para as duas chamas).
  Todo o resto é AnimationGroup em laço, criado uma vez.
- Nada roda com a janela fechada nem em outra aba: `OnHide` para os grupos e tira os OnUpdate. Tudo é filho da janela e
  recortado por ela (`SetClipsChildren`), nunca sobre a interface da Blizzard.
- `prefers-reduced-motion` não existe no jogo: a opção `snow` de hoje vira "animações do Winter Veil" (neve, brasas, raios).

## Frames e animações a implementar

| Peça | Como |
|---|---|
| Nível da Chaminé | `chimney-hot` ancorada embaixo, `SetHeight(h·pct)` + `SetTexCoord(0,1,1-pct,1)`; transição de 0,9 s por OnUpdate temporário |
| Fogo | 2 texturas no atlas, `SetTexCoord` por quadro a 10 Hz; a de trás espelhada e 3 quadros adiante; tamanho 44 a 110 px pelo nível, 140 a 100% |
| Brasas, fumaça, estrelas | AnimationGroup `REPEAT`: Translation + Alpha (+ Scale na fumaça), duração e atraso sorteados na criação |
| Chaminé cheia | Translation de uma faixa clara (ADD) atravessando, Scale na placa, 14 estrelas de uma vez, barra de chances com `SetWidth` |
| Embrulhar | Alpha do gelo, Scale X da fita horizontal, Scale Y da vertical, Scale com ressalto do laço, 8 estrelas (1,1 s) |
| Sacudir | Rotation ±9° com origem na base + Translation, 0,52 s; flipbook da neve por cima |
| Degrau de raridade | tremor (Translation de 70 ms em vaivém), anel (Scale + Alpha), clarão (Alpha, ADD), troca de textura em 160 ms de Alpha entre duas camadas |
| Lendária | antes do último degrau: camada preta a 62% sobre o corpo da aba, dois raios girando em sentidos opostos (Rotation, 22 s e 31 s), tremor de 1,3 s; depois 8 pontos de poeira caindo em laço |
| Prateleira | hover: sobe 3 px e balança uma vez (Rotation); lendária: uma faixa de brilho atravessando a cada 3,6 s |
| Teaser | Translation do gorro no `OnEnter` |

Sons (todos **a conferir** no cliente 2.5.x, sempre com `pcall`): aba 841, caixa/cena 856, embrulhar 863, sacudida 862,
degrau 3175, revelação comum/rara 878, épica/lendária 888, Chaminé cheia 8960. A animação `FlipBook` nativa do
AnimationGroup e `MaskTexture` também são a conferir; o desenho não depende de nenhuma das duas.

## O que não cabe no WoW

- Globo 3D que gira e o bilhete colado nas costas: fica no site. No jogo o bilhete é um cartão ao lado.
- Refração do vidro, brilho real, desfoque: não há shader. O brilho é textura somada.
- Neve por partícula dentro do globo: vira 4 quadros de atlas.
- Abertura instantânea (ver decisão 4), som próprio em laço, voz do Frimm.
- Neve ou qualquer efeito fora da janela do GuildOS.

## Em aberto

1. Globos de 256 px no pacote (+5,2 MB em TGA, +1,75 MB em BLP), ou tudo a 128 e a abertura menor.
2. A Chaminé visível e apagada antes do sorteio, contra o "não aparece" da 119 §10.
3. A etiqueta "bilhete caprichado: +1 nível" na revelação pede um campo novo no globo (`caprice`); hoje o jogo só poderia adivinhar pelo tamanho do bilhete.
4. Três sacudidas do jogador ou um clique só.
5. A cara do Frimm (a 121 deixou a arte fora de escopo): aprovar este desenho ou encomendar outro.

# Media

Texturas do botão do minimapa. TGA 32-bit sem compressão, origem topo-esquerda
(descriptor `0x28`), 64x64 — o WoW exige dimensões power-of-two e não carrega PNG.

| Arquivo | O que é |
|---|---|
| `minimap-logo.tga` | Escudo central do logo (`GuildOSM.png`), recortado em círculo. Já vem colorido, não tingir. |
| `minimap-ring.tga` | Anel fino branco. Tingido em Lua com `GuildOS.Colors.gold`, para acompanhar o tema e acender no hover. |

## Como regerar

`minimap-logo.tga` sai de `GuildOSM.png` na raiz do addon, recorte
`left=445 top=240 130x130` (o escudo, sem o wordmark), redimensionado para 64x64
e mascarado por um círculo de raio 31. O logo inteiro não serve: a 24px a espada,
o cajado, as asas e o texto "GUILD OS" viram borrão.

`minimap-ring.tga` é um `<circle cx=32 cy=32 r=30 stroke=white stroke-width=3>`
rasterizado a 64x64 — a 30px na tela isso dá um traço de ~1.4px.

## Fontes (o Salão, fase 3, #449)

Fontes em `Fonts/`, todas sob a SIL Open Font License 1.1, com as licenças junto, como a OFL exige.
Vêm do Google Fonts (`github.com/google/fonts`: `ofl/cinzel`, `ofl/alegreya`, `ofl/alegreyasans`).
Cinzel e Alegreya são fontes variáveis, e o WoW lê só a instância padrão (400) de uma: os arquivos
aqui são instâncias estáticas cortadas com o fontTools (`fontTools.varLib.instancer`, Cinzel em 700,
Alegreya em 400). Detalhes e fallbacks: `specs/salao/fase3.md`.

| Arquivo | Uso |
|---|---|
| `Fonts/Cinzel-Bold.ttf` | títulos: nome da guilda, título de card, cabeçalho de tabela, número de bloco; nunca abaixo de 10px |
| `Fonts/AlegreyaSans-Regular.ttf` | todo texto da interface; nunca abaixo de 11px |
| `Fonts/AlegreyaSans-Medium.ttf` | nome de membro |
| `Fonts/AlegreyaSans-Bold.ttf` | botão, distintivo, porta aberta, pílula escolhida |
| `Fonts/Alegreya-Regular.ttf` | texto para ler: recado, mensagem, campo de várias linhas |
| `Fonts/OFL-Cinzel.txt`, `Fonts/OFL-Alegreya.txt`, `Fonts/OFL-AlegreyaSans.txt` | licenças |

Fonte nova só aparece depois de reiniciar o cliente: `/reload` não basta na primeira vez.

## A arte do Salão (`Salao/`, fase 3, #449)

Gerada por `python3 tools/salao_art.py` (Pillow; `--check` diz se os arquivos batem com o script).
TGA 32-bit sem compressão, origem topo-esquerda (`0x28`), lados potência de dois. A lista e o uso de
cada uma estão em `specs/salao/fase3.md`; `tools/salao-art.lua` confere que cada textura que o código
nomeia existe e é um TGA que o WoW lê.

Texturas geradas por script: TGA 32-bit sem compressão, origem embaixo-esquerda (descriptor
`0x08`). `d` é a distância ao centro dividida pelo raio.

| Arquivo | Tamanho | O que é |
|---|---|---|
| `corner-2.tga` | 8x8 | branco opaco com a quina superior esquerda em raio de 2px, para 9-slice na barra de título e em popup. |
| `ring-28.tga` | 32x32 | anel branco de 28px de diâmetro e 2px de traço, para avatar de classe. |
| `renown-<série>-<n>.tga` | 128x128 | insígnias de Renome, `horde` e `alliance`, de 1 a 6. Saem da arte do site, `apps/web/public/renown/` (guildos.me, specs/068). |

## Winter Veil: globos, caixa, Chaminé, atlas, Frimm (guildos-web#673, S3)

Tudo TGA 32-bit sem compressão, origem topo-esquerda (`0x28`), **alfa real** (fundo transparente, sem placa
nem halo). Não há BLP: nenhuma ferramenta confiável de DXT5 disponível (Pillow não grava DXT5); em BLP DXT5
os 256 px cairiam para ~1/4 do peso (cerca de 2,5 MB no total em vez de 9,4 MB). O `.toc` não lista texturas.

Regerar (Playwright + Chromium, rede para o cdnjs do three.js r128):

```
node tools/render-globes.js <guildos-web>/specs/119-o-amigo-secreto/prototipo-globo.html   # Globes/ e Globes/256/
node tools/render-veil-assets.js                                                          # Veil/
```

| Arquivo | Tamanho | O que é | Peso |
|---|---|---|---|
| `Globes/<cena>-<raridade>.tga` | 128² | 20 globos (tree/cabin/snowman/fire/mountain × common/rare/epic/legendary) | 20 × 64 KB |
| `Globes/256/<cena>-<raridade>.tga` | 256² | os mesmos a 256 | 20 × 256 KB |
| `Globes/closed.tga`, `Globes/closed-256.tga` | 128², 256² | globo de vidro embaçado, sem cena nem fita | 64 KB, 256 KB |
| `Veil/giftbox.tga`, `giftbox-256.tga` | 128², 256² | caixa de presente fechada, fita e laço | 64 KB, 256 KB |
| `Veil/giftbox-open.tga`, `giftbox-open-256.tga` | 128², 256² | caixa com a tampa solta | 64 KB, 256 KB |
| `Veil/chimney-cold.tga`, `chimney-hot.tga` | 256×512 | Chaminé fria com neve / em brasa; o desenho (256×428) fica encostado embaixo, 84 px de cima vazios | 512 KB cada |
| `Veil/veil-fx.tga` | 512² | atlas: fogo 8 quadros de 128 (4×2), neve do sacudir 4×128, raios, anel, clarão 128, fumaça 64, estrela, brasa, floco, fita 32, laço 128×64 (linhas 1–4, ver addon.md) | 1 MB |
| `Veil/frimm.tga` | 512×128 | rush, happy, oops (128 px cada) + 1 casa livre | 256 KB |

Peso: `Globes/` 128 px 1,56 MB · `Globes/256/` 5,0 MB · `Veil/` 2,9 MB · **total 9,4 MB** (9 896 836 bytes).
Chaminé, atlas e Frimm vêm do código do protótipo (`prototipo-addon.html` da spec 122), copiado no gerador.

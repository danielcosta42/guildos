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

## Fontes (Swiss 2.0, #361)

Fontes em `Fonts/`, todas sob a SIL Open Font License 1.1. A licença vai junto no pacote, como a
OFL exige. A Plex Sans veio de `github.com/IBM/plex` (release `@ibm/plex-sans@1.1.0`,
`packages/plex-sans/fonts/complete/ttf`); a Plex Mono, de `github.com/google/fonts` (`ofl/ibmplexmono`).

| Arquivo | Uso |
|---|---|
| `Fonts/IBMPlexSans-Regular.ttf` | todo texto sem papel, corpo; nunca abaixo de 11px |
| `Fonts/IBMPlexSans-Medium.ttf` | botão, nome de membro |
| `Fonts/IBMPlexSans-SemiBold.ttf` | wordmark, título de janela e de seção, nome de item |
| `Fonts/IBMPlexMono-Regular.ttf` | número de tabela, legenda, aba, distintivo, métrica; nunca abaixo de 10px |
| `Fonts/IBMPlexMono-Medium.ttf` | cabeçalho de coluna |
| `Fonts/OFL-IBMPlexSans.txt`, `Fonts/OFL-IBMPlexMono.txt` | licenças |

Fonte nova só aparece depois de reiniciar o cliente: `/reload` não basta na primeira vez.

Texturas geradas por script: TGA 32-bit sem compressão, origem embaixo-esquerda (descriptor
`0x08`). `d` é a distância ao centro dividida pelo raio.

| Arquivo | Tamanho | O que é |
|---|---|---|
| `corner-2.tga` | 8x8 | branco opaco com a quina superior esquerda em raio de 2px, para 9-slice na barra de título e em popup. |
| `ring-28.tga` | 32x32 | anel branco de 28px de diâmetro e 2px de traço, para avatar de classe. |
| `renown-<série>-<n>.tga` | 128x128 | insígnias de Renome, `horde` e `alliance`, de 1 a 6. Saem da arte do site, `apps/web/public/renown/` (guildos.me, specs/068). |

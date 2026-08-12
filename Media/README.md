# Media

Texturas do botão do minimapa. TGA 32-bit sem compressão, origem topo-esquerda
(descriptor `0x28`), 64x64 — o WoW exige dimensões power-of-two e não carrega PNG.

| Arquivo | O que é |
|---|---|
| `minimap-logo.tga` | Escudo central do logo (`GuildOSM.png`), recortado em círculo. Já vem colorido, não tingir. |
| `minimap-ring.tga` | Anel fino branco. Tingido em Lua com `BRutus.Colors.gold`, para acompanhar o tema e acender no hover. |

## Como regerar

`minimap-logo.tga` sai de `GuildOSM.png` na raiz do addon, recorte
`left=445 top=240 130x130` (o escudo, sem o wordmark), redimensionado para 64x64
e mascarado por um círculo de raio 31. O logo inteiro não serve: a 24px a espada,
o cajado, as asas e o texto "GUILD OS" viram borrão.

`minimap-ring.tga` é um `<circle cx=32 cy=32 r=30 stroke=white stroke-width=3>`
rasterizado a 64x64 — a 30px na tela isso dá um traço de ~1.4px.

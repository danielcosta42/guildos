# O mapa da guilda, de volta e ao vivo (#449)

## Por quê

A auditoria B23 (#286) tirou o mapa: mostrava "em algum lugar desta zona" no centro do mapa. O mantenedor quer
o contrário: **o membro no mapa, na posição real, em tempo real**. Base restaurada de `c9f810e^`
(`Modules/GuildMap.lua`, `UI/GuildMap.lua`, `tools/minimap-dots.lua`, a entrada do menu do minimapa, a caixa
"Mostrar membros da sua zona no minimapa", `/gos map`); `ResolveGuildDB` não apaga mais `guildMapPrefs`.

## Protocolo (canal GUILD, `CommSystem` → ChatThrottleLib, prioridade NORMAL)

- **`MW:<mapa>`** — "estou olhando o mapa `<mapa>`". Vai quando o mapa-múndi abre, quando o mapa mostrado muda
  (no máximo a cada 2 s; a última mudança nunca se perde) e de novo a cada **20 s**. `MW:<mapa>s` é o ritmo
  lento (os pontos do minimapa, só com um membro online na zona pelo roster). `MW:0` encerra. Um olhar não
  renovado em **30 s** acaba sozinho.
- **`MP:<mapa>,<x>,<y>,<direção>,<flags>[,<instância>]`** — a posição de quem envia: x e y em 1/10000 do mapa,
  direção em 1/64 de volta, flags 1 = em combate, 2 = em instância (sem coordenadas, só o nome), 4 = "onde"
  (troca de zona). `MP:-` retira o pino (privacidade desligada).
- **Quem envia:** só quem está sendo olhado, isto é, cujo mapa é o olhado ou está abaixo dele (cadeia de
  `parentMapID`). Na própria zona, ritmo **rápido**: a cada **2 s** andando (mais de 0,15% do mapa), pelo
  menos a cada **10 s** parado. Continente, mundo ou minimapa: ritmo **lento**, 10 s / 25 s. Ninguém olhando:
  **nada**, salvo uma linha "onde" por troca de zona (no máximo a cada 10 s). Um olhar novo é respondido com
  atraso aleatório de até 1,5 s, para não chegar tudo de uma vez.
- **Multidão:** com N membros ouvidos no mesmo mapa, o intervalo mínimo vira N/5 s (no ritmo lento, N = todos
  os ouvidos): um mapa custa à guilda ~5 mensagens/s, por mais gente que haja nele.
- **Grupo:** membros da party/raid são lidos no próprio cliente (`C_Map.GetPlayerMapPosition(mapa, "partyN")`),
  sem mensagem.
- **Segurança:** identidade é o remetente do envelope, só GUILD, todo número limitado; classe e nível vêm do
  roster.

## Orçamento (`tools/guild-map.lua`)

100 membros online, 3 olhando, 60% andando, 5 minutos simulados com a própria decisão do módulo (`_Owe`):

| Cenário | msg/s na guilda | cliente mais ativo |
|---|---|---|
| espalhados em 20 zonas, 3 olhando 3 zonas | 5,3 | 0,5 |
| todos numa zona, 3 olhando ela | 5,2 | 0,05 |
| 1 olhando o continente, 2 zonas | 8,0 | 0,5 |
| 3 olhando o mundo | 4,7 | 0,05 |
| 3 minimapas | 1,3 | 0,1 |
| ninguém olhando | 0 | 0 |

O teste falha acima de **10 msg/s** na guilda ou **0,5 msg/s** por cliente. Cada posição tem **27 bytes** no fio
(depois de comprimir e codificar; teto do teste: 40), um olhar 12: ~270 B/s recebidos por cliente no teto.

## Desenho

- **Mapa-múndi:** quadro próprio sobre o canvas (`Compat.GetWorldMapCanvas`), sem data provider (evita taint no
  pool de pinos da Blizzard). Avatar redondo da cor da classe com anel dourado (`UI:CreateAvatar`); passar o
  mouse: nome, nível e classe, zona, "atualizado há N s"; desliza entre atualizações (interpolação no tempo
  entre as duas últimas); esmaece após **30 s**, some após **2 min**; cresce até 1,5× com o zoom. Em continente
  e mundo a posição é convertida (`GetMapRectOnMap`, depois `GetWorldPosFromMapPos`/`GetMapPosFromWorldPos`,
  depois a cadeia de pais), com a transformação guardada por par de mapas.
- **Lista no mapa** (canto superior direito, card escuro): "Membros da guilda neste mapa (N)", clicar pisca o
  pino ou abre o mapa do membro; "Em outro lugar (N)" com zona ou instância; avisos (posição não compartilhada,
  cliente sem posições). O X fecha; `/gos map` e o menu do minimapa reabrem.
- **Minimapa:** ponto na cor da classe na direção e distância reais (raio do minimapa por zoom, dentro e fora),
  preso à borda quando longe, gira com o minimapa giratório; nada em instância. Configurações › Interface.

## Privacidade

Configurações › Perfil › Privacidade: **"Compartilhar minha posição com a guilda"** (ligado por padrão).
Desligado, o cliente nunca envia posição (manda um `MP:-` ao desligar) e a lista diz isso. Nunca vai: em
instância em combate ou durante um chefe; com o chat em lockdown; quando o mapa ou a posição vêm como Secret
Value ou nil. Em instância vai só "em instância: <nome>", sem coordenadas.

## O que só aparece para quem tem o addon

Só membros **com Guild OS e compartilhando** aparecem fora do grupo; membros da party/raid aparecem sempre (lidos
aqui). Sem o addon, sem pino. A lista lembra isso no rodapé.

## WoW: Forever

`Probe.APIS` ganhou `C_Map.GetWorldPosFromMapPos`, `C_Map.GetMapPosFromWorldPos`, `C_Map.GetMapRectOnMap`,
`CreateVector2D`, `GetPlayerFacing`, `IsIndoors`, `Minimap.GetZoom`, `WorldMapFrame.ScrollContainer` e
`WorldMapFrame.GetCanvasZoomPercent`. Tudo passa por `Compat` (o `compat-guard` agora barra `C_Map` fora dele);
o que faltar degrada: sem posição, a lista diz "o mapa deste cliente não dá posições"; sem conversão, só os
pinos do mapa mostrado; sem zoom do minimapa, sem pontos. Oito mapas do Forever ainda são criptografados
(`docs/forever/README.md`): neles `GetMapInfo` pode faltar e a cadeia de pais para ali.

## OpenMap (mesmo mapa, outro addon)

[OpenMap](https://github.com/openmap-world/openmap) (MIT, WoW: Forever e retail; pasta `OpenMap`) também põe
guildmates no mapa: com a opção dele **"Compartilhar sua localização"** (desligada por padrão) cada cliente manda,
pelo canal GUILD e prefixo `OpenMapLoc`, `L1<tab>mapa<tab>x<tab>y<tab>classe<tab>nível` a cada 10 s andando e 60 s
parado, olhando alguém ou não, e `L0` ao parar; nunca de dentro de instância. Quem não manda aparece como selo na
zona, pelo roster.

- **Guild OS lê, nunca manda, as linhas do OpenMap** (`GuildMap:HandleOpenMap`): só GUILD, só de quem está no roster,
  nunca a própria, mapa conhecido, x e y em 0..1 (nunca 0,0), no máximo uma a cada 2 s por membro; classe e nível
  vêm do roster. O pino esmaece após 70 s e some após 150 s (o ritmo parado dele). A linha do próprio Guild OS ganha
  enquanto fresca; o `L0` do OpenMap tira só o pino do OpenMap. Os pinos do OpenMap não entram na "multidão" que
  espaça o ritmo do Guild OS. Dica no pino: "Compartilhado pelo OpenMap".
- **O ritmo do Guild OS fica** (sob demanda): o do OpenMap custa 6,7 msg/s com 100 compartilhando e 13,3 com 200,
  mesmo sem ninguém olhando (`tools/guild-map.lua` imprime e confere); o do Guild OS é 0 sem ninguém olhando e
  ≤ 8 com três olhando.
- **Coordenadas:** o OpenMap manda o mesmo que o Guild OS (uiMapID + x, y do mapa) e converte com
  `GetMapRectOnMap`; não usa HereBeDragons para os seus pontos nem `UnitPosition`. Nada a adotar aí. (Ele recoloca no
  mapa costurado os pinos de outros addons feitos com HereBeDragons-Pins; os do Guild OS são quadro próprio sobre o
  canvas e ficam no mapa de baixo.)
- **Lista:** "Nesta zona pelo roster, sem posição (N)" — o selo de zona do OpenMap, como linha (só em mapa de zona).
- **Coordenação, sem aviso:** com o OpenMap carregado e a opção dele "Membros da guilda no mapa" ligada (lida, nunca
  escrita, de `OpenMapDB.worldmap.guild`; o mapa dele desligado conta como não), o Guild OS **não desenha pino nem
  ponto no minimapa** de quem o OpenMap já mostra: quem teve linha do OpenMap ouvida aqui há até 150 s (o tempo de
  vida do ponto dele; `GuildMap.openMapSeen`, guardado mesmo quando a linha do Guild OS ganha, e apagado pelo `L0`),
  e os membros do grupo quando a opção dele "Membros do grupo e da raide" (`OpenMapDB.worldmap.group`) também está
  ligada (o OpenMap tira o grupo dos pontos da guilda e o desenha à parte). Desenha só quem compartilha pelo Guild OS e
  não pelo OpenMap (e o grupo, se o OpenMap não o desenha). Com a opção desligada ou sem o OpenMap, desenha todos. A
  opção é relida ao abrir ou mudar o mapa e no máximo a cada 30 s (`OPENMAP_RECHECK`), nunca por quadro. A lista do
  mapa continua com todos, com "no OpenMap" na linha (e "Desenhado pelo OpenMap" na dica) de quem ele desenha. O
  aviso das versões de teste (janela única por personagem, linha na lista e `GuildOSDB.openMapNotice`) saiu; o
  `GuildOSDB.openMapNotice` antigo é apagado ao carregar.

## Fogueiras da guilda (WoW: Forever; ChehulNet v16)

O Warmth (o addon de fogueiras da família) e o **farol** do ChehulNet v16 (`CN:EnableCamps`, chehulnet#13)
anunciam no prefixo `ChehulCamp` a fogueira que o jogador acende: `C2|A|mapa|x|y|zuid|tier(+letras)|n|idade|
objetos|pessoas|nota` (o farol manda `C2|A|mapa|x|y|zuid|<tier>l|1|idade||Nome~c|`), de novo a cada 240 s
enquanto perto, e `C2|X` quando acaba. Contrato completo em `chehulnet/AGENTS.md` (seção 2 e a tabela de prefixos).

- **Farol (gerar):** `Modules/ChehulNetWire.lua` chama `ChehulNet:EnableCamps{ store, ask }` só no WoW: Forever
  (nem Anniversary nem retail: os kits de acampamento não existem lá). `store` é `GuildOSDB.camps` (`consent` =
  true/false/nil). A lib decide tudo: nada sai sem o sim; a pergunta vem na **primeira fogueira acesa** (nunca no
  login), no máximo uma vez por sessão; com o Warmth carregado, nem pergunta nem anuncia. `ask` abre a janela do
  kit `GuildOS:ShowCampPrompt` (UI/GuildMap.lua) pela fila de popups (`ShowWhenClear`, chave `campconsent`): "Avisar
  a rede quando você acender uma fogueira? Outros jogadores veem a fogueira no mapa (com o Warmth). Só a fogueira e
  o seu nome; dá para mudar nas configurações." Sim/Não chamam `callback(true/false)`; fechar no X não responde (a
  lib pergunta na próxima sessão). Configurações › Perfil › Privacidade: **"Anunciar minhas fogueiras na rede"**
  (só no Forever), lida de `CN:CampState()` e gravada por `CN:SetCampConsent(sim)`.
- **Mapa (mostrar):** `GuildMap` escuta `ChehulCamp` com a **sua própria rota AceComm** (`RegisterComm` num objeto
  próprio; o evento cru se faltar AceComm). Nunca `Mesh:Register`: isso tiraria do mesh o handler do prefixo, que
  repassa as fogueiras do Warmth. Só no Forever, só **GUILD**, só de quem está no roster (nunca a própria), quem
  acendeu é o remetente do envelope (o campo de pessoas não é lido). Cada campo é validado (`DecodeCamp`): mapa
  1..1000000 e conhecido, x/y em 0..1, zuid só dígitos, tier 1/2/3 = Básico/Artesão/Especialista com letras
  desconhecidas ignoradas, idade < 60 min, linha até 255 bytes e 16 campos. No máximo uma linha por membro a cada
  2 s (`CAMP_GAP`) e 60 fogueiras (`CAMP_MAX`). Some no `C2|X` (por GUILD), 60 min depois de acesa
  (`CAMP_LIFE`, pela idade anunciada) ou 10 min sem batida (`CAMP_QUIET`).
- **Desenho:** uma chama (`Interface\Icons\Spell_Fire_Fire`, ícone do jogo em todos os clientes) no ponto, no mapa
  mostrado e nos de cima (mesma conversão dos pinos); dica "<Nome> acendeu uma fogueira em <Zona> · nível
  <tier>" e "Clique para marcar um ponto de destino"; o clique põe o waypoint do jogo (`Compat.SetUserWaypoint`:
  `C_Map.SetUserWaypoint` + `C_SuperTrack`). Rodapé da lista: "Instale o Warmth para ver o círculo e montar a sua".
- **Com o Warmth carregado** (`Compat.IsAddOnLoaded("Warmth")`) a camada some (o Warmth já as desenha, com o
  círculo); fora do Forever também. O lembrete dos oficiais (AddonReminder) não empurra o Warmth.
- **Janela do membro:** a lista de addons (`Mesh.ADDON_LABELS`) nomeia `cf` = Warmth e `ls` = Lodestar.
- Testes: `tools/guild-camps.lua`.

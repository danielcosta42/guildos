# 119 — O Amigo Secreto de Winter Veil: o globo de neve (#659)

Addon: danielcosta42/guildos#437. Redesenho de 2026-11-25 (comentário da #659, `redesenho-globo.md`, protótipo aprovado em
`prototipo-globo.html`). **Este arquivo substitui o primeiro desenho** (lista de crafts, teto em gold, entrega por correio),
que ainda está nos PRs guildos-web#660 e guildos#438 e é reescrito nas mesmas branches. As chaves do `/admin/flags` (#661)
ficam como estão. Layouts das telas novas: canvas do evento
(https://claude.ai/artifact/PKzUYXLSDzSDnjh8K15T2Z), a aprovar antes do código.

Itens marcados **[a confirmar]** ainda esperam o maintainer.

## 1. Problema e objetivo

O Feast of Winter Veil (15/dez a 2/jan) é a época de festa do WoW: Forever. O objetivo é um evento de engajamento que o
membro casual também joga, sem raidar, **100% digital e sem gold**:

- **um Amigo Secreto de globos de neve**: cada participante embrulha um globo de neve em 3D para quem tirou (escolhe a
  cena e escreve um bilhete) e abre o que recebeu no Natal;
- **uma Chaminé**: a barra comum da guilda, a porcentagem dos participantes que já embrulharam;
- **uma Coleção**: o globo fica para sempre na conta de quem recebeu, no perfil;
- **um ranking público entre guildas**, por membro, para que uma guilda pequena dispute com uma grande.

Grátis: nada aqui pergunta `hasPlan`. **Nada aqui é gold, item, correio ou trade**: o evento não lê o jogo para saber se
um presente foi entregue. Embrulhar é um ato do site (ou do addon), e o servidor é quem confere.

**Quando abre e quem vê antes** (decisão de 2026-11-25, mantida): pela chave `winter-veil` do backoffice
(`/admin/flags`, specs/120), nunca por variável de ambiente. Abre sozinha na data marcada, sem deploy; antes disso só as
contas testadoras veem as telas e recebem o evento no próprio bloco do jogo (`GOSVEIL1.event`); o bloco da guilda não fala
do evento e o manual não tem a entrada. Sem a chave, o evento não existe.

## 2. Quem faz o quê

| Quem | Onde | O quê |
|---|---|---|
| Oficial (`mayConfigure`) | site, `config` da guilda → Winter Veil | abre o evento do ano e define as regras; sorteia; vê só contagens |
| Membro com personagem confirmado (`member: { leftAt: null }`) | site e addon | entra, vê quem tirou, embrulha, abre o que recebeu |
| Dono de uma conta do Discord | site (painel `/dashboard`) e addon | vê a própria Coleção e o perfil |
| Qualquer pessoa | `/winter-veil`, página pública do personagem | ranking (números de guildas) e o globo e o ano de quem os recebeu; nenhum bilhete, nenhum doador |

## 3. As regras de um evento

Um evento por guilda e ano (`VeilEvent`, único em `guildId, year`). O oficial define:

- **fim das inscrições** (`joinUntil`);
- **prazo de embrulhar** (`wrapUntil`): por padrão **20/12 às 23h59 no fuso da guilda** (`gameClockZone`);
- **abertura** (`openAt`): por padrão **25/12 à 0h** no mesmo fuso. Antes dela ninguém abre nada;
- **prazo de reatribuição**: dias antes de `wrapUntil` (1 a 7) em que quem ainda não embrulhou perde o par;
- **rank mínimo** para entrar (opcional; `null` é todo mundo).

Ordem obrigatória: `joinUntil < reassignAt < wrapUntil < openAt`, com `reassignAt = wrapUntil − reassignDays`. Saem do primeiro
desenho: teto, tipo de presente, necessidades do banco, `VeilPrice`.

As regras mudam até o sorteio, exceto o ano; depois do sorteio só `wrapUntil` e `openAt` (nunca para antes de agora);
depois que a reatribuição rodou o prazo dela não muda; depois de `openAt` nada muda. Dois oficiais abrindo o evento ao
mesmo tempo: o segundo salvamento vira uma mudança do evento do primeiro.

## 4. Entrar

Igual ao primeiro desenho, sem a lista: **uma entrada por jogador** (`Member.mainKey ?? key`, um alt entra como o seu
principal) e **uma por conta do Discord** (índice único parcial em `eventId, discordUserId`); entrar e sair travam a linha do
evento (`FOR SHARE`) e o sorteio a atualiza; entra-se e sai-se só até `joinUntil` e antes do sorteio; entrar pelo site pede um
personagem confirmado do próprio visitante, pelo jogo a entrada chega em `GOSCOMP1.veil.join`. **Quem fala por quem no
upload:** o código de um oficial fala pela guilda **só em entrar e sair**; embrulhar e abrir são sempre do doador e do receptor (as chaves da conta do código), ou um arquivo perguntaria ao servidor que par existe. Qualquer outro código só pelos jogadores da conta que o criou
(`token.createdBy`), o upload do próprio membro só por ele.

## 5. O sorteio e o segredo

- Um oficial sorteia uma vez, depois de `joinUntil` e com pelo menos 4 participantes. É **um ciclo**, embaralhado com
  `crypto.randomInt`, cada um dá ao seguinte; ninguém tira a si mesmo nem um alt de si. Um `UPDATE … WHERE "drawnAt" IS NULL`
  do evento na mesma transação dos pares: dois cliques nunca sorteiam duas vezes.
- **Os pares são segredo, como o voto do tabardo** (specs/060); `lib/veil.ts` continua a única porta. Lê um par: o doador,
  sobre o próprio (`myPair`); o cron, para reatribuir; o servidor, ao abrir um globo (o receptor); **qualquer membro, só
  depois de `openAt` e só do globo já aberto** (§9). Oficiais, backoffice e logs veem contagens e, por membro, se
  embrulhou — **nunca quem recebeu** (o "embrulhou" de um e o "recebeu" de outro virando juntos entre duas olhadas
  entregariam o par). Sai a leitura do ingest para conferir entrega: **o jogo não confere mais nada**.

## 6. Embrulhar

- O doador escolhe uma **cena** (`tree`, `cabin`, `snowman`, `fire`, `mountain`) e escreve um **bilhete** de até 80
  caracteres (texto simples: sem `@`, link, markdown nem caractere de controle; `cleanNote` lê inteiro ou recusa). O bilhete
  pode ser vazio, mas o globo não ganha o capricho (§7).
- Vale de `drawnAt` até `wrapUntil`. Embrulhar de novo antes do prazo **substitui** cena e bilhete (`UPDATE … WHERE
  "openedAt" IS NULL`), e o carimbo de quando embrulhou (`wrappedAt`) é o da primeira vez, para a Chaminé não oscilar.
- Pelo site e pelo addon, os dois lados: vence o mais novo (`changedAt`, limitado ao relógio do servidor). Um globo que
  não passa nas regras é recusado inteiro.
- O globo guarda quem deu, para quem e o ano. **Sem embrulho até `wrapUntil`** (nem voluntário que pegasse o par, §8): quem
  envia o globo de quem não recebeu é **o personagem do evento** (o anfitrião do RP, constante no código, **Frimm, §6.2**,
  o mesmo do kit de lançamento). Ele manda um globo com modelo (cena sorteada) e raridade sorteados como os de todos os
  outros (§7, sem capricho) e **uma carta** (§6.1). Ninguém fica sem globo, e o receptor vê o anfitrião como doador.

### 6.1 A carta do anfitrião

- **Sem IA.** A carta é uma de **20 mensagens fixas**, escritas no código e traduzidas **nos nove idiomas** (`lib/veil-letters`,
  vinte entradas por idioma, `missingFrom` em `test/i18n.test.ts` falha até todas existirem). Nada aqui chama `aiCall`:
  não há custo, chave nem recusa, e `/privacy` não muda.
- **Sorteada no servidor**, uma vez, em `wrapUntil` (junto do fechamento da Chaminé), e gravada no par
  (`VeilPair.hostLetter`, o índice 0 a 19, nunca o texto). O idioma é o de quem lê (`say`/copy do leitor), então o mesmo
  índice é lido em qualquer idioma. Sem repetir a carta entre pares da mesma guilda enquanto houver cartas sobrando.
- Pode levar `{nome}`, o personagem do receptor como a guilda o vê; **nenhum outro dado do jogo** (nada de classe, nível,
  conquista) nem outro membro. Quem tem `optedOut` recebe a carta sem `{nome}`.
- Visibilidade: a do bilhete, **só quem divide o Discord com a guilda** (e o dono), nunca o público.
- Tom: engraçadinho, de um anfitrião de festa; revisado pelo maintainer junto da copy.

### 6.2 O anfitrião: Frimm

O anfitrião é **Frimm**, o duende embrulhador (escolha do maintainer, 2026-11-25): pequeno, apressado, erra o endereço de vez
em quando, e é daí que vem o tom das 20 cartas. Personagem original, sem arte nem nome da Blizzard. Constante `VEIL_HOST =
"Frimm"` e a placa do doador. **Sem voz nesta versão: só texto** (as 20 cartas e a placa do doador; nenhum áudio, nem no site nem no addon). A cara dele (imagem) e o resto do papel (Discord, addon, cerimônia) são do kit de lançamento.

## 7. A raridade

Sorteada **no servidor, uma vez, na abertura** (o receptor sacode o globo, §9) e gravada; o cliente nunca a decide.

- Base: **comum 60%, rara 25%, épica 12%, lendária 3%**.
- **Chaminé cheia** (100% dos pares contam, §10): as chances de rara, épica e lendária **dobram** (a comum fica com
  o resto: 20%, 50%, 24%, 6%). Vale a Chaminé do instante de `wrapUntil`, gravada no evento (`chimneyPct`), nunca a de depois.
- **Capricho:** o bilhete preenchido **embrulhado antes do prazo** sobe **um nível** (comum → rara → épica → lendária,
  teto lendária). Conta a quantidade de caracteres do bilhete já limpo: **40 ou mais** (decidido em 2026-11-25). O globo do anfitrião (§6) não tem capricho.
- Uma `crypto.randomInt` para o sorteio e uma linha só: `UPDATE … WHERE "openedAt" IS NULL` — duas abas abrindo juntas
  gravam uma raridade, a mesma para as duas. `rarityOf(roll, chimneyFull, caprice)` é puro e testado por faixa.

## 8. Quem não embrulha

Em `reassignAt` o cron (`veil-reassign`) passa cada par sem globo a um **voluntário**: quem marcou "posso dar mais um" e já
embrulhou o próprio, não é o receptor nem quem perdeu o par; cada voluntário recebe no máximo um par extra, por ordem de
embrulho; o par guarda `lostBy`. O evento é carimbado (`reassignedAt`) antes de qualquer mudança: roda uma vez. Sem
voluntário, o par fica como está (e em `wrapUntil` o anfitrião manda o globo, §6). Ninguém é avisado além do novo doador.

## 9. Abrir

De `openAt` em diante, só o **receptor** abre o próprio globo (site ou addon): o servidor sorteia a raridade (§7), grava
`openedAt` e devolve o globo com raridade, cena, ano, doador, bilhete e se o bilhete subiu um nível (`caprice`). Antes disso o
receptor vê só **uma caixa de presente** de alguém da guilda (nem a cena, nem o globo; decidido em 2026-11-25, spec 122).
Abrir é **um clique** (site e addon): as primeiras etapas da cerimônia (a fita cai, a tampa sai, o vidro desembaça) não
dependem da raridade e cobrem a ida ao servidor; no addon, que recebe pelo companion, o clique faz o pedido e a cerimônia
toca quando o globo aberto chega. Abrir é da pessoa, não da data: quem não abriu até o fim do evento abre depois (a data é só
o piso). O doador vê o próprio globo (cena, bilhete) e **só** quando o receptor o abriu, a raridade.

**Revelação** (a corrente da guilda): depois de `openAt`, todo membro da guilda vê os pares **dos globos já abertos** (quem
deu, para quem, cena, raridade); o par de um globo fechado continua segredo. Ninguém fora da guilda vê.

## 10. A Chaminé

`Chaminé = pares que contam ÷ pares`, 0 a 100%, arredondada para baixo. Um par conta quando o doador o **embrulhou**
(`wrappedAt`) **ou** fez uma quest do Winter Veil no jogo dentro da janela (`VeilEntrant.playedAt`, #671: de 15/12 00:00
UTC-3 a `wrapUntil`, só com o addon, só a da própria pessoa); a fatia das quests aparece à parte (azul). O participante que
perdeu o par para um voluntário conta quando o par é embrulhado por quem o tem. Calculada pelo site (sai o `needs`, o banco
e o `have/want`); a participação pelo jogo vem do cliente e é forjável, o que se aceita porque só ajuda a encher a Chaminé.
**Antes do sorteio ela aparece apagada** ("acende no sorteio", decidido em 2026-11-25, spec 122) e, depois de `wrapUntil`,
congelada no `chimneyPct`. "Cheia" é 100% de verdade. Ela vale o dobro de chances de §7 e 20% do ranking.

## 11. A Coleção

- **O colecionável é uma linha própria** (`Ornament`: id, ano, evento, tipo `snowglobe`, cena, raridade, **conta dona**
  (`discordUserId`), doador (entrada), bilhete, `openedAt`). É da **conta**, não do personagem: um alt e o principal
  mostram o mesmo globo. `@@unique([eventId, receiverId])`; nasce na abertura, só nela.
- **O perfil da conta** (a Coleção mora no painel `/dashboard`, e a mesma tela no addon): "cada conta ganha uma nova tela de perfil, onde moram as
  informações do jogador e seus colecionáveis" (maintainer, 2026-11-25). Este desenho cobre a Coleção; por ora o perfil traz **só a Coleção**
  (decidido em 2026-11-25), com um cabeçalho da conta; o resto fica para depois.
- **Quem vê o quê.** O globo, a cena, a raridade e o ano são **públicos** na página do personagem (`/c/<key>`); **o bilhete e
  quem deu, só para quem divide o Discord com a guilda** (`mayView`, a mesma regra de `/guild/<key>`), nunca nem a
  contagem para o público. `optedOut` **tira o globo da página pública** (como a regra de não nomear, #608); o dono continua
  vendo o próprio no perfil. **O pedido tem chave própria, `globesHidden`, lida junto com `optedOut`**
  (`ornamentsOfCharacter`). A caixa na Coleção (`setGlobesHidden`, `app/dashboard/actions.ts`) **marcada** liga `globesHidden` e
  também `feedOptOut` (#252) nos personagens da pessoa em todas as guildas, como a nota ao lado diz (vale para os dois);
  **desmarcada** só desliga `globesHidden` e **nunca limpa** `feedOptOut`, que a pessoa pode ter pedido em outro lugar. Um guilda não vê o bilhete de um globo de outra.
- **Fora de `GOSGILD1` e de `Inbox` público**: a Coleção de uma pessoa vai ao jogo só em `GOSVEIL1` (por sessão, §12).

## 12. O ranking público

`/winter-veil` mostra as guildas com o evento do ano e pelo menos 5 participantes. Por membro:
`pontos = round(1000 × (0,4 × participação + 0,4 × embrulhados + 0,2 × Chaminé))`, em que participação =
participantes ÷ jogadores com personagem confirmado (até 1), embrulhados = globos embrulhados ÷ pares (0 antes do sorteio) e
Chaminé = §10 (a de `wrapUntil` depois dele). Empate: mais participantes, depois o nome. Só números da guilda, nunca um nome
de membro nem a contagem de quem não embrulhou. Página pública: em `isPublicPath`.

## 13. Para o jogo

O jogo só **mostra e pede**; quem decide é o servidor (sorteio, raridade, regras).

- **`GOSGILD1.veil`** (bloco da guilda, todos os jogos), enquanto houver evento do ano:
  `{ year, joinUntil, wrapUntil, openAt, reassignDays, drawn, counts: { entrants, wrapped, pairs, opened }, chimney }`, `chimney`
  em % inteiro; depois de `openAt`, `reveal: [{ giver, to, scene, rarity }]` **só dos globos abertos**; para um código de
  oficial, `entrants: [{ key, wrapped }]`; depois do sorteio e até `wrapUntil`, o `salt` do lacre e `carriers`.
  Um addon antigo não lê `veil`. **Sai:** `cap`, `kind`, `needs`, `delivered`, a lista de cada um.
- **`GOSVEIL1` v2** (a v1 do primeiro desenho nunca saiu do teste; por sessão, `/api/app/roster`: `veil: [{ guildKey, text }]`): para cada personagem da pessoa que participa,
  o sorteado (nome, classe), o globo dela (cena, bilhete, `wrapped`), o globo que ela recebeu (só aberto: cena,
  raridade, bilhete, doador, ano), `relay` (pares que repassa) e `event` (como o bloco da guilda, para o testador, antes
  da abertura). **A Coleção** vai aqui: `collection: [{ id, year, scene, rarity, openedAt, from?, note? }]` da conta (o
  `from`/`note` só dentro dela, nunca no `GOSGILD1`).
- **`GOSCOMP1.veil`** do jogo para o site: `join` e `leave` (como antes) e **`wrap: [{ giver, scene, note, at }]`**
  (o embrulho feito no addon; `to` nomeia o par quando o doador tem dois, §8) e **`open: [{ receiver, at }]`** (o pedido de abrir);
  `leaves: [{ key, at }]` sai antes do sorteio; uma linha de `wrap` com cena fora das cinco ou bilhete recusado cai inteira. **Sai** `prices`, `needs`, `deliveries`.
  O ingest trata tudo como não confiável: valida pelo doador/receptor do par, escreve pelo `UPDATE … WHERE` e **a raridade
  vem do servidor, nunca do export**.
- **Repasse** (decisão do maintainer, 2026-11-25: "segue, só para o par"): igual ao primeiro desenho, só que leva o par
  (doador → sorteado) e nada mais: **o embrulho de quem não tem companion é feito no site**. O lacre continua ofuscação,
  não segredo (XOR de `${salt}:${giverKey}`), pela mesma decisão. Um par que só o próprio sorteado poderia levar fica sem
  repasse.
- **As imagens do addon**: uma por cena × raridade (5 × 4 = 20), **TGA 128 px, um quadro** (decisão do maintainer),
  geradas em lote por Playwright sobre `prototipo-globo.html`. O globo "fechado" (embrulhado) tem uma só imagem. O addon
  nunca carrega 3D: o WoW não lê modelos de fora.

**Cron:** `veil-reassign` (em `reassignAt`) e `veil-close` (em `wrapUntil`: congela `chimneyPct` e manda os globos do Frimm; abrir um globo também fecha, então um atraso do cron não prende ninguém).

O companion conhece o prefixo `GOSVEIL1` e escreve o bloco no inbox da pasta da guilda, como no primeiro desenho.

## 14. O 3D no site

`three` instalado como dependência **fixada**, carregado só no cliente (import dinâmico), só nas telas que mostram um
globo. **Fallback:** sem WebGL (ou falha ao carregar), a figura estática do globo (`components/snowglobe-art.tsx`: SVG
desenhado em código, por cena × raridade, sem arquivo de imagem nem script; também as miniaturas e o globo embrulhado). `prefers-reduced-motion`: sem neve nem balanço, o globo parado e girável. Nunca um globo na tela sem rótulo de
texto (cena, raridade, ano) para leitor de tela. A arte é toda em código: nenhum recurso da Blizzard.

## 15. Fora de escopo

- Cifra de verdade no repasse (precisaria de criptografia assimétrica no Lua).
- Gold, itens, correio, trade, necessidades do banco: **saíram**.
- O **kit de lançamento** (anfitrião no Discord/addon/site, textos fixos no código, oficial pode calar, cerimônia ao vivo):
  outra issue, na etapa seguinte.
- Modelo 3D com arte de referência (ChatGPT → Meshy/Tripo/Rodin → Blender): outro evento.
- Trocar ou vender globos entre contas: o globo é da conta e não sai dela.

## 16. Critérios de aceite

1. Um oficial abre o evento com as regras do §3; quem não é `mayConfigure` não abre nem muda nada (404).
2. Um membro entra com um personagem confirmado; o alt entra como o principal; uma segunda entrada do mesmo jogador é
   recusada.
3. O sorteio forma um ciclo; dois sorteios ao mesmo tempo gravam um só; antes de `joinUntil` ou com menos de 4 é recusado (com 3, num ciclo, quem eu tiro nunca é quem me tirou).
4. O doador embrulha (cena e bilhete) só entre `drawnAt` e `wrapUntil`, e só o doador do par; cena fora das cinco, ou bilhete
   inválido, é recusado inteiro.
5. A raridade nasce no servidor, uma vez, na abertura; as faixas e o capricho seguem o §7 (teste por faixa e por
   injeção do sorteio); duas aberturas ao mesmo tempo gravam uma.
6. O receptor só abre depois de `openAt` e só o próprio globo; antes, nem a cena aparece.
7. O membro vê só o próprio par; o oficial vê contagens; **nada mostra um par antes de abrir** (teste que varre telas,
   `GOSGILD1`, logs e o backoffice).
8. A reatribuição do §8 roda uma vez e só com voluntários elegíveis; sem embrulho até `wrapUntil` o receptor ganha o globo do
   anfitrião, com raridade sorteada como a dos outros e uma carta fixa (§6.1).
9. A Chaminé é a razão do §10 e vira o dobro de chances no §7; o ranking segue o §12 e não tem nome de membro (teste que
   varre a página).
10. `/c/<key>` mostra globo e ano a qualquer um e **nunca** bilhete nem doador; quem divide o Discord vê os dois; `optedOut`
    tira o globo da página pública.
11. `GOSGILD1.veil`, `GOSVEIL1` e `GOSCOMP1.veil` saem como no §13; o lacrado e o bilhete nunca saem no `GOSGILD1` (teste); um
    addon antigo ignora o campo novo.
12. As 20 imagens do addon e o fallback do site existem; o 3D carrega só no cliente e respeita `prefers-reduced-motion`.
13. Antes da abertura da chave, só os testadores veem as telas e recebem o evento, e o `GOSGILD1` não tem `veil` (teste);
    depois, todo mundo.
14. Copy nos nove idiomas; `pnpm test` e `pnpm typecheck` verdes, e `go test ./...` no companion.

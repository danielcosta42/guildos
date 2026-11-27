# Memória (auditoria de memória)

O mantenedor viu ~150 MB de memória do addon. A causa principal: listas que, a cada redesenho, criavam
frames novos para cada linha e só escondiam os antigos. O cliente nunca libera um frame, uma textura ou um
texto; a lista crescia a sessão inteira, e várias redesenhavam mesmo escondidas.

## A regra

- Uma tela que redesenha reaproveita o que desenhou: um pool por lista (criado sob demanda, reusado pela
  posição, o que sobra escondido) ou partes feitas uma vez e preenchidas de novo.
- Um formulário inteiro só é refeito quando muda de forma (`shapeOf` das Configurações) ou quando o que mostra
  mudou (a assinatura da aba Regra do Saque e das configurações do Core); senão só atualiza os valores.
- Todo gancho `uiRefresh` olha `IsVisible()` (não `IsShown()`, que é verdadeiro sob a janela fechada):
  escondida, a tela não desenha; o `OnShow` desenha o que chegou.
- Um redimensionamento desenha uma vez, quando o tamanho para (0,25 s), não a cada passo do arraste.

## Onde

Conselho de saque (o relógio de 1 s), Raides (sessões e presença), inscrição em cores, Trials, predefinições
de moderação, auditoria, aba Regra do Saque, configurações de pontos, Configurações (uma página por forma,
guardada), Calendário (o dia), ficha do membro (barra de talentos, atributos, ícones, barras), listas de
desejos da guilda, Resumo do login, Análise da guilda, Scanner de recrutamento e Cores.

## Passagem pelo roster

Sem tabela por membro a cada passagem: Chat Tweaks não faz nada desligado e reaproveita as entradas;
TrialTracker roda no máximo uma vez por minuto (como o histórico de membros; um ingresso ouvido no chat
libera a próxima na hora) com tabelas reaproveitadas; `readRoster` e `DropDeparted` reaproveitam as suas.

## Locales

`enUS.lua` continua sendo a lista mestra, mas em jogo só guarda as três entradas cujo inglês difere da
chave; o resto já cai na chave pelo `Locale.lua`. Uma entrada nova com valor diferente da chave vai lá em cima.

## Como ver

`/gos debug mem`: a memória antes e depois de uma coleta de lixo completa, os frames criados na sessão
(`GuildOS.framesMade`, contados por um `local CreateFrame` no topo de cada arquivo; o `CreateFrame` global
nunca é trocado) e o tamanho das maiores tabelas salvas. Um número de frames que sobe com a tela parada é
vazamento.

## O teste

`tools/frame-leaks.lua` abre cada entrada de cada sala, redesenha cada tela acima 25 vezes e dispara os
ganchos com a janela fechada: nenhum frame, textura ou texto novo depois do primeiro desenho.

## Dados salvos compactos (segunda passagem)

A segunda causa de memória eram os dados salvos, que o cliente carrega inteiros a cada login: numa guilda madura
de 1000 membros as receitas da Anniversary chegavam a 20–30 MB, o equipamento a ~12 MB e o histórico de membros
podia passar de 20 MB. Medido em Lua 5.1 (`compact.lua` no rascunho), guilda sintética de 1000 membros:

| O quê | Antes | Depois |
|---|---|---|
| Receitas (100 por membro, 100 mil) | 248 B/receita, 23,6 MB | 40 B/receita, 3,9 MB |
| Equipamento (18 slots) | 13,2 KB/membro, 12,6 MB | 2,3 KB/membro, 2,2 MB (itens repetidos na guilda: 0,8 KB, 0,7 MB) |
| Histórico de membros | teto de 4000 chaves: até 24,6 MB | teto de 1500: até 9,3 MB (típico 2,3 MB) |
| Receitas no Forever/retail (cópia de `db.professions`, não salva) | 248 B/receita em memória | nenhuma cópia |

### Receitas

- **Anniversary**: `db.recipeIds[chave][profissão] = { h = hash, spellId1, itemId1, spellId2, itemId2, …, nm = {…} }`,
  dois números por receita (0 onde o scan não tinha). `nm` guarda só os nomes que o jogo não devolve: todos os dos
  personagens da própria conta (a lista sai de novo pela rede por nome) e, dos outros, os de receita sem spellId.
  O nome de uma receita com spellId é o do cliente (`GetSpellInfo`), como a tela já mostrava.
- `h` é o hash que a rede calcula (nomes ordenados, `RecipeTracker.Hash`), guardado como chegou: o anúncio do
  remetente continua batendo e ninguém pede a lista de novo.
- **Forever e retail**: nenhuma cópia por membro. Os leitores leem `db.professions` pelo catálogo, e os índices
  item→artesãos e receita→artesãos são montados na primeira leitura (`Professions:CraftersOf`,
  `ProfDirectory.CraftersForItem`, `RecipeTracker:BuildItemCrafterIndex`) e descartados a cada mudança.
- **A API**: `RecipeTracker:RecipesOf(chave, profissão)` (iterador `i, spellId, itemId, nome`), `EachList()`,
  `ProfsOf(chave)`, `CountOf(chave, profissão)`, `Put(chave, profissão, lista)`. Painel de receitas, Busca, tooltips
  "Criado por", CraftFinder, CraftNet, Encomendas, diretório da aliança e o aviso de profissão leem por ela; nenhum
  lê `db.recipes`.
- **A rede não mudou**: `RC` e a resposta a `RA` levam o formato antigo (`{ name, itemId, spellId }`), que toda
  versão lê; o que chega no formato antigo (RC, ou o `recipes` de um broadcast de versão anterior à D3) é convertido
  na entrada (`Put`), com a regra do `MergeSpellIds` (nome sem ID ganha o spellId que o membro já tinha).

### Equipamento

- `linha.gc[slot] = "id:encantamento:gema1.gema2.gema3.gema4:sufixo:ilvl:qualidade\tnome[\tlink]"`: uma string por
  slot, o link só nas linhas do próprio cliente. O mesmo item com o mesmo encantamento e gemas é uma string só
  para a guilda inteira (o Lua internaliza strings).
- Ninguém lê a string: `GuildOS:MemberGear(linha)` devolve os slots no formato antigo (`{ link, id, name, quality,
  ilvl, enchantId, gems = { { id } }, suffix }`), decodificados na leitura do slot e não guardados (cache fraco).
  `pairs()` não funciona nessa visão: percorre-se `GuildOS.SlotIDs` ou `Gear.Slots`.
- O broadcast continua mandando o formato antigo; o que chega (de qualquer versão) vira `gc` em `StoreReceivedData`.

### Histórico de membros

- `MAX_KEYS` de 4000 para 1500. A regra fica: membro presente e membro com nota permanente nunca saem; saem
  primeiro os que saíram há mais tempo. Os passos e cargos continuam como tabelas com chave (compactá-los mexeria
  em toda a lógica de fusão, e o ganho com o teto já é o maior).

### Guildas desta conta

- `GuildOSDB` guarda um banco por guilda que um personagem da conta já abriu, todos carregados a cada login.
  Configurações › Dados e suporte lista "Dados de guilda nesta conta" (nome, tamanho estimado, última abertura)
  com Excluir por guilda, atrás da confirmação padrão, nunca a guilda em uso. `db._opened` é carimbado a cada login;
  um banco que esta versão nunca abriu ganha a data em que foi visto pela primeira vez (`_openedEst`: "antes de").
- O Resumo do login avisa uma vez por banco (`GuildOSDB._staleDbTold`) quando há bancos sem abrir há 90 dias, com
  o caminho até a tela. Nada é apagado sozinho.

### Migração

- Versionada em `db.schema` (`recipes = 2`, `gear = 1`, `history = 1`), rodada no `Initialize` de cada módulo.
  Receitas e equipamento são idempotentes e rodam a cada carga: só convertem o que está no formato antigo
  (`db.recipes`, `linha.gear`), que só uma versão anterior escreve. O histórico corta uma vez.
- Sem perda do que algum leitor usa: IDs, hash, nomes próprios e nomes sem spellId ficam; o nome de outro membro
  para uma receita com spellId vem do cliente (num idioma diferente do remetente aparece no idioma do leitor, como a
  tela já fazia). Os campos do item vão todos na string.
- **Backup**: o Backup (Configurações › Dados e suporte) exporta o banco inteiro; restaurar um backup de antes desta
  versão roda a migração na carga seguinte, porque `db.schema` vai junto.
- **Voltar para uma versão anterior**: os campos novos têm outro nome (`recipeIds`, `gc`), então a versão antiga não
  quebra: vê as receitas e o equipamento vazios até o próximo scan ou sync, e escreve de novo no formato antigo.
  Voltando para esta versão, o que ela escreveu é convertido na carga (ou na primeira leitura, no caso das receitas).
  O histórico cortado não volta.

### O teste

`tools/memory-compact.lua`: dados no formato antigo → formato novo → cada leitor responde o mesmo que a versão
anterior respondia (registrado rodando o `RecipeTracker.lua` anterior sobre o mesmo `db.recipes`); segunda rodada
não muda nada; lista no formato antigo vinda da rede é guardada compacta e não é pedida de novo; o broadcast do
equipamento sai igual; o teto do histórico; a lista de guildas e o aviso do Resumo. `/gos debug mem` mostra o
tamanho de cada armazenamento compacto, por linha, e quantas linhas ainda estão no formato antigo.

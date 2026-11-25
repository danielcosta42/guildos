# 121 · O kit de lançamento do Winter Veil (o Frimm vive o calendário)

Segue a spec 119 (§6.2, o anfitrião Frimm). Este é o papel dele fora das regras: o que cada canal diz, quando, e o clima
(neve) da interface. Escolhas do maintainer, 2026-11-25.

## 1. Calendário (fuso da guilda; padrões da 119 §3)

| Quando | Estado | Site | Addon | Discord |
|---|---|---|---|---|
| Hoje → 30/11 | teaser | mensagem pública com spoilers | neve num canto da janela + tooltip com o mesmo texto | nada |
| 1/12 | inscrições | banner + neve na interface toda | neve na interface toda | post "a oficina abriu" |
| 8/12 | sorteio | "veja seu par" | aviso uma vez | post "embaralhei" |
| 17/12 | reatribuição | aviso | aviso | post curto |
| 20/12 | embrulho fecha | Chaminé final | aviso | post "fechei, mandei os que faltavam" |
| 21–24/12 | espera | contagem regressiva | idem | nada |
| 25/12 0h | abertura | cerimônia | cerimônia | post do Frimm com o resultado da Chaminé |

Só os marcos acima viram post; sem lembretes semanais. O oficial pode silenciar o Frimm da guilda (recebe nada além do que o
site já mostra). A cerimônia é automática (post às 0h); um evento em voz continua sendo opção do oficial, fora do produto.

## 2. Teaser (antes de 1/12)

- Site: um cartão público (sem nomes de membros) com os textos do §5.1. Some quando a flag `winter-veil` abre para a pessoa.
- Addon: um pequeno painel de neve caindo no canto da janela principal; passar o mouse mostra a tooltip com o mesmo
  texto do site. Sem dados de guilda; só texto fixo e a data.
- O teaser é só um aceno (alguém está embrulhando algo); não conta o que é, as cenas, as raridades nem a data.
- Controle: nova flag `winter-veil-teaser` em `/admin/flags` (nunca env), aberta por padrão até 1/12 e depois substituída
  pelo estado do `winter-veil`.

## 3. Neve (a partir de 1/12, desabilitável)

- Site: neve leve em CSS (sem JS por flocos pesados), em toda a interface, **desligada** com `prefers-reduced-motion` ou
  quando a pessoa a desliga (preferência no navegador e no perfil). Nunca cobre cliques (`pointer-events: none`).
- Addon: flocos como texturas sobre a janela do GuildOS, atualizados por `OnUpdate` limitado (≤ 20 flocos, passo de 0,05 s),
  sem custo fora do painel aberto. Opção `snow` nas configurações do addon (liga/desliga), padrão ligada em dezembro.
- "Jogo" (fora da janela do addon) fica de fora: o addon não deve desenhar sobre a interface da Blizzard.

## 4. Mensagens do Frimm (regras)

Texto só, sem voz (119 §6.2). Curtas, no tom de um duende apressado, sem nome de membro nos canais públicos. Português
primeiro; os outros idiomas (`tools/locales.lua` no addon, catálogos do site) saem tradução do modelo, a revisar.

## 5. Textos (pt-BR)

### 5.1 Teaser
- Título: **Algo está sendo embrulhado na oficina…**
- Corpo: "Alguém está embrulhando algo para a guilda. Fique de olho. — Frimm"
- Tooltip do addon: o mesmo corpo.

### 5.2 Marcos
- 1/12: "A oficina abriu! Entre no Amigo Secreto da guilda e escolha o seu globo. Eu embrulho, vocês só precisam querer."
- 8/12: "Embaralhei os nomes. Mais ou menos. Confiem. Olhe o seu par no site ou no addon."
- 17/12: "Quem ainda não embrulhou perde o par para um voluntário. Não é castigo, é que a etiqueta vira outra."
- 20/12: "Fechei a oficina! Os globos que faltavam eu mesmo embrulhei (a letra está meio torta). A Chaminé ficou em {pct}%."
- 25/12: "Feliz Winter Veil! Sacudam o globo. A Chaminé fechou em {pct}%; e eu errei só um endereço, juro."

## 6. Fora de escopo
Arte do Frimm (imagem), voz, evento em voz, lembretes por DM.

## 7. Aceite
- O teaser aparece no site e no addon antes de 1/12, some (site) ou vira neve geral (addon) depois, sem ler dado de guilda.
- A neve respeita `prefers-reduced-motion` e a opção de desligar, e não bloqueia cliques.
- Discord: um post por marco, uma vez (idempotente), não sai se o oficial silenciou o Frimm.

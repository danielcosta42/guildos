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

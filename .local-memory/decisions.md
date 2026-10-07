# GuildOS — Decisões Arquiteturais (ADR)

_Last updated: 2026-04-26_

Registro de decisões arquiteturais. Consultar ANTES de introduzir novos padrões.
Adicionar um novo ADR quando introduzir um padrão arquitetural significativo.

Formato:
```
## YYYY-MM-DD — Título
### Contexto
### Decisão
### Motivo
### Impacto
```

---

## 2026-04-26 — Namespace único `GuildOS`
> ADR-0001

### Contexto
Addons WoW compartilham ambiente global. Colisões entre addons são um risco real.
TBC Classic não suporta sistemas de módulos modernos Lua.

### Decisão
Criar exatamente um global: `GuildOS`. Todos os módulos como sub-tabelas (`GuildOS.CommSystem`, etc.).
Apenas `Core.lua` cria o global. Todos os outros arquivos assumem que ele existe.

### Motivo
Um único global para auditar. Sem vazamento acidental de globais.

### Impacto
(+) Um global para auditar, sem vazamentos.
(+) Sub-módulos fazem alias local: `local RT = GuildOS.RaidTracker`.
(-) Módulos devem ser carregados em ordem correta. Aplicado via `.toc`.

---

## 2026-04-26 — Chave per-guild em SavedVariables
> ADR-0002

### Contexto
Uma instalação pode ser usada em múltiplas guilds. Misturar dados seria catastrófico.

### Decisão
`GuildOSDB` usa `"GuildName-Realm"` como chave top-level. `GuildOS.db` é o alias para a sub-tabela da guild atual.

### Motivo
Isolamento completo de dados por guild/realm.

### Impacto
(+) Sem contaminação entre guilds.
(-) Dados de guild antiga ficam em GuildOSDB até limpeza manual.

---

## 2026-04-26 — Camada de compatibilidade (`GuildOS.Compat`)
> ADR-0003

### Contexto
TBC Anniversary tem superfície de API diferente de Classic/Retail. `C_Timer`, `C_GuildInfo`, etc. podem não existir.

### Decisão
Todas as chamadas sensíveis à versão passam por `GuildOS.Compat`. Nenhum módulo testa `C_ChatInfo` diretamente.

### Motivo
Único ponto de atualização quando APIs mudam entre patches.

### Impacto
(+) Módulos de feature são agnósticos à versão.
(-) Indireção leve; overhead de performance negligenciável.

---

## 2026-04-26 — Protocolo de comm: LibSerialize + LibDeflate + ChatThrottleLib
> ADR-0004

### Contexto
Mensagens addon têm limite de 255 bytes. Dados de roster excedem isso facilmente.

### Decisão
Todas as mensagens: Serialize → Compress → Encode → Chunk (230 bytes) → ChatThrottleLib.
Recepção: reassembla chunks, desfaz o pipeline.

### Motivo
Único jeito de enviar payloads arbitrários de forma confiável sem disconnect.

### Impacto
(+) Suporta qualquer tamanho de payload com segurança.
(-) Mensagens pequenas passam pelo pipeline completo (overhead aceitável).

---

## 2026-04-26 — Estado de sessão em `GuildOS.State` (não em vars de módulo)
> ADR-0005

### Contexto
Dados runtime (não persistidos) misturados com métodos de módulo tornavam difícil saber o que é salvo.

### Decisão
Dados runtime ficam em `GuildOS.State.*`. Módulos têm apenas métodos e constantes.

### Motivo
Fronteira clara: `GuildOS.db.*` = persistido, `GuildOS.State.*` = runtime-only.

### Impacto
(+) Fácil de inspecionar/resetar estado de sessão.
(-) Caminho de acesso mais verboso: `GuildOS.State.lootMaster.activeLoot`.

---

## 2026-04-26 — Sem EventBus centralizado (por ora)
> ADR-0006

### Contexto
GuildOS tem frames de eventos espalhados por módulos. Um EventBus centralizado desacoplaria melhor.

### Decisão
Sem EventBus por enquanto. Cada módulo cria seu próprio frame em `Initialize()`. Revisar quando a contagem de módulos crescer.

### Motivo
Mais simples de raciocinar sobre escopo por módulo. Sem risco de handlers de um módulo afetarem outro.

### Impacto
(+) Escopo de evento por módulo é claro.
(-) Múltiplos frames registrados para o mesmo evento (overhead menor).
(-) Sem desacoplamento entre emissor e listener.

---

## 2026-04-26 — Config accessors (`GetSetting` / `SetSetting`)
> ADR-0007

### Contexto
Callbacks de UI liam/escreviam `GuildOS.db.settings.*` diretamente, acoplando UI ao schema interno.

### Decisão
Todas as leituras/escritas de settings passam por `GuildOS:GetSetting(key)` / `GuildOS:SetSetting(key, value)`.

### Motivo
Migrações de schema requerem apenas atualizar os accessors. UI não tem dependência de nomes de chave.

### Impacto
(+) Desacoplamento da UI do schema de SavedVariables.
(-) Overhead marginal (chamada de função vs acesso direto a tabela).

---

## 2026-04-26 — Factory de componentes UI em `UI/Helpers.lua`
> ADR-0008

### Contexto
Cada arquivo de painel criava frames independentemente, com lógica de backdrop e estilo duplicada.

### Decisão
`UI/Helpers.lua` é a fonte única de criação de componentes: `CreateButton`, `CreateText`, etc. e tabela de cores `C`.
Arquivos de painel usam essas factories e nunca inline backdrop/font logic.

### Motivo
Consistência visual aplicada no nível da factory. Tema centralizável.

### Impacto
(+) Consistência visual enforçada.
(-) `UI/Helpers.lua` atualmente mistura tema e factory (tech debt conhecido).

---

## 2026-04-26 — Lógica de negócio em módulos de dados, não em callbacks de UI
> ADR-0009

### Contexto
`RaidHUD.lua` tinha parsing de combat log inline em SetScript. `FeaturePanels.lua` tinha cálculo de score inline.

### Decisão
Toda lógica de negócio fica no módulo de dados dono do domínio. Callbacks de UI são delegações de uma linha.

### Motivo
Lógica reutilizável de múltiplos painéis. Módulos testáveis em isolamento.

### Impacto
(+) Lógica reutilizável e testável.
(-) Requer disciplina para não colocar lógica "por enquanto" nos callbacks.

---

## 2026-04-26 — Magic strings de sync não estão em MSG_TYPES
> ADR-0010 (PROBLEMA — não uma decisão intencional)

### Contexto
Ao analisar `CommSystem.lua`, foram encontrados tipos de mensagem ("WL", "LP", "ON", "RC", "TR") sendo tratados em `OnMessageReceived` mas NÃO declarados em `MSG_TYPES`. Isso significa que não há inventário completo dos tipos de mensagem do protocolo.

### Decisão (planejada — Fase 3)
Migrar todos os tipos para um enum centralizado em `SyncService.lua`. Eliminar magic strings espalhadas.

### Motivo
Sem um enum centralizado, é impossível auditar quais tipos de mensagem o addon envia e recebe. Adicionar um novo tipo de mensagem pode acidentalmente colidir com um existente que não está documentado.

### Impacto (atual)
(-) Impossível auditar protocolo de sync completamente sem ler todo o código.
(-) Risco de colisão de tipo de mensagem em futuras adições.
(-) Refactoring de protocolo requer busca de string em vez de renomeação de constante.

---

## 2026-04-26 — CommSystem usa `C_Timer.NewTicker` direto (não via Compat)
> ADR-0011 (VIOLAÇÃO de ADR-0003)

### Contexto
`CommSystem:Initialize()` usa `C_Timer.NewTicker(300, fn)` diretamente, sem passar por `GuildOS.Compat.NewTicker`. Isso viola ADR-0003.

### Decisão (planejada — Fase 3)
Substituir pela chamada via `GuildOS.Compat.NewTicker` ao refatorar CommSystem para SyncService.

### Motivo
Se `C_Timer.NewTicker` não existir em alguma versão do cliente, o ticker de sync silenciosamente não existirá sem logs de erro, pois o fallback está em Compat mas não está sendo usado.

### Impacto (atual)
(-) Inconsistência com a política de ADR-0003.
(-) Risco baixo no TBC Anniversary atual (API existe), mas pode causar problemas em futuros patches ou backports.

---

## 2026-04-26 — Sem versionamento de protocolo de sync (risco crítico)
> ADR-0012 (PROBLEMA — não uma decisão intencional)

### Contexto
`GuildOS.COMM_VERSION = 1` existe em `Core.lua`, mas não é incluído no envelope das mensagens de sync (pelo menos não em todas elas). Isso significa que mensagens de versões antigas do addon podem sobreescrever dados de versões novas.

### Decisão (planejada — Fase 3)
Envelope v2 inclui `protocolVersion`, `addonVersion`, e `rev` (revision counter). Receivers devem checar a versão e ignorar mensagens de protocolo incompatível.

### Motivo
Sem versionamento, uma atualização de addon que muda a estrutura de dados pode corromper o DB de membros que ainda estão na versão antiga (dados com formato novo sendo sobrescritos por dados no formato antigo).

### Impacto (atual)
(-) Risk of data corruption during addon version transitions in the guild.
(-) Sem mecanismo de negotiation entre versões diferentes.

# GuildOS — Coding Standards

_Last updated: 2026-04-26_

---

## Linguagem e Versão

- **Lua 5.1** (WoW TBC Classic)
- Sem `goto`, sem bitwise operators (`&`, `|`, `~`), sem `//` floor division
- Usar `math.floor(a/b)` em vez de `a//b`
- Aliases WoW disponíveis: `strsplit`, `strtrim`, `tinsert`, `tremove`, `wipe`, `format`, `floor`, `ceil`

---

## Namespace

```lua
-- CORRETO: tudo sob GuildOS
local ModuleName = {}
GuildOS.ModuleName = ModuleName

-- ERRADO: globais soltas
MyModule = {}
function GlobalFunction() end
```

- O único global criado pelo addon é `GuildOS`
- Todas as variáveis em file scope são `local`
- Dentro do arquivo, usar alias local: `local ModuleName = {}; GuildOS.ModuleName = ModuleName`

---

## Nomenclatura

| Elemento | Convenção | Exemplo |
|---|---|---|
| Módulos | PascalCase | `GuildOS.RaidTracker` |
| Métodos de módulo | `:PascalCase()` | `RaidTracker:GetSnapshotScore()` |
| Funções estáticas | `.PascalCase()` | `RaidTracker.GetWeekNum()` |
| Variáveis locais | camelCase | `local memberKey` |
| Constantes | UPPER_SNAKE | `local CHUNK_SIZE = 230` |
| Eventos WoW | UPPER_SNAKE | `"GUILD_ROSTER_UPDATE"` |
| Domínios de sync | snake_case | `"officerNotes"` |
| Chaves de player | `"Name-Realm"` | `"Arthax-Firetree"` |

---

## Estrutura de Arquivo

```lua
----------------------------------------------------------------------
-- GuildOS Guild Manager - NomeDoMódulo
-- Uma linha descrevendo a responsabilidade do módulo
----------------------------------------------------------------------
local ModuleName = {}
GuildOS.ModuleName = ModuleName

-- Constantes locais
local CONST_A = 10
local CONST_B = "string"

----------------------------------------------------------------------
-- Initialize
----------------------------------------------------------------------
function ModuleName:Initialize()
    -- DB defaults
    if not GuildOS.db.moduleDomain then
        GuildOS.db.moduleDomain = {}
    end
    -- Registro de eventos, se necessário
end

----------------------------------------------------------------------
-- Métodos públicos
----------------------------------------------------------------------
-- Descrição do que este método faz (Rule 14)
function ModuleName:PublicMethod(param)
    -- implementação
end

----------------------------------------------------------------------
-- Funções privadas
----------------------------------------------------------------------
local function privateHelper(x)
    return x
end
```

---

## Regras de Organização

### Rule 1 — Namespace único
Ver seção Namespace acima.

### Rule 2 — Módulo com responsabilidade única
Cada arquivo tem uma responsabilidade. Se está misturando duas coisas diferentes, separar.

### Rule 3 — One-Way Data Flow
```
Game Events → Handlers → Módulos de Dados → GuildOS.db / GuildOS.State → UI
```
UI nunca escreve no db. UI chama métodos de módulos.

### Rule 4 — Compatibility Layer
Toda chamada de API que pode não existir no TBC Anniversary passa por `GuildOS.Compat`:
```lua
-- CORRETO
GuildOS.Compat.After(1, fn)
GuildOS.Compat.IsQuestComplete(questId)

-- ERRADO
C_Timer.After(1, fn)          -- direto sem guard
C_QuestLog.IsQuestFlaggedCompleted(questId)  -- direto sem guard
```

### Rule 5 — Sem event frames órfãos
Event frames são criados dentro de `Initialize()`. Nunca em file scope.

### Rule 6 — State vs Storage
```lua
-- Session only → GuildOS.State
GuildOS.State.lootMaster.activeLoot = item

-- Persistente → GuildOS.db (via módulo dono)
GuildOS.LootTracker:RecordMLAward(item)
```

### Rule 7 — SavedVariables com defaults
```lua
GuildOS.db.field = GuildOS.db.field or {}
GuildOS.db.counter = GuildOS.db.counter or 0
```

### Rule 8 — Config Accessors
```lua
-- CORRETO
local val = GuildOS:GetSetting("showOffline")
GuildOS:SetSetting("showOffline", true)

-- ERRADO (em UI files)
GuildOS.db.settings.showOffline = true
```

### Rule 9 — Structured Logger
```lua
-- CORRETO
GuildOS.Logger.Debug("mensagem de debug")
GuildOS.Logger.Info("mensagem informativa")
GuildOS.Logger.Warn("aviso importante")

-- ERRADO
print("alguma coisa")                -- polui o chat
DEFAULT_CHAT_FRAME:AddMessage("...")  -- direto
```

### Rule 10 — UI/Logic Separation
```lua
-- CORRETO: callback é uma linha
Button:SetScript("OnClick", function()
    GuildOS.LootMaster:StartRoll()
end)

-- ERRADO: business logic inline
Button:SetScript("OnClick", function()
    -- 50 linhas de lógica aqui
end)
```

### Rule 11 — Performance
- Não varrer guild inteira em eventos frequentes
- `COMBAT_LOG_EVENT_UNFILTERED`: early return obrigatório
- Usar `C_Timer.After` em vez de `OnUpdate` para polling
- `wipe(table)` em vez de criar nova tabela em loops

### Rule 12 — UI Component Separation
- Cores sempre do `C` table — **nunca hardcode**
- Usar `UI:CreateButton()`, `UI:CreateText()`, etc.
- Sem backdrop logic inline — usar `UI:CreatePanel()`

### Rule 13 — Magic Numbers
```lua
-- ERRADO
C_Timer.After(0.1 * (i - 1), send)

-- CORRETO
local CHUNK_DELAY = 0.1  -- seconds between chunks to avoid rate limit
C_Timer.After(CHUNK_DELAY * (i - 1), send)
```

### Rule 14 — Comentários
- Toda função pública `GuildOS.*` tem uma linha de descrição acima
- Todo workaround de compatibilidade explica o POR QUÊ
- Todo magic number tem comentário inline

---

## Tratamento de Erros

```lua
-- Verificar nil ANTES de acessar sub-campos
local data = GuildOS.db and GuildOS.db.members and GuildOS.db.members[key]
if not data then return end

-- GetGuildRosterInfo: sempre nil-check
local name, rank = GetGuildRosterInfo(i)
if not name then break end

-- pcall para operações que podem falhar em contextos externos
local ok, result = pcall(function()
    return LibSerialize:Deserialize(data)
end)
if not ok then return end
```

---

## Padrões Específicos do WoW TBC

### Player Keys
```lua
-- Sempre com realm
local key = GuildOS:GetPlayerKey(name, realm)  -- retorna "Name-Realm"

-- Nunca usar só o nome curto como chave
-- ERRADO: GuildOS.db.members[name]
-- CORRETO: GuildOS.db.members[name .. "-" .. realm]
```

### itemId vs itemLink
```lua
-- Salvar sempre o itemId numérico como chave principal
-- itemLink pode mudar entre patches

-- Extrair itemId de um link:
local itemId = tonumber(link:match("item:(%d+)"))

-- Salvar ambos quando possível:
{ itemId = itemId, itemLink = link }  -- link para display, id para lógica
```

### GetGuildRosterInfo Loop
```lua
local n = GetNumGuildMembers()
for i = 1, n do
    local name, rank, rankIndex, level, class, zone,
          note, officerNote, online, status, classFileName = GetGuildRosterInfo(i)
    if not name then break end  -- nil-check obrigatório
    -- ...
end
```

### C_Timer Guards
```lua
-- SEMPRE via Compat
GuildOS.Compat.After(delay, fn)
GuildOS.Compat.NewTicker(interval, fn)

-- Guardar referência para cancelar
State.raid.snapshotTimer = GuildOS.Compat.NewTicker(300, fn)
-- Depois:
if State.raid.snapshotTimer then
    State.raid.snapshotTimer:Cancel()
    State.raid.snapshotTimer = nil
end
```

---

## Anti-Patterns

| Anti-pattern | Por que evitar |
|---|---|
| Global leakage | Conflito entre addons |
| Business logic em SetScript | Difícil de testar e manter |
| UI escrevendo GuildOS.db direto | Acopla UI ao schema |
| Magic strings de tipo de mensagem | Difícil de auditar e refatorar |
| Criar tabelas em loops de eventos frequentes | Garbage collection pressure |
| NewTicker sem referência para Cancel | Timer fantasma duplicado em reload |
| `SendChatMessage` diretamente em canais públicos | Requer hardware event — usa popup |
| Depender de GetLootMethod() | Retorna nil no TBC Anniversary |
| Salvar frames em SavedVariables | Crash imediato |
| Salvar itemLink como única chave | Pode mudar entre patches |

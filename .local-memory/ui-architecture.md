# BRutus — UI Architecture

_Last updated: 2026-09-14_

---

## Estrutura Atual da UI

```
UI/
├── Helpers.lua      ← Componentes do skin Forever: superfícies, texto, botões, abas e sub-abas, scroll
├── Layout.lua       ← Resolvedores puros: colunas, linhas, barras, escada de largura (ResolveBand), abas que cabem (FitTabs)
├── Window.lua       ← A janela única (#14, ADR-0016): título, régua de abas + »n, seletor, rodapé, alça; UI:OpenWindow / UI:ToggleMain
├── Agora.lua        ← Aba Agora: coluna viva (próxima raide, precisa de mim, atividade) e os dados dela, sem frames
├── Dashboard.lua    ← Cards da home ao lado da coluna da Agora (redesenho em #15)
├── RosterFrame.lua  ← Painel do roster, hub de raides e recrutamento
├── MemberDetail.lua ← Painel slide-in de detalhe do membro
├── FeaturePanels.lua← Raids, Loot, Trials, Settings, Wishlist, Recruitment panels
├── RecipesPanel.lua ← Browser de receitas com filtros por profissão
└── RaidHUD.lua      ← CD overlay flutuante + consumable check popup
```

---

## Hierarquia de Frames

```
UIParent
└── BRutus.RosterFrame (GuildOSWindow) — a janela única: 1000×620 por padrão, redimensionável até 320×28
      ├── titleBar (arrasta): wordmark · guilda e online · sync · — · ×   (na barra: online · raide · pendências)
      ├── rule: as abas que cabem + »n (menu); abaixo de 520px, o seletor de uma linha
      ├── content (recorta) → tabPanels[id], cada um construído na primeira abertura
      │     ├── tabPanels["home"]   ← Agora: coluna viva; cards da home ao lado a partir de 780px
      │     ├── tabPanels["roster"] ← KPI + trilho + tabela
      │     └── … uma por feature com aba (UI/Features.lua)
      ├── footer: buscar · sincronizar · convite · core sign-up · Blizzard (somem por prioridade)
      └── grip 16×16

UIParent
└── BRutusDetailFrame (slide-in)
      └── ScrollFrame → content
            ├── Spec/talent section
            ├── Gear section (17 slots)
            ├── Professions section
            ├── Stats section
            ├── Attunements section
            ├── Officer Notes section (officer only)
            └── Linked Characters section (officer only)

UIParent
└── BRutus.RaidHUD (floating, movable)
      └── Rows de cooldowns por player

UIParent
└── BRutus.ConsumablePopup
      └── Grid de results por player
```

---

## Helpers.lua — Tema e Factory

### C Table (cores)
```lua
-- Definido em UI/Helpers.lua (alias local C = BRutus.UI.Colors)
-- Mas as cores originais estão em BRutus.Colors em Core.lua
-- UI arquivos usam: local C = BRutus.UI.Colors
C.row1, C.row2, C.rowHover    -- cores de linha alternadas
C.accent                      -- cópia de C.gold (o único destaque)
C.gold                        -- dourado: wordmark, botão primário, regra da aba ativa
C.online, C.offline           -- status de jogador
C.red, C.green, C.blue        -- feedback
C.panel, C.panelDark          -- backgrounds
C.border, C.separator         -- bordas e separadores
```

### Factory Functions Disponíveis
```lua
UI:CreatePanel(parent, name, level)           -- frame com BackdropTemplate
UI:CreateDarkPanel(parent, name, level)       -- variante mais escura
UI:CreateAccentLine(parent, thickness)         -- linha horizontal de destaque
UI:CreateSeparator(parent)                     -- separador tênue
UI:CreateTitle(parent, text, size)             -- título de janela: Spectral 16, cor text (papel)
UI:CreateText(parent, text, size, r, g, b)    -- FontString padrão
UI:CreateHeaderText(parent, text, size)        -- texto de cabeçalho de coluna
UI:CreateButton(parent, text, width, height)  -- botão estilizado com hover
UI:CreateCheckbox(parent, labelText, size)    -- checkbox customizado
UI:CreateCloseButton(parent)                   -- botão × em label, papel no hover
UI:SkinScrollBar(scrollFrame, scrollName)     -- track 8px (well) + thumb lineHi (sem botões padrão)
UI:CreateScrollFrame(parent, name)            -- UIPanelScrollFrameTemplate skinned
UI:CreateIcon(parent, size, iconPath)         -- frame de ícone com borda
UI:SetIconQuality(iconFrame, quality)          -- borda por quality color
UI:CreateProgressBar(parent, width, height, ramp) -- barra com :SetProgress(v); dourada até completar, ok ao completar; ramp=true: ok ≥80% / dourado ≥60% / perigo
```

---

## Padrões Visuais

### Cores por Contexto
| Contexto | Usar |
|---|---|
| Fundo de janela | `C.bg` (card dentro dela: `C.panel`) |
| Fundo de sub-painel | `C.panelDark` |
| Linha par | `C.row1` |
| Linha ímpar | `C.row2` |
| Linha hover | `C.rowHover` |
| Título de janela / header de coluna | `C.text` / `C.label` |
| Player online | `C.online` |
| Player offline | `C.offline` |
| Destaque/botão ativo | `C.accent` |
| Aviso/erro | `C.red` |
| Sucesso | `C.green` |
| Info | `C.blue` |

### Tamanhos de Fonte
| Uso | Tamanho |
|---|---|
| Títulos de janela | 16 (Spectral) |
| Headers de coluna | 10 (IBM Plex Mono Medium) |
| Texto de linha | 11pt |
| Texto secundário | 10pt |
| Tooltips | 11pt |

### Botões
- Usar sempre `UI:CreateButton()` — nunca bare Frame + SetScript
- Tamanho padrão: width=120, height=26 (secundário; `UI:SetButtonVariant` troca para primary, ghost ou danger)
- Hover effect incluído na factory

---

## Scroll Lists (FauxScrollFrame)

### Virtual Scroll Pattern
```lua
local VISIBLE_ROWS = 20
local ROW_HEIGHT = 18

-- Criar rows uma vez
for i = 1, VISIBLE_ROWS do
    rows[i] = CreateRosterRow(parent, i)
end

-- Update por evento/refresh
local function UpdateRows()
    local offset = FauxScrollFrame_GetOffset(scrollFrame)
    local total = #filteredList
    FauxScrollFrame_Update(scrollFrame, total, VISIBLE_ROWS, ROW_HEIGHT)
    for i = 1, VISIBLE_ROWS do
        local idx = offset + i
        local row = rows[i]
        if idx <= total then
            row:Show()
            UpdateRosterRow(row, filteredList[idx], idx)
        else
            row:Hide()
        end
    end
end
```

**CRÍTICO**: Sempre resetar TODO o estado visual de cada row em `UpdateRosterRow`.
Nunca assumir que a row estava em algum estado anterior.

---

## Scroll Panels (Content Scroll)

Para painéis com conteúdo variável (não listas):
```lua
local scrollFrame, content = UI:CreateScrollFrame(parent, "PanelName")
-- content é o filho scrollável
-- Posicionar widgets em content com :SetPoint("TOPLEFT", content, ...)
-- Ajustar altura: content:SetHeight(totalHeight)
```

---

## Tooltips

```lua
-- Padrão obrigatório:
GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
GameTooltip:ClearLines()
GameTooltip:AddLine(title, r, g, b)
GameTooltip:AddLine(detail, 1, 1, 1, true)  -- true = wrap
GameTooltip:Show()

-- No OnLeave:
GameTooltip:Hide()
```

---

## Backdrop (TBC Anniversary)

Todo frame que precisa de visual de painel DEVE usar BackdropTemplate:
```lua
local f = CreateFrame("Frame", "FrameName", parent, "BackdropTemplate")
f:SetBackdrop({ bgFile = "...", edgeFile = "...", edgeSize = 1, ... })
f:SetBackdropColor(r, g, b, a)
f:SetBackdropBorderColor(r, g, b, a)
```

Usar `UI:CreatePanel()` ou `UI:CreateDarkPanel()` em vez de replicar isso inline.

---

## Violações Atuais de UI Architecture

### ⚠️ Business logic inline em SetScript (parcialmente resolvido)
- `UI/RaidHUD.lua` → `HandleCombatLogCD` foi extraído ✅
- `UI/FeaturePanels.lua` → score calc movido para `RaidTracker:GetSnapshotScore` ✅
- `UI/FeaturePanels.lua` → alguns callbacks ainda têm lógica inline

### ⚠️ UI escrevendo BRutus.db diretamente
- `UI/MemberDetail.lua` → `BRutus.db.altLinks[altKey] = mainKey` (deveria chamar `BRutus:LinkAlt`)
- `UI/FeaturePanels.lua` → alguns campos de `recruitment` escritos inline

### ⚠️ Helpers.lua tem 3 responsabilidades
- Tema/cores → target: `UI/Theme.lua`
- Factory functions → target: `UI/Core.lua`
- Shim → `UI/Helpers.lua` (manter para backward compat)

---

## Target UI Split

```
UI/Theme.lua   ← C table, score color helpers, size constants — SEM frames
UI/Core.lua    ← CreateButton, CreateText, CreateHeaderText, CreateCloseButton,
                  SkinScrollBar, _ApplyBackdrop, backdrop probe
UI/Helpers.lua ← (thin shim) re-exports Theme + Core para backward compat
UI/Panels.lua  ← compound builders: tabs, section headers, filter rows
```

Até o split ser feito: NUNCA hardcode cores, SEMPRE usar `C.xxx`.

# BRutus — Agent Memory

> **DIRETIVA PRINCIPAL**: Antes de qualquer tarefa que toque `.lua`, leia os arquivos nesta pasta.
> Eles contêm o mapa completo do projeto, regras de código, decisões de arquitetura e o catálogo de funções.
> Codificar sem ler primeiro resultará em duplicação, violação de padrões e warnings no luacheck.

Esta pasta **não é enviada ao CurseForge** (está no `.gitignore`). É visível apenas localmente no VS Code.
O conteúdo espelha os arquivos em `/memories/repo/` do sistema interno do Copilot.

---

## Índice de Arquivos

| Arquivo | Conteúdo | Quando ler |
|---|---|---|
| [architecture.md](architecture.md) | Mapa de módulos, ordem de carga, pipelines de dados, State, Config, schema do SavedVariables, protocolo de comm | Sempre — antes de qualquer tarefa |
| [functions-catalog.md](functions-catalog.md) | Catálogo completo de todas as funções públicas existentes | Sempre — antes de criar qualquer função |
| [lua-best-practices.md](lua-best-practices.md) | 14 regras de engenharia (namespace, one-way flow, Compat, State, Config, UI, performance, magic numbers) | Sempre — antes de qualquer tarefa |
| [dev-workflow.md](dev-workflow.md) | Fluxo READ→CREATE→WRITE, luacheck, templates de módulo, convenções de UI, padrões de acesso ao DB | Sempre — antes de qualquer tarefa |
| [quality-checklist.md](quality-checklist.md) | 40-item checklist de pré-merge (namespace, compat, arquitetura, state, config, UI, performance, correctness, luacheck) | Antes de `task_complete` |
| [decisions.md](decisions.md) | ADRs (Architectural Decision Records) — por que o código está estruturado assim | Ao introduzir novos padrões arquiteturais |

---

## Fluxo Obrigatório do Agente

```
PHASE 1 — READ
  ├── architecture.md        (mapa de módulos, data flow, load order)
  ├── functions-catalog.md   (verificar se a função já existe)
  ├── lua-best-practices.md  (14 regras)
  ├── dev-workflow.md        (workflow, templates, pitfalls)
  └── quality-checklist.md   (saber o que verificar no final)

PHASE 2 — CREATE (planejar)
  ├── Identificar módulo dono da lógica (Module Map em architecture.md)
  ├── Confirmar one-way data flow: Game Events → Modules → State/DB → UI
  ├── Confirmar zero business logic em UI callbacks
  └── Verificar novos globals WoW que precisam entrar no .luacheckrc

PHASE 3 — WRITE (implementar e validar)
  ├── Implementar com scoping local
  ├── Rodar luacheck: C:\Users\danie\bin\luacheck.exe . --config .luacheckrc
  ├── Corrigir TODOS os warnings — 0 warnings / 0 errors obrigatório
  ├── Rodar quality-checklist.md antes de task_complete
  ├── Atualizar functions-catalog.md se novas funções públicas foram adicionadas
  └── Atualizar decisions.md se novo padrão arquitetural foi introduzido
```

---

## Quick Reference

| Tópico | Detalhe |
|---|---|
| Global único | `BRutus` — todos os módulos como sub-tabelas |
| State (runtime) | `BRutus.State.*` — nunca persiste |
| Storage (persistente) | `BRutus.db.*` — via `BRutusDB[guildKey]` |
| Configurações | `BRutus:GetSetting(key)` / `BRutus:SetSetting(key, value)` |
| Compatibilidade | `BRutus.Compat.*` — nunca chamar `C_ChatInfo`, `C_Timer` etc. diretamente |
| Logger | `BRutus.Logger.Debug/Info/Warn` — sem `print()` direto |
| luacheck | `C:\Users\danie\bin\luacheck.exe . --config .luacheckrc` |
| Commit format | Conventional Commits: `feat:`, `fix:`, `refactor:`, `chore:`, etc. |
| CurseForge | Projeto ID 1549177, BCC client |

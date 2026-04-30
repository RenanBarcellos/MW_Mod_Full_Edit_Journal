# Fase 7 — Análise e correção definitiva da seleção

## Diagnóstico

### Problema 1 — Seleção limitada às páginas 1 e 2

**Causa raiz**: `moveSelection` em `input.lua` usa `buildVisibleEntryList(blocks)`, que só
contém as entries do spread visível atual. Ao chegar na última entry visível não há mais para
onde navegar, mesmo que existam dezenas de outras entries em outros spreads.

### Problema 2 — Entry cortada entre páginas causa highlight errado e cascata de bugs

**Causa raiz**: O modelo atual injeta dividers no DOM (`createDivider` + `reorderChildren`)
ao redor de **um único nó de texto** (`anchor`). Quando uma entry é longa e o MenuBook a
quebra entre páginas 1 e 2, o `findAnchorInElement` encontra um fragmento do texto no meio
da entry e insere os dividers ali — criando o espaço em branco visível na imagem. Toda a
navegação posterior fica comprometida porque os blocos derivados do texto visível não
correspondem mais às posições visuais reais.

O mesmo problema ocorrerá de forma pior quando uma entry estiver inteiramente em spreads
não exibidos ao mesmo tempo (por exemplo, início na página 2 e fim na 3).

---

## Design definitivo

### Princípio geral

> **Separar completamente a lógica de navegação da lógica de destaque visual.**

| Aspecto | Abordagem anterior (quebrada) | Abordagem nova (definitiva) |
|---------|------------------------------|-----------------------------|
| Lista de navegação | Só entries do spread atual | **Todas** as entries em ordem de renderização |
| Highlight | Dividers injetados ao redor de um nó de texto | Mudança de `color` nos nós de texto que pertencem à entry |
| Âncora de highlight | Apenas um nó — falha se for fragmento | Todos os nós correspondentes, em ambas as páginas |
| Rebuild no keypress | Não | Não (mudança de cor é no-rebuild) |

### Solução para Problema 1 — Navegação pelo full-list

Adicionar `M.getOrderedEntryIds()` em `data.lua` (mesma ordenação do render) e usá-la em
`book.lua` para construir um bloco de navegação que passa por *todas* as entries. A
resolução de spread (para limpar seleção ao virar página) continua usando os blocos reais.

### Solução para Problema 2 — Color-based highlight

Ao invés de injetar dividers, percorrer a árvore de UI nas duas páginas do spread, encontrar
**todos** os nós de texto que pertencem à entry selecionada, e alterar a propriedade `color`
deles para uma cor de destaque. Ao limpar a seleção, restaurar as cores originais.

**Vantagens:**
- Funciona naturalmente para entries que cruzam a quebra de página
- Sem alteração de DOM (sem `createDivider`, sem `reorderChildren`)
- Sem espaços em branco fantasmas
- Simples de limpar (basta restaurar `color`)

---

## Mudanças de código

### 1. `data.lua` — adicionar `getOrderedEntryIds()`

Adicionar ao final do módulo (antes de `return M`):

```lua
function M.getOrderedEntryIds()
    local loadedState = requireLoadedState()
    local list = {}

    for _, entry in pairs(loadedState.entries or {}) do
        if type(entry) == "table" and entry.deleted ~= true then
            list[#list + 1] = entry
        end
    end

    table.sort(list, function(left, right)
        local leftDays = type(left.daysPassed) == "number" and left.daysPassed or math.huge
        local rightDays = type(right.daysPassed) == "number" and right.daysPassed or math.huge
        if leftDays ~= rightDays then
            return leftDays < rightDays
        end

        local leftSource = tostring(left.source or "")
        local rightSource = tostring(right.source or "")
        if leftSource ~= rightSource then
            return leftSource < rightSource
        end

        local leftQuestId = tostring(left.questId or left.displayDate or "")
        local rightQuestId = tostring(right.questId or right.displayDate or "")
        if leftQuestId ~= rightQuestId then
            return leftQuestId < rightQuestId
        end

        local leftQuestIndex = type(left.questIndex) == "number" and left.questIndex or math.huge
        local rightQuestIndex = type(right.questIndex) == "number" and right.questIndex or math.huge
        if leftQuestIndex ~= rightQuestIndex then
            return leftQuestIndex < rightQuestIndex
        end

        return tostring(left.id or "") < tostring(right.id or "")
    end)

    local ids = {}
    for _, entry in ipairs(list) do
        ids[#ids + 1] = entry.id
    end

    return ids
end
```

---

### 2. `book.lua` — substituir dividers por color-based highlight + full-list navigation

#### 2a. Remover constantes de divider e adicionar `coloredElements`

Substituir:
```lua
local SELECTION_DIVIDER_TOP_ID = tes3ui.registerID("journal_custom_selectionDividerTop")
local SELECTION_DIVIDER_BOTTOM_ID = tes3ui.registerID("journal_custom_selectionDividerBottom")
```

Por:
```lua
local coloredElements = {}
```

#### 2b. Substituir `clearSelectionHighlight`

Substituir a função inteira por:
```lua
local function clearSelectionHighlight(menu)
    local hadEntries = #coloredElements > 0

    for _, item in ipairs(coloredElements) do
        if item.element then
            pcall(function()
                item.element.color = item.originalColor
            end)
        end
    end

    coloredElements = {}

    if menu and hadEntries then
        menu:updateLayout()
    end

    return hadEntries
end
```

#### 2c. Remover `findAnchorInElement` e `findSelectionAnchor` inteiramente

Essas duas funções não são mais necessárias.

#### 2d. Substituir `updateSelectionHighlight`

Substituir a função inteira por:
```lua
local function updateSelectionHighlight(menu)
    clearSelectionHighlight(menu)

    if not menu then
        return false
    end

    local selectedEntryId = lastContext.selectedEntryId or data.getState().selectedEntryId
    if not isSelectionEnabled() or not selectedEntryId then
        return false
    end

    local entry = data.getEntry(selectedEntryId)
    if not entry then
        return false
    end

    local bodyText = buildAnchorBodyText(entry)
    local bodySegments = buildAnchorSegments(bodyText)
    if #bodySegments == 0 and bodyText == "" then
        return false
    end

    local accentColor = tes3ui.getPalette("journal_topic_color") or { 0.40, 0.20, 0.05 }
    local found = false

    local function colorMatchingNodes(pageElement)
        if not pageElement then
            return
        end

        local function visit(node)
            if not node or node.visible == false then
                return
            end

            if type(node.text) == "string" then
                local normalizedText = normalizeUiText(node.text)

                if normalizedText ~= "" then
                    local matched = false

                    if bodyText ~= "" then
                        if normalizedText:find(bodyText, 1, true) then
                            matched = true
                        elseif #normalizedText >= BODY_SEGMENT_MIN_LENGTH and bodyText:find(normalizedText, 1, true) then
                            matched = true
                        end
                    end

                    if not matched then
                        for _, seg in ipairs(bodySegments) do
                            if normalizedText:find(seg, 1, true) then
                                matched = true
                                break
                            elseif #normalizedText >= BODY_SEGMENT_MIN_LENGTH and seg:find(normalizedText, 1, true) then
                                matched = true
                                break
                            end
                        end
                    end

                    if matched then
                        local originalColor = node.color
                        node.color = accentColor
                        coloredElements[#coloredElements + 1] = {
                            element = node,
                            originalColor = originalColor,
                        }
                        found = true
                    end
                end
            end

            for _, child in ipairs(node.children or {}) do
                visit(child)
            end
        end

        visit(pageElement)
    end

    colorMatchingNodes(getPageElement(menu, "left"))
    colorMatchingNodes(getPageElement(menu, "right"))

    if found then
        menu:updateLayout()
    end

    return found
end
```

#### 2e. Adicionar `buildFullNavigationBlocks()` antes de `configureMenuBook`

```lua
local function buildFullNavigationBlocks()
    local allIds = data.getOrderedEntryIds()
    local fakeBlocks = {}

    for _, id in ipairs(allIds) do
        fakeBlocks[#fakeBlocks + 1] = { entryId = id }
    end

    fakeBlocks.spreadStart = (activeVisibleBlocks and type(activeVisibleBlocks.spreadStart) == "number")
        and activeVisibleBlocks.spreadStart
        or 1

    return fakeBlocks
end
```

#### 2f. Atualizar handlers de teclado para usar `buildFullNavigationBlocks()`

Dentro de `configureMenuBook`, no handler de `keyPress`:
```lua
-- ANTES:
local nextEntryId, handled = input.onKeyPress(e, activeVisibleBlocks, selectedEntryId)

-- DEPOIS:
local nextEntryId, handled = input.onKeyPress(e, buildFullNavigationBlocks(), selectedEntryId)
```

Dentro de `ensureMenuBookHooks`, nos dois handlers de `keyDown`:
```lua
-- ANTES (em ambos):
local nextEntryId, handled = input.onKeyDown(e, activeVisibleBlocks, selectedEntryId)

-- DEPOIS (em ambos):
local nextEntryId, handled = input.onKeyDown(e, buildFullNavigationBlocks(), selectedEntryId)
```

#### 2g. Limpar `coloredElements` no destroy do menu

No início de `handleMenuBookDestroyed`:
```lua
local function handleMenuBookDestroyed(menu)
    coloredElements = {}   -- <-- adicionar esta linha
    timer.frame.delayOneFrame(function()
        ...
```

---

## Por que isso resolve o caso de spreads não exibidos ao mesmo tempo

Quando a entry selecionada está em um spread diferente do atual:
- A navegação continua funcionando (usa a lista completa)
- O `updateSelectionHighlight` não encontra nenhum nó correspondente nas duas páginas atuais — simplesmente não colore nada, sem crash, sem blank space
- Quando o usuário virar a página até o spread que contém a entry, o `scheduleVisibleBlockCollection` dispara, que por sua vez chama `updateSelectionHighlight` no novo spread — e os nós corretos são coloridos

Isso é robusto por design: a ausência de correspondência visual é silent, não um bug.

---

## O que não muda

- `mapping.lua` — inalterado (coleta blocos para spread tracking)
- `input.lua` — inalterado (a lista de navegação é construída em `book.lua`)
- `render.lua` — inalterado (HTML sem divider, sem marcador inline)
- `data.lua` — apenas recebe a nova função `getOrderedEntryIds()`
- Lógica de `resolveSelection` e limpeza ao trocar spread — inalteradas

# Phase 7 — Selection analysis and definitive fix

## Diagnosis

### Problem 1 — Selection limited to pages 1 and 2

**Root cause**: `moveSelection` in `input.lua` uses `buildVisibleEntryList(blocks)`, which only
contains entries from the current visible spread. When reaching the last visible entry there is nowhere
else to navigate, even though there may be dozens of other entries in other spreads.

### Problem 2 — Entry cut across pages causes wrong highlight and cascade of bugs

**Root cause**: The current model injects dividers into the DOM (`createDivider` + `reorderChildren`)
around a **single text node** (`anchor`). When a long entry is split by MenuBook across pages 1 and 2, the
`findAnchorInElement` finds a fragment of text in the middle of the entry and inserts the dividers there —
creating the visible white space in the image. All subsequent navigation is compromised because the blocks
derived from visible text no longer correspond to actual visual positions.

The same problem will occur even worse when an entry spans entirely across non-simultaneously displayed spreads
(for example, beginning on page 2 and ending on page 3).

---

## Definitive Design

### General Principle

> **Completely separate navigation logic from visual highlight logic.**

| Aspect | Previous approach (broken) | New approach (definitive) |
|---------|------------------------------|-----------------------------|
| Navigation list | Only entries from current spread | **All** entries in render order |
| Highlight | Dividers injected around a text node | `color` change in text nodes belonging to the entry |
| Highlight anchor | Only one node — fails if fragment | All corresponding nodes, on both pages |
| Rebuild on keypress | No | No (color change is no-rebuild) |

### Solution for Problem 1 — Navigation by full-list

Add `M.getOrderedEntryIds()` in `data.lua` (same ordering as render) and use it in
`book.lua` to build a navigation block that goes through *all* entries. The spread resolution
(to clear selection when turning page) continues using real blocks.

### Solution for Problem 2 — Color-based highlight

Instead of injecting dividers, traverse the UI tree on both pages of the spread, find
**all** text nodes that belong to the selected entry, and change their `color` property
to a highlight color. When clearing selection, restore original colors.

**Advantages:**
- Works naturally for entries that cross page breaks
- No DOM alteration (no `createDivider`, no `reorderChildren`)
- No phantom white spaces
- Simple to clean up (just restore `color`)

---

## Code Changes

### 1. `data.lua` — add `getOrderedEntryIds()`

Add at the end of the module (before `return M`):

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

### 2. `book.lua` — replace dividers with color-based highlight + full-list navigation

#### 2a. Remove divider constants and add `coloredElements`

Replace:
```lua
local SELECTION_DIVIDER_TOP_ID = tes3ui.registerID("journal_custom_selectionDividerTop")
local SELECTION_DIVIDER_BOTTOM_ID = tes3ui.registerID("journal_custom_selectionDividerBottom")
```

With:
```lua
local coloredElements = {}
```

#### 2b. Replace `clearSelectionHighlight`

Replace the entire function with:
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

#### 2c. Remove `findAnchorInElement` and `findSelectionAnchor` entirely

These two functions are no longer needed.

#### 2d. Replace `updateSelectionHighlight`

Replace the entire function with:
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

#### 2e. Add `buildFullNavigationBlocks()` before `configureMenuBook`

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

#### 2f. Update keyboard handlers to use `buildFullNavigationBlocks()`

Inside `configureMenuBook`, in the `keyPress` handler:
```lua
-- BEFORE:
local nextEntryId, handled = input.onKeyPress(e, activeVisibleBlocks, selectedEntryId)

-- AFTER:
local nextEntryId, handled = input.onKeyPress(e, buildFullNavigationBlocks(), selectedEntryId)
```

Inside `ensureMenuBookHooks`, in both `keyDown` handlers:
```lua
-- BEFORE (in both):
local nextEntryId, handled = input.onKeyDown(e, activeVisibleBlocks, selectedEntryId)

-- AFTER (in both):
local nextEntryId, handled = input.onKeyDown(e, buildFullNavigationBlocks(), selectedEntryId)
```

#### 2g. Clean up `coloredElements` on menu destroy

At the beginning of `handleMenuBookDestroyed`:
```lua
local function handleMenuBookDestroyed(menu)
    coloredElements = {}   -- <-- add this line
    timer.frame.delayOneFrame(function()
        ...
```

---

## Why this resolves the case of spreads not displayed at the same time

When the selected entry is in a different spread than the current one:
- Navigation continues working (uses the complete list)
- `updateSelectionHighlight` finds no corresponding nodes on the two current pages — simply doesn't color anything, no crash, no blank space
- When the user turns the page to the spread containing the entry, `scheduleVisibleBlockCollection` fires, which in turn calls `updateSelectionHighlight` on the new spread — and the correct nodes are colored

This is robust by design: the absence of visual correspondence is silent, not a bug.

---

## What doesn't change

- `mapping.lua` — unchanged (collects blocks for spread tracking)
- `input.lua` — unchanged (navigation list is built in `book.lua`)
- `render.lua` — unchanged (HTML without divider, without inline marker)
- `data.lua` — only receives the new `getOrderedEntryIds()` function
- `resolveSelection` logic and cleanup when switching spread — unchanged

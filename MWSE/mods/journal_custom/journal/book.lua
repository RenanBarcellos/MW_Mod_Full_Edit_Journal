local config = require("journal_custom.config")
local data = require("journal_custom.journal.data")
local input = require("journal_custom.journal.input")
local journalDate = require("journal_custom.util.date")
local logger = require("journal_custom.util.logger")
local mapping = require("journal_custom.journal.mapping")
local render = require("journal_custom.journal.render")
local text = require("journal_custom.util.text")

local M = {}
local SELECTED_ENTRY_UI_COLOR = {
    0x6F / 255,
    0x2C / 255,
    0x12 / 255,
}
local MIN_HIGHLIGHT_FRAGMENT_LENGTH = 18
local PAGE_ELEMENT_IDS = {
    left = "MenuBook_page_1",
    right = "MenuBook_page_2",
}
local HELP_BUTTON_ID = tes3ui.registerID("journal_custom:help_button")
local HELP_MENU_ID = tes3ui.registerID("journal_custom:help_menu")
local HELP_CLOSE_BUTTON_ID = tes3ui.registerID("journal_custom:help_close")

local coloredElements = {}

local lastContext = {
    selectedEntryId = nil,
    selectedSpreadStart = nil,
    viewMode = "diary",
}

local suppressedDestroyMenu
local activeBookHtml
local activeVisibleBlocks = {}
local customBookSessionActive = false
local menuBookHooksRegistered = false
local mappingUpdateScheduled = false
local spreadRestoreInProgress = false
local renderSoundSuppression = {
    active = false,
    framesRemaining = 0,
    remaining = 0,
    reason = nil,
    token = 0,
}
local beginEditForSelection
local beginCreateDate
local beginCreateNote
local scheduleVisibleBlockCollection

local function isSelectionEnabled()
    local currentConfig = config.get()
    local featureFlags = currentConfig.featureFlags or {}
    return featureFlags.enableSelection == true
end

local function pickNeighborEntryId(entryIds, currentEntryId)
    for index, entryId in ipairs(entryIds or {}) do
        if entryId == currentEntryId then
            return entryIds[index + 1] or entryIds[index - 1]
        end
    end

    return entryIds and entryIds[1] or nil
end

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

local function clearRenderSoundSuppression(expectedToken)
    if expectedToken ~= nil and renderSoundSuppression.token ~= expectedToken then
        return
    end

    renderSoundSuppression.active = false
    renderSoundSuppression.framesRemaining = 0
    renderSoundSuppression.remaining = 0
    renderSoundSuppression.reason = nil
end

local function armRenderSoundSuppression(reason)
    renderSoundSuppression.token = renderSoundSuppression.token + 1
    renderSoundSuppression.active = true
    renderSoundSuppression.framesRemaining = 8
    renderSoundSuppression.remaining = 2
    renderSoundSuppression.reason = reason or "render"

    local token = renderSoundSuppression.token
    local function tickSuppressionWindow()
        if renderSoundSuppression.token ~= token or not renderSoundSuppression.active then
            return
        end

        renderSoundSuppression.framesRemaining = renderSoundSuppression.framesRemaining - 1
        if renderSoundSuppression.framesRemaining <= 0 then
            clearRenderSoundSuppression(token)
            return
        end

        timer.frame.delayOneFrame(tickSuppressionWindow)
    end

    timer.frame.delayOneFrame(tickSuppressionWindow)
end

local function updateSelectionHighlight(menu)
    local resolvedMenu = menu or tes3ui.findMenu("MenuBook")
    clearSelectionHighlight(resolvedMenu)

    local selectedEntryId = lastContext.selectedEntryId or data.getState().selectedEntryId
    if not resolvedMenu or not selectedEntryId then
        return false
    end

    local entry = data.getEntry(selectedEntryId)
    if not entry or entry.deleted == true then
        return false
    end

    local bodyText = text.normalizeWhitespace(text.stripBookHtml(render.buildEntryBody(entry))):gsub("%-+", " ")
    if bodyText == "" then
        return false
    end

    local visiblePageSides = {}
    for _, block in ipairs(activeVisibleBlocks or {}) do
        if block.entryId == selectedEntryId and block.pageSide then
            visiblePageSides[block.pageSide] = true
        end
    end

    if not next(visiblePageSides) then
        return false
    end

    local function collectTextElements(element, target)
        if not element or element.visible == false then
            return target
        end

        local elementText = element.text
        if type(elementText) == "string" then
            local normalizedText = text.normalizeWhitespace(text.stripBookHtml(elementText)):gsub("%-+", " ")
            if normalizedText ~= "" then
                target[#target + 1] = {
                    element = element,
                    text = normalizedText,
                }
            end
        end

        for _, child in ipairs(element.children or {}) do
            collectTextElements(child, target)
        end

        return target
    end

    local changed = false
    for pageSide in pairs(visiblePageSides) do
        local pageElementId = PAGE_ELEMENT_IDS[pageSide]
        local pageElement = resolvedMenu:findChild(tes3ui.registerID(pageElementId)) or resolvedMenu:findChild(pageElementId)

        local items = collectTextElements(pageElement, {})

        local function joinedText(lo, hi)
            local parts = {}
            for k = lo, hi do
                parts[#parts + 1] = items[k].text
            end
            local joined = table.concat(parts, " ")
            joined = joined:gsub("%s+", " ")
            joined = joined:gsub("^%s+", ""):gsub("%s+$", "")
            return joined
        end

        local matched = {}

        if #bodyText < MIN_HIGHLIGHT_FRAGMENT_LENGTH then
            for index, item in ipairs(items) do
                if item.text == bodyText or item.text:find(bodyText, 1, true) or bodyText:find(item.text, 1, true) then
                    matched[index] = true
                end
            end
        else
            for index, item in ipairs(items) do
                if #item.text >= MIN_HIGHLIGHT_FRAGMENT_LENGTH and bodyText:find(item.text, 1, true) then
                    matched[index] = true
                end
            end

            for index in pairs(matched) do
                local lo = index
                while lo > 1 and not matched[lo - 1] do
                    if bodyText:find(joinedText(lo - 1, index), 1, true) then
                        lo = lo - 1
                    else
                        break
                    end
                end

                local hi = index
                while hi < #items and not matched[hi + 1] do
                    if bodyText:find(joinedText(lo, hi + 1), 1, true) then
                        hi = hi + 1
                    else
                        break
                    end
                end

                for k = lo, hi do
                    matched[k] = true
                end
            end
        end

        for index, item in ipairs(items) do
            if matched[index] then
                coloredElements[#coloredElements + 1] = {
                    element = item.element,
                    originalColor = item.element.color,
                }
                item.element.color = SELECTED_ENTRY_UI_COLOR
                changed = true
            end
        end
    end

    if changed then
        resolvedMenu:updateLayout()
    end

    return changed
end

local function resetSelectionState()
    local state = data.getState()
    if state.selectedEntryId == nil and lastContext.selectedEntryId == nil and lastContext.selectedSpreadStart == nil then
        return false
    end

    lastContext.selectedEntryId = nil
    lastContext.selectedSpreadStart = nil
    data.setSelectedEntry(nil)
    data.save()
    logger.debug("journal_custom selection cleared (open).")
    return true
end

local function getCurrentSpreadStart(menu)
    local liveSpreadStart = mapping.getCurrentSpreadStart(menu or tes3ui.findMenu("MenuBook"))
    if type(liveSpreadStart) == "number" then
        return liveSpreadStart
    end

    if activeVisibleBlocks and type(activeVisibleBlocks.spreadStart) == "number" then
        return activeVisibleBlocks.spreadStart
    end

    return nil
end

local function findBookPageButton(menu, direction)
    local buttonId = direction > 0 and "MenuBook_button_next" or "MenuBook_button_prev"
    return menu and (menu:findChild(tes3ui.registerID(buttonId)) or menu:findChild(buttonId))
end

local function schedulePageTurnSync(previousSpreadStart, reason)
    local resolvedReason = reason or "pageTurn"
    scheduleVisibleBlockCollection(resolvedReason)

    timer.frame.delayOneFrame(function()
        if not customBookSessionActive or spreadRestoreInProgress then
            return
        end

        local menu = tes3ui.findMenu("MenuBook")
        if not menu then
            return
        end

        if type(previousSpreadStart) ~= "number" then
            scheduleVisibleBlockCollection(resolvedReason .. ":retry")
            return
        end

        local currentSpreadStart = getCurrentSpreadStart(menu)
        if currentSpreadStart == previousSpreadStart then
            scheduleVisibleBlockCollection(resolvedReason .. ":retry")
        end
    end)
end

local function turnBookPage(direction, reason)
    if spreadRestoreInProgress then
        return false
    end

    local menu = tes3ui.findMenu("MenuBook")
    if not menu then
        return false
    end

    local button = findBookPageButton(menu, direction)
    if not button or button.visible == false then
        return false
    end

    local previousSpreadStart = getCurrentSpreadStart(menu)
    button:triggerEvent("mouseClick")
    schedulePageTurnSync(previousSpreadStart, reason or (direction > 0 and "pageRight" or "pageLeft"))
    return true
end

local function findBookNavigationContainer(menu)
    local nextButton = findBookPageButton(menu, 1)
    if nextButton and nextButton.parent then
        return nextButton.parent
    end

    local previousButton = findBookPageButton(menu, -1)
    if previousButton and previousButton.parent then
        return previousButton.parent
    end

    local pageNumber = menu and (
        menu:findChild(tes3ui.registerID("MenuBook_page_number_1"))
        or menu:findChild("MenuBook_page_number_1")
    )
    if pageNumber and pageNumber.parent then
        return pageNumber.parent
    end

    return menu
end

local function isHelpActive()
    return tes3ui.findMenu(HELP_MENU_ID) ~= nil
end

local function closeHelpMenu()
    local menu = tes3ui.findMenu(HELP_MENU_ID)
    if not menu then
        return false
    end

    menu:destroy()
    logger.debug("journal_custom help closed.")
    return true
end

local function openHelpMenu()
    if isHelpActive() then
        return false
    end

    local menu = tes3ui.createMenu({ id = HELP_MENU_ID, fixedFrame = true, modal = true })
    menu.alpha = 1.0
    menu.autoHeight = true
    menu.autoWidth = true
    menu.flowDirection = "top_to_bottom"
    menu.paddingAllSides = 12

    local title = menu:createLabel({ text = "journal_custom Help" })
    title.borderBottom = 8

    local lines = input.getHelpShortcutLines()

    local body = menu:createBlock({})
    body.width = 560
    body.autoHeight = true
    body.flowDirection = "top_to_bottom"
    body.borderBottom = 12

    for _, line in ipairs(lines) do
        local label = body:createLabel({ text = line })
        label.wrapText = true
        label.borderBottom = 4
    end

    local closeButton = menu:createButton({ id = HELP_CLOSE_BUTTON_ID, text = "Close" })
    closeButton:register(tes3.uiEvent.mouseClick, function()
        closeHelpMenu()
    end)

    menu:registerAfter("destroy", function()
        logger.debug("journal_custom help menu destroyed.")
    end)

    menu:getTopLevelMenu():updateLayout()
    logger.debug("journal_custom help opened.")
    return true
end

local function toggleHelpMenu()
    if isHelpActive() then
        return closeHelpMenu()
    end

    return openHelpMenu()
end

local function ensureHelpButton(menu)
    if not menu or menu:findChild(HELP_BUTTON_ID) then
        return false
    end

    local container = findBookNavigationContainer(menu)
    if not container then
        return false
    end

    local helpButton = container:createButton({ id = HELP_BUTTON_ID, text = "Help" })
    helpButton.borderLeft = 12
    helpButton:register(tes3.uiEvent.mouseClick, function()
        toggleHelpMenu()
    end)

    container:updateLayout()
    return true
end

local function applySelection(entryId, reason)
    if entryId == nil or entryId == "" then
        return false
    end

    local state = data.getState()
    local menu = tes3ui.findMenu("MenuBook")
    local currentSpreadStart = getCurrentSpreadStart(menu)
    if state.selectedEntryId == entryId
        and lastContext.selectedEntryId == entryId
        and lastContext.selectedSpreadStart == currentSpreadStart
    then
        return false
    end

    lastContext.selectedEntryId = entryId
    lastContext.selectedSpreadStart = currentSpreadStart
    data.setSelectedEntry(entryId)
    data.save()
    logger.debug("journal_custom selection (%s): %s", reason or "update", input.describeSelection(entryId))

    updateSelectionHighlight(menu)
    return true
end

local function clearSelection(reason)
    local state = data.getState()
    if state.selectedEntryId == nil and lastContext.selectedEntryId == nil and lastContext.selectedSpreadStart == nil then
        return false
    end

    local menu = tes3ui.findMenu("MenuBook")
    local currentSpreadStart = getCurrentSpreadStart(menu)
    local hadSelection = state.selectedEntryId ~= nil or lastContext.selectedEntryId ~= nil

    lastContext.selectedEntryId = nil
    lastContext.selectedSpreadStart = nil
    data.setSelectedEntry(nil)
    data.save()
    logger.debug("journal_custom selection cleared (%s).", reason or "update")

    if not hadSelection then
        return false
    end

    updateSelectionHighlight(menu)
    return true
end

local function summarizeVisibleBlocks(blocks)
    local parts = {}

    for _, block in ipairs(blocks or {}) do
        parts[#parts + 1] = string.format("p%d/%s:%s", block.pageNumber or 0, block.pageSide or "?", block.entryId or "?")
    end

    return table.concat(parts, ", ")
end

local function isEntryVisibleInBlocks(blocks, entryId)
    if not entryId or not blocks then
        return false
    end

    for _, block in ipairs(blocks) do
        if block.entryId == entryId then
            return true
        end
    end

    return false
end

local function persistVisibleBlocks(blocks)
    local state = data.getState()
    local changed = false
    local blocksByPage = {}
    local firstPageByEntry = {}

    for _, block in ipairs(blocks or {}) do
        local pageNumber = block.pageNumber
        if type(pageNumber) == "number" then
            blocksByPage[pageNumber] = blocksByPage[pageNumber] or {}
            blocksByPage[pageNumber][#blocksByPage[pageNumber] + 1] = block
        end

        local currentFirstPage = firstPageByEntry[block.entryId]
        if not currentFirstPage or (type(pageNumber) == "number" and pageNumber < currentFirstPage) then
            firstPageByEntry[block.entryId] = pageNumber
        end
    end

    for pageNumber, pageBlocks in pairs(blocksByPage) do
        if mapping.updatePageCache(state, pageNumber, pageBlocks) then
            changed = true
        end
    end

    for entryId, pageNumber in pairs(firstPageByEntry) do
        local entry = data.getEntry(entryId)
        if entry and type(pageNumber) == "number" and entry.lastKnownPage ~= pageNumber then
            data.setLastKnownPage(entryId, pageNumber)
            changed = true
        end
    end

    if changed then
        data.save()
    end

    return changed
end

local function collectVisibleBlocks(menu, reason)
    local ok, blocks = pcall(mapping.collectVisibleBlocks, menu, data.getState())
    if not ok then
        logger.warn("Failed to collect book mapping: %s", blocks)
        return false
    end

    activeVisibleBlocks = blocks
    if isSelectionEnabled() then
        local selectedEntryId = lastContext.selectedEntryId or data.getState().selectedEntryId
        local selectedSpreadStart = lastContext.selectedSpreadStart
        local spreadChanged = selectedSpreadStart ~= nil
            and blocks.spreadStart ~= nil
            and selectedSpreadStart ~= blocks.spreadStart

        if spreadChanged then
            if isEntryVisibleInBlocks(blocks, selectedEntryId) then
                lastContext.selectedSpreadStart = blocks.spreadStart
                selectedSpreadStart = blocks.spreadStart
                logger.debug(
                    "journal_custom selection kept after spread change: %s at %s.",
                    tostring(selectedEntryId),
                    tostring(blocks.spreadStart)
                )
            else
                clearSelection("pageChange")
                selectedEntryId = nil
                selectedSpreadStart = nil
            end
        elseif #blocks == 0 then
            if selectedEntryId then
                clearSelection("mapping")
            end
        else
            local resolvedEntryId, changed = input.resolveSelection(blocks, selectedEntryId, selectedSpreadStart)
            if changed then
                if resolvedEntryId then
                    applySelection(resolvedEntryId, "mapping")
                else
                    clearSelection("mapping")
                end
            end
        end

        updateSelectionHighlight(menu)
    end

    if #blocks == 0 then
        logger.debug("journal_custom mapping found no visible blocks (%s).", reason or "update")
        return false
    end

    persistVisibleBlocks(blocks)

    logger.debug("journal_custom mapping (%s): %s", reason or "update", summarizeVisibleBlocks(blocks))
    return true
end

scheduleVisibleBlockCollection = function(reason)
    if spreadRestoreInProgress then
        return
    end

    if mappingUpdateScheduled then
        return
    end

    mappingUpdateScheduled = true
    timer.frame.delayOneFrame(function()
        mappingUpdateScheduled = false

        local menu = tes3ui.findMenu("MenuBook")
        if not menu or not customBookSessionActive then
            return
        end

        collectVisibleBlocks(menu, reason)
    end)
end

local function syncVisibleBlocksForInput()
    local menu = tes3ui.findMenu("MenuBook")
    if not menu or spreadRestoreInProgress then
        return nil
    end

    local liveSpreadStart = getCurrentSpreadStart(menu)
    local cachedSpreadStart = activeVisibleBlocks and activeVisibleBlocks.spreadStart or nil
    local needsRefresh = #activeVisibleBlocks == 0

    if type(liveSpreadStart) == "number" and liveSpreadStart ~= cachedSpreadStart then
        needsRefresh = true
    end

    if needsRefresh then
        collectVisibleBlocks(menu, "keySync")
        if spreadRestoreInProgress then
            return nil
        end
    end

    return activeVisibleBlocks
end

local function scheduleSpreadRestore(targetSpreadStart, reason)
    local normalizedTarget = math.max(1, math.floor(targetSpreadStart or 1))

    if normalizedTarget <= 1 then
        spreadRestoreInProgress = false
        scheduleVisibleBlockCollection(reason or "open")
        return
    end

    spreadRestoreInProgress = true

    local restoreState = {
        targetSpreadStart = normalizedTarget,
        reason = reason or "restore",
        steps = 0,
        waitFrames = 0,
        maxSteps = math.max(4, math.floor(normalizedTarget / 2) + 4),
    }

    local function finishRestore(finalReason)
        spreadRestoreInProgress = false
        scheduleVisibleBlockCollection(finalReason or restoreState.reason)
    end

    local function advanceRestore(menu, currentSpreadStart)
        local current = currentSpreadStart

        while current ~= restoreState.targetSpreadStart do
            if restoreState.steps >= restoreState.maxSteps then
                return current, false, "limit"
            end

            local direction = current < restoreState.targetSpreadStart and 1 or -1
            local button = findBookPageButton(menu, direction)
            if not button or button.visible == false then
                return current, false, "button"
            end

            button:triggerEvent("mouseClick")
            restoreState.steps = restoreState.steps + 1

            local updatedSpreadStart = mapping.getCurrentSpreadStart(menu)
            if type(updatedSpreadStart) ~= "number" or updatedSpreadStart == current then
                return current, false, "pending"
            end

            current = updatedSpreadStart
        end

        return current, true, nil
    end

    local function stepRestore()
        local menu = tes3ui.findMenu("MenuBook")
        if not menu or not customBookSessionActive then
            spreadRestoreInProgress = false
            return
        end

        local currentSpreadStart = mapping.getCurrentSpreadStart(menu)
        if type(currentSpreadStart) ~= "number" then
            restoreState.waitFrames = restoreState.waitFrames + 1
            if restoreState.waitFrames > 6 then
                logger.warn("Could not read the current spread while restoring the book to %s.", tostring(restoreState.targetSpreadStart))
                finishRestore(restoreState.reason)
                return
            end

            timer.frame.delayOneFrame(stepRestore)
            return
        end

        if currentSpreadStart == restoreState.targetSpreadStart then
            finishRestore(restoreState.reason)
            return
        end

        local updatedSpreadStart, restored, failureReason = advanceRestore(menu, currentSpreadStart)
        if restored then
            finishRestore(restoreState.reason)
            return
        end

        if failureReason == "limit" then
            logger.warn(
                "Restauracao de spread abortada. Atual: %s, alvo: %s.",
                tostring(updatedSpreadStart),
                tostring(restoreState.targetSpreadStart)
            )
            finishRestore(restoreState.reason)
            return
        end

        if failureReason == "button" then
            logger.warn(
                "Botao de pagina indisponivel ao restaurar spread. Atual: %s, alvo: %s.",
                tostring(updatedSpreadStart),
                tostring(restoreState.targetSpreadStart)
            )
            finishRestore(restoreState.reason)
            return
        end

        timer.frame.delayOneFrame(stepRestore)
    end

    stepRestore()
end

local function handleMenuBookDestroyed(menu)
    coloredElements = {}
    timer.frame.delayOneFrame(function()
        if suppressedDestroyMenu == menu then
            suppressedDestroyMenu = nil
            return
        end

        if tes3ui.findMenu("MenuBook") then
            return
        end

        if not customBookSessionActive then
            return
        end

        closeHelpMenu()
        input.closeEdit()
        spreadRestoreInProgress = false
        customBookSessionActive = false
        activeBookHtml = nil
        activeVisibleBlocks = {}
        tes3ui.leaveMenuMode()
    end)
end

local function configureMenuBook(menu)
    if not menu then
        return false
    end

    menu:setPropertyBool(tes3.uiProperty.leaveMenuMode, true)
    input.ensure(menu)
    updateSelectionHighlight(menu)
    ensureHelpButton(menu)

    if menu:getLuaData("journal_custom:configured") then
        return true
    end

    menu:setLuaData("journal_custom:configured", true)
    menu:registerAfter("destroy", function()
        handleMenuBookDestroyed(menu)
    end)
    menu:registerAfter(tes3.uiEvent.mouseClick, function()
        scheduleVisibleBlockCollection("mouseClick")
    end)
    menu:registerAfter(tes3.uiEvent.keyPress, function(e)
        local _ = e
        scheduleVisibleBlockCollection("keyPress")
    end)

    return true
end

local function ensureMenuBookHooks()
    if menuBookHooksRegistered then
        return
    end

    event.register(tes3.event.uiActivated, function(e)
        if not customBookSessionActive then
            return
        end

        configureMenuBook(e.element)
        scheduleVisibleBlockCollection("uiActivated")
    end, { filter = "MenuBook" })

    event.register(tes3.event.keybindTested, function(e)
        if not customBookSessionActive or (not input.isEditActive() and not isHelpActive()) then
            return
        end

        if not e.result then
            return
        end

        e.result = false
        return false
    end, { filter = tes3.keybind.journal })

    event.register(tes3.event.keyDown, function(e)
        if not customBookSessionActive then
            return
        end

        if isHelpActive() then
            if input.matchesShortcut(e, "cancelModal") then
                if closeHelpMenu() then
                    return false
                end
            end

            return
        end

        if input.isEditActive() then
            if input.matchesShortcut(e, "cancelModal") then
                if input.cancelEdit() then
                    return false
                end
            elseif input.matchesShortcut(e, "saveModal") then
                if input.commitEdit() then
                    return false
                end
            else
                input.noteTyping(e)
            end

            return
        end

        if not input.isEditEnabled() then
            return
        end

        if input.matchesShortcut(e, "help") then
            if toggleHelpMenu() then
                return false
            end
        elseif input.matchesShortcut(e, "createDate") then
            local blocks = syncVisibleBlocksForInput()
            if beginCreateDate(blocks) then
                return false
            end
        elseif input.matchesShortcut(e, "createNote") then
            local blocks = syncVisibleBlocksForInput()
            if beginCreateNote(blocks) then
                return false
            end
        elseif input.matchesShortcut(e, "editEntry") then
            local blocks = syncVisibleBlocksForInput()
            if beginEditForSelection(blocks) then
                return false
            end
        end
    end)

    event.register(tes3.event.keyDown, function(e)
        if not customBookSessionActive then
            return
        end

        if input.isEditActive() or isHelpActive() then
            return
        end

        if turnBookPage(-1, "pageArrowLeft") then
            return false
        end
    end, { filter = tes3.scanCode.left })

    event.register(tes3.event.keyDown, function(e)
        if not customBookSessionActive then
            return
        end

        if input.isEditActive() or isHelpActive() then
            return
        end

        if turnBookPage(1, "pageArrowRight") then
            return false
        end
    end, { filter = tes3.scanCode.right })

    event.register(tes3.event.keyDown, function(e)
        if not customBookSessionActive or not isSelectionEnabled() then
            return
        end

        if input.isEditActive() or isHelpActive() then
            return
        end

        local blocks = syncVisibleBlocksForInput()
        local selectedEntryId = lastContext.selectedEntryId or data.getState().selectedEntryId
        local nextEntryId, handled = input.onKeyDown(e, blocks, selectedEntryId)
        if handled and nextEntryId then
            applySelection(nextEntryId, "keyDown")
            return false
        end
    end, { filter = tes3.scanCode.keyUp })

    event.register(tes3.event.keyDown, function(e)
        if not customBookSessionActive or not isSelectionEnabled() then
            return
        end

        if input.isEditActive() or isHelpActive() then
            return
        end

        local blocks = syncVisibleBlocksForInput()
        local selectedEntryId = lastContext.selectedEntryId or data.getState().selectedEntryId
        local nextEntryId, handled = input.onKeyDown(e, blocks, selectedEntryId)
        if handled and nextEntryId then
            applySelection(nextEntryId, "keyDown")
            return false
        end
    end, { filter = tes3.scanCode.keyDown })

    event.register(tes3.event.addSound, function(e)
        if not renderSoundSuppression.active
            or renderSoundSuppression.remaining <= 0
            or renderSoundSuppression.framesRemaining <= 0
        then
            return
        end

        local sound = e.sound
        if not sound or e.reference ~= nil then
            return
        end

        local soundId = string.lower(sound.id or "")
        local soundFilename = string.lower(sound.filename or "")
        local matchesBookSound = soundId:find("book", 1, true)
            or soundId:find("journal", 1, true)
            or soundFilename:find("book", 1, true)
            or soundFilename:find("journal", 1, true)
            or renderSoundSuppression.remaining == 2

        if not matchesBookSound then
            return
        end

        renderSoundSuppression.remaining = renderSoundSuppression.remaining - 1
        logger.debug(
            "journal_custom opening sound suppressed (%s): %s",
            tostring(renderSoundSuppression.reason or "render"),
            sound.id or sound.filename or "unknown"
        )

        if renderSoundSuppression.remaining <= 0 or soundId:find("book", 1, true) or soundFilename:find("book", 1, true) then
            clearRenderSoundSuppression()
        end

        e.block = true
        return false
    end, { priority = 1000000 })

    event.register(tes3.event.playItemSound, function(e)
        if not renderSoundSuppression.active
            or renderSoundSuppression.remaining <= 0
            or renderSoundSuppression.framesRemaining <= 0
        then
            return
        end

        local item = e.item
        local itemId = string.lower(item and item.id or "")
        local isBookLikeItem = itemId:find("book", 1, true)
            or itemId:find("journal", 1, true)
            or renderSoundSuppression.remaining == 2

        if not isBookLikeItem then
            return
        end

        renderSoundSuppression.remaining = renderSoundSuppression.remaining - 1

        if renderSoundSuppression.remaining <= 0 then
            clearRenderSoundSuppression()
        end

        e.block = true
        return false
    end, { priority = 1000000 })

    menuBookHooksRegistered = true
end

local function countRenderableEntries(entries)
    local count = 0

    for _, entry in pairs(entries or {}) do
        if type(entry) == "table" and entry.deleted ~= true then
            count = count + 1
        end
    end

    return count
end

local function setSelectionForRebuild(entryId, restoreSpreadStart)
    lastContext.selectedEntryId = entryId
    if type(restoreSpreadStart) == "number" then
        lastContext.selectedSpreadStart = restoreSpreadStart
    end
    data.setSelectedEntry(entryId)
end

local function handleEditSave(payload)
    local entryId = payload and payload.entryId or nil
    if not entryId or not data.updateEditedText(entryId, payload.draftText or "") then
        logger.warn("Failed to save journal_custom edit for %s.", tostring(entryId))
        return false
    end

    data.markDeleted(entryId, false)
    setSelectionForRebuild(entryId, payload.restoreSpreadStart)
    data.save()
    logger.info("journal_custom edit saved for %s.", tostring(entryId))
    return M.rebuild(true, payload.restoreSpreadStart, "editSave")
end

local function handleEditCancel(payload)
    local entryId = payload and payload.entryId or nil
    setSelectionForRebuild(entryId, payload and payload.restoreSpreadStart or nil)
    logger.debug("journal_custom edit canceled for %s.", tostring(entryId))
    updateSelectionHighlight(tes3ui.findMenu("MenuBook"))
    scheduleVisibleBlockCollection("editCancel")
    return true
end

local function handleEditDelete(payload)
    local entryId = payload and payload.entryId or nil
    if not entryId or not data.markDeleted(entryId, true) then
        logger.warn("Failed to delete journal_custom entry for %s.", tostring(entryId))
        return false
    end

    local fallbackEntryId = pickNeighborEntryId(payload and payload.visibleEntryIds or {}, entryId)
    setSelectionForRebuild(fallbackEntryId, payload.restoreSpreadStart)
    data.save()
    logger.info("journal_custom entry deleted: %s.", tostring(entryId))
    return M.rebuild(true, payload.restoreSpreadStart, "editDelete")
end

local function handleCreateNoteSave(payload)
    local currentDate = journalDate.getCurrentDateFields()
    local afterEntryId = lastContext.selectedEntryId or data.getState().selectedEntryId
    local created = data.createPlayerEntryAfter(afterEntryId, {
        daysPassed = currentDate.daysPassed,
        calendarDay = currentDate.calendarDay,
        calendarMonth = currentDate.calendarMonth,
        calendarYear = currentDate.calendarYear,
        dateCaptured = true,
        dateKey = journalDate.buildDateKey(currentDate),
        displayDate = journalDate.buildDisplayDate(currentDate),
        editedText = payload and payload.draftText or "",
        originalText = payload and payload.draftText or "",
    })

    if not created then
        logger.warn("Failed to create player note in journal_custom.")
        return false
    end

    data.ensureDateEntryForEntry(created.id)
    setSelectionForRebuild(created.id, payload and payload.restoreSpreadStart or nil)
    data.save()
    logger.info("Player note created in journal_custom: %s.", tostring(created.id))
    return M.rebuild(true, payload and payload.restoreSpreadStart or nil, "noteCreate")
end

local function handleCreateNoteCancel(payload)
    local _ = payload
    logger.debug("Player note creation canceled in journal_custom.")
    updateSelectionHighlight(tes3ui.findMenu("MenuBook"))
    scheduleVisibleBlockCollection("noteCancel")
    return true
end

local function handleCreateDateSave(payload)
    local currentDate = journalDate.getCurrentDateFields()
    local afterEntryId = lastContext.selectedEntryId or data.getState().selectedEntryId
    local draftLabel = journalDate.normalizeLabel(payload and payload.draftText or "")
    local defaultLabel = journalDate.buildDisplayDate(currentDate)

    if draftLabel == "" then
        draftLabel = defaultLabel
    end

    local useCurrentDateKey = draftLabel == defaultLabel
    local created = data.createDateEntryAfter(afterEntryId, {
        calendarDay = useCurrentDateKey and currentDate.calendarDay or nil,
        calendarMonth = useCurrentDateKey and currentDate.calendarMonth or nil,
        calendarYear = useCurrentDateKey and currentDate.calendarYear or nil,
        dateKind = "manual",
        dateKey = useCurrentDateKey and journalDate.buildDateKey(currentDate) or nil,
        daysPassed = useCurrentDateKey and currentDate.daysPassed or nil,
        displayDate = draftLabel,
        editedText = draftLabel,
        originalText = draftLabel,
    })

    if not created then
        logger.warn("Failed to create date entry in journal_custom.")
        return false
    end

    setSelectionForRebuild(created.id, payload and payload.restoreSpreadStart or nil)
    data.save()
    logger.info("Date entry created in journal_custom: %s.", tostring(created.id))
    return M.rebuild(true, payload and payload.restoreSpreadStart or nil, "dateCreate")
end

local function handleCreateDateCancel(payload)
    local _ = payload
    logger.debug("Date entry creation canceled in journal_custom.")
    updateSelectionHighlight(tes3ui.findMenu("MenuBook"))
    scheduleVisibleBlockCollection("dateCancel")
    return true
end

beginEditForSelection = function(blocks)
    local selectedEntryId = lastContext.selectedEntryId or data.getState().selectedEntryId
    if not selectedEntryId then
        return false
    end

    return input.beginEdit(selectedEntryId, blocks, {
        onCancel = handleEditCancel,
        onDelete = handleEditDelete,
        onSave = handleEditSave,
    })
end

beginCreateNote = function(blocks)
    return input.beginCreateNote(blocks, {
        onCancel = handleCreateNoteCancel,
        onSave = handleCreateNoteSave,
    })
end

beginCreateDate = function(blocks)
    return input.beginCreateDate(blocks, {
        onCancel = handleCreateDateCancel,
        onSave = handleCreateDateSave,
    })
end

local function resolveContext(preserveContext)
    local state = data.getState()

    return {
        title = "Journal Custom",
        viewMode = state.viewMode or lastContext.viewMode or "diary",
        selectedEntryId = preserveContext and (lastContext.selectedEntryId or state.selectedEntryId) or nil,
        selectedSpreadStart = preserveContext and lastContext.selectedSpreadStart or nil,
        restoreSpreadStart = preserveContext and lastContext.selectedSpreadStart or nil,
        lastSearch = state.lastSearch or "",
    }
end

local function renderCurrentBook(context, reason)
    local entries = data.getEntries()
    local restoreSpreadStart = type(context.restoreSpreadStart) == "number" and math.max(1, context.restoreSpreadStart) or nil
    local previousVisibleBlocks = activeVisibleBlocks
    local reuseVisibleBlocks = type(restoreSpreadStart) == "number"
        and type(previousVisibleBlocks) == "table"
        and type(previousVisibleBlocks.spreadStart) == "number"
        and previousVisibleBlocks.spreadStart == restoreSpreadStart

    activeBookHtml = render.renderBook(entries, context)
    customBookSessionActive = true
    activeVisibleBlocks = reuseVisibleBlocks and previousVisibleBlocks or {}
    spreadRestoreInProgress = restoreSpreadStart ~= nil and restoreSpreadStart > 1
    ensureMenuBookHooks()
    armRenderSoundSuppression(reason)

    local existingMenu = tes3ui.findMenu("MenuBook")
    if existingMenu then
        suppressedDestroyMenu = existingMenu
        tes3ui.closeBookMenu()
    end

    tes3ui.showBookMenu(activeBookHtml)
    lastContext = context
    configureMenuBook(tes3ui.findMenu("MenuBook"))
    updateSelectionHighlight(tes3ui.findMenu("MenuBook"))

    if spreadRestoreInProgress then
        scheduleSpreadRestore(restoreSpreadStart, reason or "rebuild")
    else
        scheduleVisibleBlockCollection(reason or "open")
    end

    logger.debug("journal_custom book opened with %d entries.", countRenderableEntries(entries))
    return true
end

function M.open()
    local ok, context = pcall(function()
        resetSelectionState()
        return resolveContext(false)
    end)
    if not ok then
        logger.warn("journal_custom book requested before the save finished loading.")
        tes3.messageBox("journal_custom has not loaded the save data yet.")
        return false
    end

    return renderCurrentBook(context, "open")
end

function M.close()
    if tes3ui.findMenu("MenuBook") then
        tes3ui.closeBookMenu()
        logger.debug("journal_custom book closed.")
        return true
    end

    return false
end

function M.isOpen()
    return customBookSessionActive == true and tes3ui.findMenu("MenuBook") ~= nil
end

function M.rebuild(preserveContext, restoreSpreadStart, reason)
    local context = resolveContext(preserveContext ~= false)
    context.restoreSpreadStart = type(restoreSpreadStart) == "number" and math.max(1, restoreSpreadStart) or context.restoreSpreadStart
    return renderCurrentBook(context, reason or "rebuild")
end

function M.restoreContext()
    return lastContext
end

function M.getVisibleBlocks()
    return activeVisibleBlocks
end

function M.getSelectedEntryId()
    return lastContext.selectedEntryId or data.getState().selectedEntryId
end

function M.goToEntry(entryId)
    lastContext.selectedEntryId = entryId
    data.setSelectedEntry(entryId)
    return M.rebuild(true)
end

return M
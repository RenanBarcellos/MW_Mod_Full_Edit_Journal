local config = require("journal_custom.config")
local data = require("journal_custom.journal.data")
local editor = require("journal_custom.journal.editor")
local journalDate = require("journal_custom.util.date")
local logger = require("journal_custom.util.logger")
local render = require("journal_custom.journal.render")

local M = {}

local function isSelectionEnabled()
    local currentConfig = config.get()
    local featureFlags = currentConfig.featureFlags or {}
    return featureFlags.enableSelection == true
end

local function isEditEnabled()
    local currentConfig = config.get()
    local featureFlags = currentConfig.featureFlags or {}
    return featureFlags.enableEditMode == true
end

local function getShortcutDefaults()
    local defaultSettings = config.getDefaults().settings or {}
    return defaultSettings.shortcuts or {}
end

local function getShortcutSettings()
    local settings = config.get().settings or {}
    return settings.shortcuts or {}
end

local function resolveShortcut(shortcutOrName)
    if type(shortcutOrName) == "table" then
        return shortcutOrName
    end

    if type(shortcutOrName) ~= "string" then
        return nil
    end

    local shortcuts = getShortcutSettings()
    return shortcuts[shortcutOrName] or getShortcutDefaults()[shortcutOrName]
end

local function resolveKeyName(keyCode)
    local resolvedKeyCode = type(keyCode) == "number" and keyCode or nil
    if not resolvedKeyCode then
        return "Unbound"
    end

    local ok, keyName = pcall(function()
        local gmst = tes3.findGMST(tes3.gmst.sKeyName_00 + resolvedKeyCode)
        return gmst and gmst.value or nil
    end)

    if ok and type(keyName) == "string" and keyName ~= "" then
        return keyName
    end

    return tostring(resolvedKeyCode)
end

local function describeShortcutValue(shortcutOrName)
    local resolvedShortcut = resolveShortcut(shortcutOrName)
    if type(resolvedShortcut) ~= "table" or type(resolvedShortcut.keyCode) ~= "number" then
        return "Unbound"
    end

    local parts = {}

    if resolvedShortcut.isControlDown then
        parts[#parts + 1] = "Ctrl"
    end

    if resolvedShortcut.isAltDown then
        parts[#parts + 1] = "Alt"
    end

    if resolvedShortcut.isShiftDown then
        parts[#parts + 1] = "Shift"
    end

    parts[#parts + 1] = resolveKeyName(resolvedShortcut.keyCode)
    return table.concat(parts, "+")
end

local function buildEditHelpText(isDateEntry)
    local saveShortcut = describeShortcutValue("saveModal")
    local cancelShortcut = describeShortcutValue("cancelModal")

    if isDateEntry then
        return string.format(
            "Edit the date label. %s saves. %s cancels. Use the Delete button to remove this date entry from the mod journal.",
            saveShortcut,
            cancelShortcut
        )
    end

    return string.format(
        "Edit the selected entry. %s saves. %s cancels. Use the Delete button to remove this entry from the mod journal.",
        saveShortcut,
        cancelShortcut
    )
end

local function buildCreateNoteHelpText()
    return string.format(
        "Write the note text. %s saves. %s cancels. The note is only created when you save.",
        describeShortcutValue("saveModal"),
        describeShortcutValue("cancelModal")
    )
end

local function buildCreateDateHelpText()
    return string.format(
        "Write the date label. %s saves. %s cancels. The date entry is only created when you save.",
        describeShortcutValue("saveModal"),
        describeShortcutValue("cancelModal")
    )
end

local function buildVisibleEntryList(blocks)
    local list = {}
    local visibleSet = {}

    for _, block in ipairs(blocks or {}) do
        local entryId = tostring(block.entryId or "")
        if entryId ~= "" then
            visibleSet[entryId] = true
        end
    end

    for _, entryId in ipairs(data.getOrderedEntryIds()) do
        if visibleSet[entryId] then
            list[#list + 1] = entryId
        end
    end

    return list
end

local function findEntryIndex(entryIds, selectedEntryId)
    for index, entryId in ipairs(entryIds) do
        if entryId == selectedEntryId then
            return index
        end
    end

    return nil
end

local function describeEntry(entryId)
    local entry = data.getEntry(entryId)
    if not entry then
        return tostring(entryId or "desconhecida")
    end

    return string.format("%s [%s]", render.buildHeaderTitle(entry), entry.id)
end

function M.ensure(menu)
    local _ = menu
    return true
end

function M.getShortcut(name)
    return resolveShortcut(name)
end

function M.matchesShortcut(e, shortcutOrName)
    local shortcut = resolveShortcut(shortcutOrName)
    if not e or type(shortcut) ~= "table" or type(shortcut.keyCode) ~= "number" then
        return false
    end

    return tes3.isKeyEqual({ actual = e, expected = shortcut })
end

function M.describeShortcut(shortcutOrName)
    return describeShortcutValue(shortcutOrName)
end

function M.getHelpShortcutLines()
    return {
        "Journal key: open journal_custom.",
        "Shift+Journal key: open the vanilla journal.",
        "Up Arrow / Down Arrow: move the current selection.",
        "Left Arrow / Right Arrow: turn the current book pages.",
        string.format("%s: edit the selected entry.", M.describeShortcut("editEntry")),
        string.format(
            "%s: create a new player note below the current selection, or at the end if nothing is selected.",
            M.describeShortcut("createNote")
        ),
        string.format(
            "%s: create a new date entry below the current selection, or at the end if nothing is selected.",
            M.describeShortcut("createDate")
        ),
        string.format("%s: toggle this help.", M.describeShortcut("help")),
        string.format("%s: save while the editor modal is open.", M.describeShortcut("saveModal")),
        string.format("%s: cancel the editor modal or close the help overlay.", M.describeShortcut("cancelModal")),
    }
end

function M.resolveSelection(blocks, selectedEntryId, selectedSpreadStart)
    if not isSelectionEnabled() then
        return selectedEntryId, false
    end

    local entryIds = buildVisibleEntryList(blocks)
    if #entryIds == 0 then
        return nil, false
    end

    local currentSpreadStart = blocks and blocks.spreadStart
    if selectedEntryId and selectedSpreadStart and currentSpreadStart and selectedSpreadStart ~= currentSpreadStart then
        return nil, true
    end

    if findEntryIndex(entryIds, selectedEntryId) then
        return selectedEntryId, false
    end

    if selectedEntryId then
        return nil, true
    end

    return nil, false
end

function M.moveSelection(blocks, selectedEntryId, direction)
    if not isSelectionEnabled() then
        return selectedEntryId, false
    end

    if not blocks or type(blocks.spreadStart) ~= "number" then
        return selectedEntryId, false
    end

    local entryIds = buildVisibleEntryList(blocks)
    if #entryIds == 0 then
        return nil, false
    end

    local currentIndex = findEntryIndex(entryIds, selectedEntryId)
    if not currentIndex then
        if direction < 0 then
            return entryIds[#entryIds], true
        end

        return entryIds[1], true
    end

    local nextIndex = math.max(1, math.min(#entryIds, currentIndex + direction))
    if nextIndex == currentIndex then
        return entryIds[currentIndex], true
    end

    return entryIds[nextIndex], true
end

function M.beginEdit(entryId, blocks, callbacks)
    if not isEditEnabled() then
        return false
    end

    if editor.isActive() then
        return false
    end

    local entry = data.getEntry(entryId)
    if not entry or entry.deleted == true then
        logger.warn("Nao foi possivel iniciar edicao para a entry %s.", tostring(entryId))
        return false
    end

    local isDateEntry = data.isDateEntry(entry)
    local titleText = isDateEntry
        and string.format("Editar data: %s", journalDate.resolveEntryDateLabel(entry))
        or nil
    local helpText = buildEditHelpText(isDateEntry)

    logger.info("Iniciando edicao do journal_custom: %s", describeEntry(entryId))

    return editor.open({
        entry = entry,
        helpText = helpText,
        onCancel = callbacks and callbacks.onCancel,
        onDelete = callbacks and callbacks.onDelete,
        onSave = callbacks and callbacks.onSave,
        restoreSpreadStart = blocks and blocks.spreadStart or nil,
        sessionKind = "edit",
        titleText = titleText,
        visibleEntryIds = buildVisibleEntryList(blocks),
    })
end

function M.beginCreateNote(blocks, callbacks)
    if not isEditEnabled() then
        return false
    end

    if editor.isActive() then
        return false
    end

    logger.info("Iniciando criacao de nota do jogador no journal_custom.")

    return editor.open({
        entry = {
            id = "__new_player_note__",
            editedText = "",
            originalText = "",
            source = "player",
            displayDate = "Nova nota",
        },
        helpText = buildCreateNoteHelpText(),
        initialText = "",
        onCancel = callbacks and callbacks.onCancel,
        onSave = callbacks and callbacks.onSave,
        restoreSpreadStart = blocks and blocks.spreadStart or nil,
        sessionKind = "create",
        showDelete = false,
        titleText = "Nova nota do jogador",
        visibleEntryIds = buildVisibleEntryList(blocks),
    })
end

function M.beginCreateDate(blocks, callbacks)
    if not isEditEnabled() then
        return false
    end

    if editor.isActive() then
        return false
    end

    local initialLabel = journalDate.buildDisplayDate(journalDate.getCurrentDateFields())

    logger.info("Iniciando criacao de entry de data no journal_custom.")

    return editor.open({
        entry = {
            id = "__new_date_entry__",
            displayDate = initialLabel,
            editedText = initialLabel,
            entryType = "date",
            originalText = initialLabel,
            source = "player",
        },
        helpText = buildCreateDateHelpText(),
        initialText = initialLabel,
        onCancel = callbacks and callbacks.onCancel,
        onSave = callbacks and callbacks.onSave,
        restoreSpreadStart = blocks and blocks.spreadStart or nil,
        sessionKind = "createDate",
        showDelete = false,
        titleText = "Nova entrada de data",
        visibleEntryIds = buildVisibleEntryList(blocks),
    })
end

function M.commitEdit()
    return editor.commit()
end

function M.cancelEdit()
    return editor.cancel()
end

function M.deleteEdit()
    return editor.delete()
end

function M.closeEdit()
    return editor.close()
end

function M.isEditActive()
    return editor.isActive()
end

function M.isEditEnabled()
    return isEditEnabled()
end

function M.noteTyping(e)
    return editor.noteTyping(e)
end

function M.onKeyDown(e, blocks, selectedEntryId)
    if not isSelectionEnabled() then
        return nil, false
    end

    local keyCode = e and (e.keyCode or e.data0)
    if keyCode == tes3.scanCode.keyUp then
        return M.moveSelection(blocks, selectedEntryId, -1)
    end

    if keyCode == tes3.scanCode.keyDown then
        return M.moveSelection(blocks, selectedEntryId, 1)
    end

    return selectedEntryId, false
end

function M.onKeyPress(e, blocks, selectedEntryId)
    return M.onKeyDown(e, blocks, selectedEntryId)
end

function M.describeSelection(entryId)
    return describeEntry(entryId)
end

return M
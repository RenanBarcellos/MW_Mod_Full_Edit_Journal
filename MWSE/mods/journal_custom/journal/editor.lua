local logger = require("journal_custom.util.logger")
local render = require("journal_custom.journal.render")

local M = {}

local MENU_ID = tes3ui.registerID("journal_custom:editor_menu")
local INPUT_ID = tes3ui.registerID("journal_custom:editor_input")
local SAVE_BUTTON_ID = tes3ui.registerID("journal_custom:editor_save")
local CANCEL_BUTTON_ID = tes3ui.registerID("journal_custom:editor_cancel")
local DELETE_BUTTON_ID = tes3ui.registerID("journal_custom:editor_delete")
local WRITE_SOUND_PATH = "Fx\\magic\\BOOKPAG1.wav"
local WRITE_SOUND_VOLUME = 0.22
local WRITE_SOUND_PITCH = 1.08
local WRITE_SOUND_COOLDOWN = 0.24

local NON_WRITING_KEYS = {
    [tes3.scanCode.capsLock] = true,
    [tes3.scanCode.down] = true,
    [tes3.scanCode["end"]] = true,
    [tes3.scanCode.home] = true,
    [tes3.scanCode.insert] = true,
    [tes3.scanCode.left] = true,
    [tes3.scanCode.lAlt] = true,
    [tes3.scanCode.lCtrl] = true,
    [tes3.scanCode.lShift] = true,
    [tes3.scanCode.pageDown] = true,
    [tes3.scanCode.pageUp] = true,
    [tes3.scanCode.rAlt] = true,
    [tes3.scanCode.rCtrl] = true,
    [tes3.scanCode.right] = true,
    [tes3.scanCode.rShift] = true,
    [tes3.scanCode.tab] = true,
    [tes3.scanCode.up] = true,
}

local activeSession
local typingSoundState = {
    cooldown = false,
    token = 0,
}

local function resetTypingFeedback()
    typingSoundState.cooldown = false
    typingSoundState.token = typingSoundState.token + 1
end

local function armTypingCooldown()
    typingSoundState.cooldown = true
    typingSoundState.token = typingSoundState.token + 1

    local token = typingSoundState.token
    timer.start({
        callback = function()
            if typingSoundState.token ~= token then
                return
            end

            typingSoundState.cooldown = false
        end,
        duration = WRITE_SOUND_COOLDOWN,
        type = timer.real,
    })
end

local function isWritingKey(e)
    local keyCode = e and (e.keyCode or e.data0) or nil
    if type(keyCode) ~= "number" then
        return false
    end

    if NON_WRITING_KEYS[keyCode] then
        return false
    end

    if e.isAltDown or e.isSuperDown then
        return false
    end

    if e.isControlDown and keyCode ~= tes3.scanCode.backspace and keyCode ~= tes3.scanCode.delete then
        return false
    end

    return true
end

local function playTypingSound()
    if typingSoundState.cooldown then
        return false
    end

    armTypingCooldown()
    tes3.playSound({
        mixChannel = tes3.soundMix.effects,
        pitch = WRITE_SOUND_PITCH,
        soundPath = WRITE_SOUND_PATH,
        volume = WRITE_SOUND_VOLUME,
    })
    return true
end

local function releaseTextInput()
    tes3ui.acquireTextInput(nil)
end

local function destroyMenu()
    resetTypingFeedback()
    releaseTextInput()

    local menu = tes3ui.findMenu(MENU_ID)
    if menu then
        menu:destroy()
    end
end

local function buildPayload(session)
    local draftText = session.draftText or session.originalText or ""
    if session.input then
        draftText = session.input.text or draftText
    end

    return {
        draftText = draftText,
        entryId = session.entryId,
        originalText = session.originalText,
        restoreSpreadStart = session.restoreSpreadStart,
        sessionKind = session.sessionKind,
        visibleEntryIds = session.visibleEntryIds,
    }
end

local function finalize(actionKey)
    if not activeSession then
        return false
    end

    local session = activeSession
    local callback = session[actionKey]
    local payload = buildPayload(session)

    resetTypingFeedback()
    activeSession = nil
    destroyMenu()

    if callback then
        callback(payload)
    end

    return true
end

function M.isActive()
    return activeSession ~= nil
end

function M.getEntryId()
    return activeSession and activeSession.entryId or nil
end

function M.noteTyping(e)
    if not activeSession or not activeSession.input or not isWritingKey(e) then
        return false
    end

    return playTypingSound()
end

function M.open(params)
    if M.isActive() then
        logger.debug("journal_custom editor was already active for %s.", tostring(M.getEntryId()))
        return false
    end

    local entry = params and params.entry or nil
    if type(entry) ~= "table" or type(entry.id) ~= "string" or entry.id == "" then
        logger.warn("Attempted to open editor without a valid entry.")
        return false
    end

    destroyMenu()

    local titleText = params.titleText or string.format("Edit: %s", render.buildHeaderTitle(entry))
    local helpText = params.helpText or "Use the configured save and cancel shortcuts, or the buttons below."
    local inputText = tostring(params.initialText or entry.editedText or entry.originalText or "")
    local showDelete = params.showDelete ~= false
    local deleteButtonText = params.deleteButtonText or "Delete"

    local menu = tes3ui.createMenu({ id = MENU_ID, fixedFrame = true, modal = true })
    menu.alpha = 1.0
    menu.autoHeight = true
    menu.autoWidth = true
    menu.flowDirection = "top_to_bottom"
    menu.paddingAllSides = 12

    local title = menu:createLabel({ text = titleText })
    title.borderBottom = 6

    local help = menu:createLabel({ text = helpText })
    help.borderBottom = 10

    local inputBlock = menu:createBlock({})
    inputBlock.width = 760
    inputBlock.autoHeight = true
    inputBlock.borderBottom = 12

    local inputBorder = inputBlock:createThinBorder({})
    inputBorder.width = 760
    inputBorder.height = 320
    inputBorder.paddingAllSides = 8

    local input = inputBorder:createParagraphInput({ id = INPUT_ID })
    input.width = 744
    input.height = 304
    input.text = inputText
    input.widget.lengthLimit = 12000

    local buttonRow = menu:createBlock({})
    buttonRow.width = 760
    buttonRow.autoHeight = true
    buttonRow.flowDirection = "left_to_right"

    local saveButton = buttonRow:createButton({ id = SAVE_BUTTON_ID, text = "Save" })
    saveButton.borderRight = 8
    saveButton:register("mouseClick", function()
        M.commit()
    end)

    local cancelButton = buttonRow:createButton({ id = CANCEL_BUTTON_ID, text = "Cancel" })
    cancelButton.borderRight = 8
    cancelButton:register("mouseClick", function()
        M.cancel()
    end)

    if showDelete then
        local deleteButton = buttonRow:createButton({ id = DELETE_BUTTON_ID, text = deleteButtonText })
        deleteButton:register("mouseClick", function()
            M.delete()
        end)
    end

    activeSession = {
        draftText = input.text,
        entryId = entry.id,
        input = input,
        menu = menu,
        onCancel = params.onCancel,
        onDelete = params.onDelete,
        onSave = params.onSave,
        originalText = tostring(entry.editedText or entry.originalText or ""),
        restoreSpreadStart = params.restoreSpreadStart,
        sessionKind = params.sessionKind or "edit",
        visibleEntryIds = params.visibleEntryIds or {},
    }

    menu:registerAfter("destroy", function()
        releaseTextInput()
        if activeSession and activeSession.menu == menu then
            activeSession = nil
        end
    end)

    menu:getTopLevelMenu():updateLayout()
    tes3ui.acquireTextInput(input)

    logger.info("journal_custom editor opened for %s.", tostring(entry.id))
    return true
end

function M.commit()
    return finalize("onSave")
end

function M.cancel()
    return finalize("onCancel")
end

function M.delete()
    return finalize("onDelete")
end

function M.close()
    if not activeSession then
        destroyMenu()
        return false
    end

    resetTypingFeedback()
    activeSession = nil
    destroyMenu()
    return true
end

return M
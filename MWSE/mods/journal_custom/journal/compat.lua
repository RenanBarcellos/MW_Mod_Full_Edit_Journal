local config = require("journal_custom.config")
local input = require("journal_custom.journal.input")
local logger = require("journal_custom.util.logger")

local M = {}

local keybindRedirectRegistered = false
local vanillaSuppressionRegistered = false
local allowVanillaJournalActivation = 0

-- These menus either own text input or represent UI states where hijacking the
-- journal key would feel unsafe or surprising.
local BLOCKED_MENU_IDS = {
    MenuAlchemy = true,
    MenuBarter = true,
    MenuContents = true,
    MenuDialog = true,
    MenuEnchantment = true,
    MenuLoad = true,
    MenuLoading = true,
    MenuMessage = true,
    MenuName = true,
    MenuPersuasion = true,
    MenuQuantity = true,
    MenuRepair = true,
    MenuRestWait = true,
    MenuSave = true,
    MenuServiceSpells = true,
    MenuServiceTraining = true,
    MenuServiceTravel = true,
    MenuSpellmaking = true,
}

-- The redirect layer can be toggled at runtime from config and MCM.
local function isVanillaJournalBlockEnabled()
    local currentConfig = config.get()
    local featureFlags = currentConfig.featureFlags or {}
    return featureFlags.enableVanillaJournalBlock == true
end

-- When a text field owns focus, the journal key should behave like normal text
-- input instead of opening or closing menus.
local function isTextInputActive()
    local worldController = tes3.worldController
    local menuController = worldController and worldController.menuController or nil
    local inputController = menuController and menuController.inputController or nil
    local textInputFocus = inputController and inputController.textInputFocus or nil
    return textInputFocus ~= nil and textInputFocus.visible == true
end

-- Shift is used as the explicit escape hatch to open the vanilla journal.
local function isShiftHeld()
    local worldController = tes3.worldController
    local inputController = worldController and worldController.inputController or nil
    return inputController ~= nil and inputController:isShiftDown() == true
end

-- Some engine menus do not expose a direct "safe to intercept" flag, so this
-- helper checks the known conflicting menu ids.
local function findBlockingMenuId()
    for menuId in pairs(BLOCKED_MENU_IDS) do
        if tes3ui.findMenu(menuId) then
            return menuId
        end
    end

    return nil
end

-- The compat layer does not own the custom journal UI; it just calls back into
-- whichever module is responsible for opening it.
local function runOpenBookCallback(openBookCallback)
    if type(openBookCallback) ~= "function" then
        return
    end

    local ok, err = pcall(openBookCallback)
    if not ok then
        logger.error("Failed to execute journal_custom callback: %s", err)
    end
end

-- Shift+Journal temporarily bypasses the custom redirect and reopens the
-- vanilla journal UI.
local function openVanillaJournal()
    if tes3ui.findMenu("MenuBook") then
        tes3ui.closeBookMenu()
    end

    allowVanillaJournalActivation = allowVanillaJournalActivation + 1
    if tes3ui.showJournal() then
        logger.info("Vanilla journal opened through Shift+J.")
        return true
    end

    allowVanillaJournalActivation = math.max(0, allowVanillaJournalActivation - 1)
    logger.warn("Failed to open the vanilla journal through Shift+J.")
    return false
end

-- Centralize every reason the journal key should be ignored instead of routed.
function M.shouldSuppressJournalKeybind()
    if input.isEditActive() then
        return true, "editor"
    end

    if isTextInputActive() then
        return true, "textInput"
    end

    local menuId = findBlockingMenuId()
    if menuId then
        return true, menuId
    end

    return false, nil
end

-- Intercept the configured journal keybind and decide whether it should open
-- journal_custom, the vanilla journal, or nothing at all.
function M.registerKeybindRedirect(openBookCallback)
    if keybindRedirectRegistered then
        return
    end

    event.register(tes3.event.keybindTested, function(e)
        if not isVanillaJournalBlockEnabled() then
            return
        end

        if e.transition ~= tes3.keyTransition.downThisFrame then
            return
        end

        if not e.result then
            return
        end

        if isShiftHeld() then
            local shouldSuppress, reason = M.shouldSuppressJournalKeybind()
            if shouldSuppress then
                logger.debug("Shift+J consumed without opening the vanilla journal (%s).", tostring(reason))
                e.result = false
                return false
            end

            e.result = false
            openVanillaJournal()
            return false
        end

        local shouldSuppress, reason = M.shouldSuppressJournalKeybind()
        if shouldSuppress then
            logger.debug("Journal keybind consumed without opening journal_custom (%s).", tostring(reason))
            e.result = false
            return false
        end

        logger.debug("Redirecting journal keybind to journal_custom.")
        e.result = false
        runOpenBookCallback(openBookCallback)
    end, { filter = tes3.keybind.journal })

    keybindRedirectRegistered = true
end

-- Some systems can still try to activate MenuJournal directly, so close or
-- destroy it unless the user explicitly requested the vanilla fallback.
function M.registerVanillaJournalSuppression()
    if vanillaSuppressionRegistered then
        return
    end

    event.register(tes3.event.uiActivated, function()
        if not isVanillaJournalBlockEnabled() then
            return
        end

        if allowVanillaJournalActivation > 0 then
            allowVanillaJournalActivation = allowVanillaJournalActivation - 1
            return
        end

        if tes3ui.closeJournal() then
            logger.debug("Vanilla MenuJournal closed by the compatibility layer.")
            return
        end

        local menu = tes3ui.findMenu("MenuJournal")
        if menu then
            menu:destroy()
            logger.debug("Vanilla MenuJournal destroyed by the compatibility layer.")
        end
    end, { filter = "MenuJournal" })

    vanillaSuppressionRegistered = true
end

-- The public entry point wires both redirect strategies together.
function M.register(openBookCallback)
    M.registerKeybindRedirect(openBookCallback)
    M.registerVanillaJournalSuppression()
end

return M
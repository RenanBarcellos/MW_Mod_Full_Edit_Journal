local config = require("journal_custom.config")
local input = require("journal_custom.journal.input")

local modName = "Journal Custom"

-- All shortcut binders share the same defaults and storage location, so keep
-- that wiring in one helper.
local function createShortcutBinder(category, shortcutId, label, description)
    category:createKeyBinder({
        label = label,
        description = description,
        allowCombinations = true,
        defaultSetting = config.getDefaults().settings.shortcuts[shortcutId],
        showDefaultSetting = true,
        variable = mwse.mcm.createTableVariable({
            id = shortcutId,
            table = config.get().settings.shortcuts,
        }),
    })
end

-- Expose the runtime feature flags and shortcuts through MCM so testing and
-- rollout do not require code edits.
local function registerModConfig()
    local template = mwse.mcm.createTemplate({
        name = modName,
        config = config.get(),
        defaultConfig = config.getDefaults(),
    })
    template.onClose = function()
        config.save()
    end

    local page = template:createPage({ label = "General" })

    page:createInfo({
        text = "Configuration for journal_custom version 1.0. The recommended defaults already leave the mod ready to use without editing code.",
    })

    local rolloutCategory = page:createCategory({ label = "Features" })

    rolloutCategory:createOnOffButton({
        label = "Block vanilla journal",
        description = "Intercepts the vanilla journal opening and redirects it to journal_custom.",
        variable = mwse.mcm.createTableVariable({
            id = "enableVanillaJournalBlock",
            table = config.get().featureFlags,
        }),
    })

    rolloutCategory:createOnOffButton({
        label = "Book mode",
        description = "Opens journal_custom in MenuBook instead of only registering the intercept.",
        variable = mwse.mcm.createTableVariable({
            id = "enableBookMode",
            table = config.get().featureFlags,
        }),
    })

    rolloutCategory:createOnOffButton({
        label = "Navigable selection",
        description = "Enables arrow-key selection inside the current spread.",
        variable = mwse.mcm.createTableVariable({
            id = "enableSelection",
            table = config.get().featureFlags,
        }),
    })

    rolloutCategory:createOnOffButton({
        label = "Modal editing",
        description = "Enables the Phase 8 editing modal and player note creation.",
        variable = mwse.mcm.createTableVariable({
            id = "enableEditMode",
            table = config.get().featureFlags,
        }),
    })

    rolloutCategory:createOnOffButton({
        label = "Legacy migration",
        description = "Imports data from the legacy per-save format when needed.",
        variable = mwse.mcm.createTableVariable({
            id = "enableMigration",
            table = config.get().featureFlags,
        }),
    })

    local shortcutsCategory = page:createCategory({ label = "Shortcuts" })

    shortcutsCategory:createInfo({
        text = table.concat({
            "Shortcuts used by the mod:",
            table.concat(input.getHelpShortcutLines(), "\n"),
        }, "\n\n"),
    })

    createShortcutBinder(
        shortcutsCategory,
        "help",
        "Open help",
        "Toggles the help overlay inside journal_custom."
    )
    createShortcutBinder(
        shortcutsCategory,
        "editEntry",
        "Edit selected entry",
        "Opens the editing modal for the selected entry."
    )
    createShortcutBinder(
        shortcutsCategory,
        "createNote",
        "Create player note",
        "Creates a note below the current selection or at the end if nothing is selected."
    )
    createShortcutBinder(
        shortcutsCategory,
        "createDate",
        "Create date entry",
        "Creates a date entry below the current selection or at the end if nothing is selected."
    )
    createShortcutBinder(
        shortcutsCategory,
        "saveModal",
        "Save in modal",
        "Confirms editing or creation while the modal is open."
    )
    createShortcutBinder(
        shortcutsCategory,
        "cancelModal",
        "Cancel in modal",
        "Cancels the current edit or closes the contextual help."
    )

    local debugCategory = page:createCategory({ label = "Debug and diagnostics" })

    debugCategory:createOnOffButton({
        label = "Detailed logs",
        description = "Keeps detailed journal_custom logs in MWSE.log.",
        variable = mwse.mcm.createTableVariable({
            id = "debugLogging",
            table = config.get().featureFlags,
        }),
    })

    debugCategory:createInfo({
        text = "The journal keybind still comes from the game's Controls menu. Holding Shift while using that keybind opens the vanilla journal.",
    })

    template:register()
end

event.register("modConfigReady", registerModConfig)
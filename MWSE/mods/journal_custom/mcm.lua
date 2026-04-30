local config = require("journal_custom.config")
local input = require("journal_custom.journal.input")

local modName = "Journal Custom"

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

local function registerModConfig()
    local template = mwse.mcm.createTemplate({
        name = modName,
        config = config.get(),
        defaultConfig = config.getDefaults(),
    })
    template.onClose = function()
        config.save()
    end

    local page = template:createPage({ label = "Geral" })

    page:createInfo({
        text = "Configuracao da versao 1.0 do journal_custom. Os defaults recomendados ja deixam o mod pronto para uso sem editar codigo.",
    })

    local rolloutCategory = page:createCategory({ label = "Features" })

    rolloutCategory:createOnOffButton({
        label = "Bloquear journal vanilla",
        description = "Interceta a abertura do journal vanilla para redirecionar ao journal_custom.",
        variable = mwse.mcm.createTableVariable({
            id = "enableVanillaJournalBlock",
            table = config.get().featureFlags,
        }),
    })

    rolloutCategory:createOnOffButton({
        label = "Modo livro",
        description = "Abre o journal_custom no MenuBook em vez de apenas registrar o intercept.",
        variable = mwse.mcm.createTableVariable({
            id = "enableBookMode",
            table = config.get().featureFlags,
        }),
    })

    rolloutCategory:createOnOffButton({
        label = "Selecao navegavel",
        description = "Habilita a selecao por setas dentro do spread atual.",
        variable = mwse.mcm.createTableVariable({
            id = "enableSelection",
            table = config.get().featureFlags,
        }),
    })

    rolloutCategory:createOnOffButton({
        label = "Edicao modal",
        description = "Habilita o modal de edicao da Fase 8 e a criacao de notas do jogador.",
        variable = mwse.mcm.createTableVariable({
            id = "enableEditMode",
            table = config.get().featureFlags,
        }),
    })

    rolloutCategory:createOnOffButton({
        label = "Migracao legada",
        description = "Importa dados do formato legado por save quando necessario.",
        variable = mwse.mcm.createTableVariable({
            id = "enableMigration",
            table = config.get().featureFlags,
        }),
    })

    local shortcutsCategory = page:createCategory({ label = "Atalhos" })

    shortcutsCategory:createInfo({
        text = table.concat({
            "Atalhos usados no mod:",
            table.concat(input.getHelpShortcutLines(), "\n"),
        }, "\n\n"),
    })

    createShortcutBinder(
        shortcutsCategory,
        "help",
        "Abrir help",
        "Alterna a sobreposicao de help dentro do journal_custom."
    )
    createShortcutBinder(
        shortcutsCategory,
        "editEntry",
        "Editar entrada selecionada",
        "Abre o modal de edicao para a entrada selecionada."
    )
    createShortcutBinder(
        shortcutsCategory,
        "createNote",
        "Criar nota do jogador",
        "Cria uma nota abaixo da selecao atual ou no fim se nao houver selecao."
    )
    createShortcutBinder(
        shortcutsCategory,
        "createDate",
        "Criar entrada de data",
        "Cria uma entrada de data abaixo da selecao atual ou no fim se nao houver selecao."
    )
    createShortcutBinder(
        shortcutsCategory,
        "saveModal",
        "Salvar no modal",
        "Confirma a edicao ou criacao quando o modal estiver aberto."
    )
    createShortcutBinder(
        shortcutsCategory,
        "cancelModal",
        "Cancelar no modal",
        "Cancela a edicao atual ou fecha a ajuda contextual."
    )

    local debugCategory = page:createCategory({ label = "Debug e diagnostico" })

    debugCategory:createOnOffButton({
        label = "Logs detalhados",
        description = "Mantem logs detalhados do journal_custom no MWSE.log.",
        variable = mwse.mcm.createTableVariable({
            id = "debugLogging",
            table = config.get().featureFlags,
        }),
    })

    debugCategory:createInfo({
        text = "O keybind do journal continua vindo do menu Controls do jogo. Segurar Shift enquanto usa esse keybind abre o journal vanilla.",
    })

    template:register()
end

event.register("modConfigReady", registerModConfig)
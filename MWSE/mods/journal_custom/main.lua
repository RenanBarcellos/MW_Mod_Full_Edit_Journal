local config = require("journal_custom.config")
local book = require("journal_custom.journal.book")
local capture = require("journal_custom.journal.capture")
local compat = require("journal_custom.journal.compat")
local migrate = require("journal_custom.journal.migrate")
local logger = require("journal_custom.util.logger")
require("journal_custom.mcm")
local data = require("journal_custom.journal.data")

local function openJournalEntryPoint()
    local currentConfig = config.get()
    local featureFlags = currentConfig.featureFlags or {}

    local shouldSuppress, reason = compat.shouldSuppressJournalKeybind()
    if shouldSuppress then
        logger.debug("Abertura do journal_custom ignorada por contexto de UI (%s).", tostring(reason))
        return
    end

    if featureFlags.enableBookMode then
        if book.isOpen() then
            book.close()
            return
        end

        book.open()
        return
    end

    tes3.messageBox("journal_custom interceptou a tecla do journal.")
    logger.debug("Callback de entrada do journal_custom executado.")
end

local function initialized()
    config.load()
    capture.register()
    compat.register(openJournalEntryPoint)
    logger.info("Inicializado.")
end

local function loaded(e)
    data.load(e.filename)
    capture.flushPendingEntries()

    local currentConfig = config.get()
    local featureFlags = currentConfig.featureFlags or {}

    if featureFlags.enableMigration and migrate.needsMigration(data.getState()) then
        migrate.run()
    end

    if featureFlags.debugLogging then
        local _, created = data.ensureDebugSeedEntry()

        if created then
            logger.info(
                "Nota de debug registrada no journal do save '%s' e sera gravada no proximo save.",
                data.getProfileKey()
            )
        else
            logger.debug("Nota de debug ja existia para o save '%s'.", data.getProfileKey())
        end
    end
end

local function save(e)
    local ok, _, flushed = pcall(data.flush, e and e.filename)
    if not ok then
        logger.error(
            "Falha ao preparar o journal_custom para o save '%s'.",
            e and e.filename or data.getProfileKey() or "desconhecido"
        )
        return
    end

    if not flushed then
        return
    end

    logger.debug("Journal do save '%s' sincronizado antes da gravacao.", data.getProfileKey())
end

event.register(tes3.event.initialized, initialized)
event.register(tes3.event.loaded, loaded)
event.register(tes3.event.save, save)
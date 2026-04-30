local config = require("journal_custom.config")
local book = require("journal_custom.journal.book")
local capture = require("journal_custom.journal.capture")
local compat = require("journal_custom.journal.compat")
local migrate = require("journal_custom.journal.migrate")
local logger = require("journal_custom.util.logger")
require("journal_custom.mcm")
local data = require("journal_custom.journal.data")

local function resolveTopicLabel(topic)
    if type(topic) == "string" and topic ~= "" then
        return topic
    end

    if type(topic) ~= "table" then
        return nil
    end

    if type(topic.id) == "string" and topic.id ~= "" then
        return topic.id
    end

    if type(topic.name) == "string" and topic.name ~= "" then
        return topic.name
    end

    return nil
end

-- Dialogue topics can be unlocked independently of journal capture, so keep a
-- save-scoped index updated as the game exposes new topics to the player.
local function rememberUnlockedTopic(e)
    if not data.isLoaded() then
        return
    end

    local topicLabel = resolveTopicLabel(e and (e.topic or e.topicId or e.id or e.name))
    if not topicLabel or not data.rememberKnownTopic(topicLabel) then
        return
    end

    logger.debug("Known topic unlocked for save '%s': %s.", data.getProfileKey() or "unknown", topicLabel)
end

-- The game can rebuild the topic list wholesale, so rescan persisted state to
-- keep the lookup normalized after those refreshes.
local function topicsListUpdated()
    if not data.isLoaded() or not data.rebuildKnownTopics() then
        return
    end

    logger.debug("Known topic index rebuilt for save '%s'.", data.getProfileKey() or "unknown")
end

-- Route the journal key either to the custom book UI or to the lightweight
-- debug intercept, depending on the current feature flags.
local function openJournalEntryPoint()
    local currentConfig = config.get()
    local featureFlags = currentConfig.featureFlags or {}

    local shouldSuppress, reason = compat.shouldSuppressJournalKeybind()
    if shouldSuppress then
        logger.debug("journal_custom open ignored due to UI context (%s).", tostring(reason))
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

    tes3.messageBox("journal_custom intercepted the journal key.")
    logger.debug("journal_custom input callback executed.")
end

-- Register runtime systems once MWSE finishes loading the mod.
local function initialized()
    config.load()
    capture.register()
    compat.register(openJournalEntryPoint)
    event.register(tes3.event.topicAdded, rememberUnlockedTopic)
    event.register(tes3.event.topicsListUpdated, topicsListUpdated)
    logger.info("Initialized.")
end

-- Hydrate per-save state and run one-time migration or debug seeding after a
-- save has been loaded.
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
                "Debug note registered in save journal '%s' and will be written on the next save.",
                data.getProfileKey()
            )
        else
            logger.debug("Debug note already existed for save '%s'.", data.getProfileKey())
        end
    end

    topicsListUpdated()
end

-- Copy the in-memory journal snapshot into Lua data right before the game
-- writes the save file.
local function save(e)
    local ok, _, flushed = pcall(data.flush, e and e.filename)
    if not ok then
        logger.error(
            "Failed to prepare journal_custom for save '%s'.",
            e and e.filename or data.getProfileKey() or "unknown"
        )
        return
    end

    if not flushed then
        return
    end

    logger.debug("Save journal '%s' synced before write.", data.getProfileKey())
end

-- Keep the entry point small: runtime work happens inside the modules above.
event.register(tes3.event.initialized, initialized)
event.register(tes3.event.loaded, loaded)
event.register(tes3.event.save, save)
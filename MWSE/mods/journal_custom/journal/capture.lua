local data = require("journal_custom.journal.data")
local journalDate = require("journal_custom.util.date")
local logger = require("journal_custom.util.logger")
local text = require("journal_custom.util.text")

local M = {}

local registered = false
local originalAddJournalEntry
local pendingFreeformEntries = {}

-- Journal-derived ids need to be stable and filesystem-safe because they are
-- reused across loads and across freeform capture fallbacks.
local function sanitizeIdSegment(value)
    local normalized = tostring(value or "unknown")
    normalized = normalized:lower()
    normalized = normalized:gsub("[^%w]+", "_")
    normalized = normalized:gsub("_+", "_")
    normalized = normalized:gsub("^_", "")
    normalized = normalized:gsub("_$", "")

    if normalized == "" then
        return "unknown"
    end

    return normalized
end

local function buildEntryId(questId, questIndex)
    return string.format("engine_%s_%04d", sanitizeIdSegment(questId), questIndex)
end

-- Freeform journal text has no quest identity, so derive a deterministic id
-- from the visible text and the current day.
local function buildFreeformEntryId(originalText, daysPassed)
    local baseId = string.format(
        "engine_note_%s_%s",
        sanitizeIdSegment(daysPassed or "unknown"),
        sanitizeIdSegment(text.buildAnchorKey(originalText))
    )
    local candidate = baseId
    local suffix = 2

    while true do
        local existing = data.getEntry(candidate)
        if not existing then
            return candidate
        end

        if existing.originalText == originalText and existing.daysPassed == daysPassed then
            return candidate
        end

        candidate = string.format("%s_%03d", baseId, suffix)
        suffix = suffix + 1
    end
end

-- Convert the HTML-like text coming from tes3.addJournalEntry into the same
-- entry shape used by captured engine updates.
local function buildEntryFromFreeformJournalText(journalText)
    local normalizedText = text.stripBookHtml(journalText)
    if normalizedText == "" then
        return nil
    end

    local currentDate = journalDate.getCurrentDateFields()

    return {
        id = buildFreeformEntryId(normalizedText, currentDate.daysPassed),
        originalText = normalizedText,
        editedText = normalizedText,
        daysPassed = currentDate.daysPassed,
        calendarDay = currentDate.calendarDay,
        calendarMonth = currentDate.calendarMonth,
        calendarYear = currentDate.calendarYear,
        dateCaptured = true,
        dateKey = journalDate.buildDateKey(currentDate),
        displayDate = journalDate.buildDisplayDate(currentDate),
        deleted = false,
    }
end

-- Persist a freeform entry through the same data pipeline used by regular
-- journal events, including date-entry maintenance.
local function persistFreeformEntry(entry)
    if not entry then
        return false
    end

    local existing = data.getEntry(entry.id)
    local persistedEntry = data.upsertEngineEntry(entry)
    data.ensureDateEntryForEntry(persistedEntry.id)
    return existing == nil
end

-- Capture raw engine journal events into the normalized entry model stored by
-- journal_custom.
function M.buildEntryFromJournalEvent(e)
    local questId = e.topic.id
    local questIndex = e.index
    local originalText = e.info.text
    local currentDate = journalDate.getCurrentDateFields()

    return {
        id = buildEntryId(questId, questIndex),
        questId = questId,
        questIndex = questIndex,
        originalText = originalText,
        editedText = originalText,
        daysPassed = currentDate.daysPassed,
        calendarDay = currentDate.calendarDay,
        calendarMonth = currentDate.calendarMonth,
        calendarYear = currentDate.calendarYear,
        dateCaptured = true,
        dateKey = journalDate.buildDateKey(currentDate),
        displayDate = journalDate.buildDisplayDate(currentDate),
        deleted = false,
    }
end

-- Quest-driven journal updates come through tes3.event.journal and are written
-- immediately once a save profile is active.
local function onJournal(e)
    if not data.getProfileKey() then
        logger.warn("Journal event received before journal_custom loaded the save data.")
        return
    end

    local entry = M.buildEntryFromJournalEvent(e)
    local existing = data.getEntry(entry.id)

    local persistedEntry = data.upsertEngineEntry(entry)
    data.ensureDateEntryForEntry(persistedEntry.id)
    data.save()

    if existing then
        logger.info(
            "Journal captured: quest '%s' index %d updated.",
            entry.questId,
            entry.questIndex
        )
    else
        logger.info(
            "Journal captured: quest '%s' index %d recorded.",
            entry.questId,
            entry.questIndex
        )
    end
end

-- Freeform entries created before the save profile is ready are replayed once
-- loading finishes.
local function flushPendingFreeformEntries()
    if #pendingFreeformEntries == 0 or not data.getProfileKey() then
        return 0
    end

    local createdCount = 0

    for _, entry in ipairs(pendingFreeformEntries) do
        if persistFreeformEntry(entry) then
            createdCount = createdCount + 1
        end
    end

    pendingFreeformEntries = {}
    data.save()
    logger.info("Freeform journal captured after load: %d entries recorded.", createdCount)
    return createdCount
end

-- Hook tes3.addJournalEntry so freeform notes added by code are mirrored into
-- the custom journal state.
local function wrapAddJournalEntry()
    if originalAddJournalEntry then
        return
    end

    originalAddJournalEntry = tes3.addJournalEntry
    rawset(tes3, "addJournalEntry", function(params)
        originalAddJournalEntry(params)

        local entry = buildEntryFromFreeformJournalText(params and params.text)
        if not entry then
            return
        end

        if not data.getProfileKey() then
            pendingFreeformEntries[#pendingFreeformEntries + 1] = entry
            return
        end

        local created = persistFreeformEntry(entry)
        data.save()

        if created then
            logger.info("Freeform journal captured through addJournalEntry: '%s'.", entry.id)
        else
            logger.debug("Freeform journal already existed through addJournalEntry: '%s'.", entry.id)
        end
    end)
end

function M.flushPendingEntries()
    return flushPendingFreeformEntries()
end

-- Register the capture layer only once for the whole session.
function M.register()
    if registered then
        return
    end

    event.register(tes3.event.journal, onJournal)
    wrapAddJournalEntry()
    registered = true
end

return M
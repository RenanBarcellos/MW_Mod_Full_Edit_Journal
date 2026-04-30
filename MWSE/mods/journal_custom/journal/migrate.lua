local data = require("journal_custom.journal.data")
local logger = require("journal_custom.util.logger")

local SAVE_BATCH_SIZE = 25

local M = {}

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

local function buildEntryFromInfo(dialogue, info)
    if not dialogue or dialogue.type ~= tes3.dialogueType.journal then
        return nil
    end

    local questIndex = info.journalIndex
    if type(questIndex) ~= "number" or questIndex <= 0 then
        return nil
    end

    if info.isQuestName then
        return nil
    end

    local originalText = info.text
    if type(originalText) ~= "string" or originalText == "" then
        return nil
    end

    return {
        id = buildEntryId(dialogue.id, questIndex),
        questId = dialogue.id,
        questIndex = questIndex,
        originalText = originalText,
        editedText = originalText,
        daysPassed = nil,
        deleted = false,
    }
end

local function getStartedQuests()
    local worldController = tes3.worldController
    if not worldController or not worldController.quests then
        return {}
    end

    local quests = {}

    for _, quest in ipairs(worldController.quests) do
        if quest.isStarted then
            quests[#quests + 1] = quest
        end
    end

    table.sort(quests, function(left, right)
        return tostring(left.id or "") < tostring(right.id or "")
    end)

    return quests
end

local function importInfoForDialogue(dialogue, info)
    local sourceDialogue = info:findDialogue()
    if not sourceDialogue or sourceDialogue.id ~= dialogue.id then
        return false
    end

    local entry = buildEntryFromInfo(dialogue, info)
    if not entry then
        return false
    end

    local existing = data.getEntry(entry.id)
    data.upsertEngineEntry(entry)
    return existing == nil
end

function M.needsMigration(state)
    local loadedState = state or data.getState()
    return loadedState.migrationDone ~= true
end

function M.importDialogue(dialogue)
    if not dialogue or dialogue.type ~= tes3.dialogueType.journal then
        return 0, 0
    end

    local quest = tes3.findQuest({ journal = dialogue })
    if not quest or not quest.isStarted then
        return 0, 0
    end

    local importedCount = 0
    local touchedCount = 0

    for _, info in ipairs(quest.info or {}) do
        local created = importInfoForDialogue(dialogue, info)
        if created ~= false then
            touchedCount = touchedCount + 1
            if created then
                importedCount = importedCount + 1
            end
        end
    end

    return importedCount, touchedCount
end

function M.run()
    local state = data.getState()
    if not M.needsMigration(state) then
        logger.debug("Migration skipped for save '%s': already completed.", data.getProfileKey())
        return {
            imported = 0,
            touched = 0,
            alreadyDone = true,
        }
    end

    logger.info("Starting journal migration for save '%s'.", data.getProfileKey())

    local totalImported = 0
    local totalTouched = 0
    local pendingSave = 0

    for _, quest in ipairs(getStartedQuests()) do
        for _, dialogue in ipairs(quest.dialogue or {}) do
            local importedCount, touchedCount = M.importDialogue(dialogue)
            totalImported = totalImported + importedCount
            totalTouched = totalTouched + touchedCount
            pendingSave = pendingSave + touchedCount

            if pendingSave >= SAVE_BATCH_SIZE then
                data.save()
                pendingSave = 0
            end
        end
    end

    state.migrationDone = true
    data.save()

    logger.info(
        "Migration completed for save '%s': %d active entries processed, %d new entries imported.",
        data.getProfileKey(),
        totalTouched,
        totalImported
    )

    return {
        imported = totalImported,
        touched = totalTouched,
        alreadyDone = false,
    }
end

return M
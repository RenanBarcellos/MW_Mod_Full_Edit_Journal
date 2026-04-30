local logger = require("journal_custom.util.logger")
local journalDate = require("journal_custom.util.date")

local legacyDataRoot = "journal_custom\\journal"
local saveDataKey = "journal_custom"
local saveDataPath = "tes3.player.data.journal_custom"
local CUSTOM_ORDER_GAP = 1024
local ENTRY_TYPE_NOTE = "note"
local ENTRY_TYPE_DATE = "date"
local DATE_KIND_AUTO = "auto"
local DATE_KIND_MANUAL = "manual"
local currentProfileKey
local state
local dirty = false

local M = {}

-- Deep-copy persisted journal data so runtime mutations never share nested
-- tables with the save snapshot or default values.
local function clone(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}

    for key, nestedValue in pairs(value) do
        copy[key] = clone(nestedValue)
    end

    return copy
end

local function getPersistentDefaults()
    return {
        schemaVersion = 1,
        migrationDone = false,
        viewMode = "diary",
        entries = {},
    }
end

-- Fill missing keys without overwriting values that were already loaded from
-- the save or from a legacy config file.
local function ensureDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = clone(value)
        elseif type(target[key]) == "table" and type(value) == "table" then
            ensureDefaults(target[key], value)
        end
    end

    return target
end

-- Extend persisted data with transient state used only while the game session
-- is running.
local function initializeRuntimeState(persistedState)
    local runtimeState = ensureDefaults(clone(persistedState or {}), getPersistentDefaults())
    runtimeState.selectedEntryId = nil
    runtimeState.lastSearch = ""
    runtimeState.pageCache = {}
    return runtimeState
end

-- Build a filesystem-safe identifier for legacy per-save config files.
local function sanitizeProfileKey(profileKey)
    local normalized = tostring(profileKey or "default")
    normalized = normalized:gsub("[<>:\"/\\|%?%*]", "_")
    normalized = normalized:gsub("%s+", "_")
    normalized = normalized:gsub("_+", "_")
    normalized = normalized:gsub("^_", "")
    normalized = normalized:gsub("_$", "")

    if normalized == "" then
        return "default"
    end

    return normalized:lower()
end

local function buildLegacyDataPath(profileKey)
    return string.format("%s\\%s", legacyDataRoot, sanitizeProfileKey(profileKey))
end

local function requirePlayerData()
    local player = tes3.player
    if not player or not player.supportsLuaData then
        error("journal_custom.journal.data requires tes3.player with Lua data support.")
    end

    return player.data, player
end

local function loadPersistedStateFromSave()
    local playerData = requirePlayerData()
    local persistedState = playerData[saveDataKey]
    if type(persistedState) ~= "table" then
        return nil
    end

    return ensureDefaults(clone(persistedState), getPersistentDefaults())
end

-- Legacy configs are still imported once so older saves can migrate into the
-- new Lua data storage model.
local function loadLegacyState(profileKey)
    local legacyPath = buildLegacyDataPath(profileKey)
    local loadedState = mwse.loadConfig(legacyPath, {})

    if type(loadedState) ~= "table" or next(loadedState) == nil then
        return nil, nil
    end

    if loadedState.entries == nil and loadedState.migrationDone == nil and loadedState.schemaVersion == nil then
        return nil, nil
    end

    return ensureDefaults(clone(loadedState), getPersistentDefaults()), legacyPath
end

-- Strip runtime-only fields before syncing the journal back into player data.
local function buildPersistentSnapshot(runtimeState)
    local defaults = getPersistentDefaults()
    return {
        schemaVersion = tonumber(runtimeState.schemaVersion) or defaults.schemaVersion,
        migrationDone = runtimeState.migrationDone == true,
        viewMode = runtimeState.viewMode or defaults.viewMode,
        entries = clone(runtimeState.entries or {}),
    }
end

-- Update the existing Lua data table in place so MWSE keeps the table shape it
-- expects inside tes3.player.data.
local function syncLuaDataTable(target, source)
    for key in pairs(target) do
        if source[key] == nil then
            target[key] = nil
        end
    end

    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            syncLuaDataTable(target[key], value)
        else
            target[key] = value
        end
    end
end

local function requireLoadedState()
    if not state then
        error("journal_custom.journal.data was used before load().")
    end

    return state
end

-- Date entries act like structural separators in the custom journal, so many
-- features branch on this check.
local function isDateEntry(entry)
    return type(entry) == "table" and entry.entryType == ENTRY_TYPE_DATE
end

local function getDateKind(entry)
    if not isDateEntry(entry) then
        return nil
    end

    if entry.dateKind == DATE_KIND_MANUAL then
        return DATE_KIND_MANUAL
    end

    if entry.dateKind == DATE_KIND_AUTO or entry.dateKey ~= nil then
        return DATE_KIND_AUTO
    end

    return DATE_KIND_MANUAL
end

-- Only notes with a captured world date are eligible for automatic date-entry
-- grouping.
local function isCapturedDatedNote(entry)
    return type(entry) == "table"
        and isDateEntry(entry) ~= true
        and entry.dateCaptured == true
        and journalDate.hasWorldDate(entry)
        and journalDate.buildDateKey(entry) ~= nil
end

local function clearCapturedDateMetadata(entry)
    entry.calendarDay = nil
    entry.calendarMonth = nil
    entry.calendarYear = nil
    entry.dateCaptured = nil
    entry.dateKey = nil
end

-- Custom ordering uses gaps so new notes can be inserted between existing
-- entries without renumbering the entire journal every time.
local function getEntryOrderValue(entry, fallbackIndex)
    if type(entry.customOrder) == "number" then
        return entry.customOrder
    end

    return fallbackIndex * CUSTOM_ORDER_GAP
end

local function hasInitializedCustomOrder()
    for _, entry in pairs(requireLoadedState().entries or {}) do
        if type(entry) == "table" and entry.deleted ~= true and type(entry.customOrder) == "number" then
            return true
        end
    end

    return false
end

local function getHighestCustomOrder()
    local highestOrder

    for _, entry in pairs(requireLoadedState().entries or {}) do
        if type(entry) == "table" and entry.deleted ~= true and type(entry.customOrder) == "number" then
            if not highestOrder or entry.customOrder > highestOrder then
                highestOrder = entry.customOrder
            end
        end
    end

    return highestOrder
end

local function findAutoDateEntryByKey(dateKey)
    if type(dateKey) ~= "string" or dateKey == "" then
        return nil
    end

    for _, entry in pairs(requireLoadedState().entries or {}) do
        if isDateEntry(entry) and getDateKind(entry) == DATE_KIND_AUTO and entry.dateKey == dateKey then
            return entry
        end
    end

    return nil
end

-- Normalize legacy or partially migrated date-entry state before the runtime
-- starts using it for rendering and ordering.
local function normalizeLoadedDateState(loadedState)
    local entries = loadedState.entries or {}
    local validAutoDateKeys = {}
    local changed = false

    for _, entry in pairs(entries) do
        if type(entry) == "table" then
            if isDateEntry(entry) then
                local resolvedDateKind = getDateKind(entry)
                if entry.dateKind ~= resolvedDateKind then
                    entry.dateKind = resolvedDateKind
                    changed = true
                end

                if resolvedDateKind == DATE_KIND_MANUAL then
                    local manualLabel = journalDate.normalizeLabel(entry.dateLabelOverride)
                    if manualLabel == "" then
                        manualLabel = journalDate.normalizeLabel(entry.editedText or entry.displayDate or entry.originalText)
                        if manualLabel ~= "" then
                            entry.dateLabelOverride = manualLabel
                            changed = true
                        end
                    end
                end
            elseif isCapturedDatedNote(entry) then
                local expectedDateKey = journalDate.buildDateKey(entry)
                if entry.dateKey ~= expectedDateKey then
                    entry.dateKey = expectedDateKey
                    changed = true
                end

                if expectedDateKey then
                    validAutoDateKeys[expectedDateKey] = true
                end
            else
                if entry.calendarDay ~= nil
                    or entry.calendarMonth ~= nil
                    or entry.calendarYear ~= nil
                    or entry.dateCaptured ~= nil
                    or entry.dateKey ~= nil
                then
                    clearCapturedDateMetadata(entry)
                    changed = true
                end
            end
        end
    end

    for entryId, entry in pairs(entries) do
        if isDateEntry(entry) and getDateKind(entry) == DATE_KIND_AUTO then
            local dateKey = entry.dateKey
            if not dateKey or not validAutoDateKeys[dateKey] then
                entries[entryId] = nil
                changed = true
            end
        end
    end

    return changed
end

-- Validate and normalize every entry that enters the data store so downstream
-- modules can rely on a consistent shape.
local function validateEntry(entry)
    if type(entry) ~= "table" then
        error("invalid entry: expected table.")
    end

    if type(entry.id) ~= "string" or entry.id == "" then
        error("invalid entry: id is required.")
    end

    entry.entryType = entry.entryType == ENTRY_TYPE_DATE and ENTRY_TYPE_DATE or ENTRY_TYPE_NOTE
    if isDateEntry(entry) then
        entry.dateKind = getDateKind(entry)
    else
        entry.dateKind = nil
    end

    if entry.source == nil and isDateEntry(entry) then
        entry.source = "player"
    end

    if entry.source ~= "engine" and entry.source ~= "player" then
        error("invalid entry: source must be 'engine' or 'player'.")
    end

    if not isDateEntry(entry) and entry.dateCaptured ~= true then
        entry.dateCaptured = nil
        entry.dateKey = nil
        entry.calendarDay = nil
        entry.calendarMonth = nil
        entry.calendarYear = nil
    elseif not isDateEntry(entry) and entry.dateKey == nil then
        entry.dateKey = journalDate.buildDateKey(entry)
    end

    if isDateEntry(entry) then
        local label = journalDate.resolveEntryDateLabel(entry)
        entry.originalText = label
        entry.editedText = label
        entry.displayDate = label
    else
        if entry.displayDate == nil then
            entry.displayDate = entry.source == "player" and "Note" or "Journal entry"
        end

        if entry.editedText == nil then
            entry.editedText = entry.originalText or ""
        end
    end

    if entry.deleted == nil then
        entry.deleted = false
    end

    return entry
end

-- Player-created entries use generated ids because they are not backed by a
-- quest id + index pair from the engine.
local function generateEntryId(prefix)
    local entries = requireLoadedState().entries
    local index = 1

    while true do
        local candidate = string.format("%s_%03d", prefix, index)
        if entries[candidate] == nil then
            return candidate
        end
        index = index + 1
    end
end

-- All entry writes flow through one helper so validation stays centralized.
local function upsertEntry(entry)
    local loadedState = requireLoadedState()
    loadedState.entries[entry.id] = validateEntry(entry)
    return loadedState.entries[entry.id]
end

local function findRenderableEntryIndex(entries, entryId)
    for index, entry in ipairs(entries or {}) do
        if entry.id == entryId then
            return index
        end
    end

    return nil
end

local function resolveInsertOrderAfter(renderableEntries, afterEntryId)
    if #renderableEntries == 0 then
        return CUSTOM_ORDER_GAP
    end

    local insertAfterIndex = findRenderableEntryIndex(renderableEntries, afterEntryId)
    if not insertAfterIndex then
        return getEntryOrderValue(renderableEntries[#renderableEntries], #renderableEntries) + CUSTOM_ORDER_GAP
    end

    local afterEntry = renderableEntries[insertAfterIndex]
    local nextEntry = renderableEntries[insertAfterIndex + 1]
    local afterOrder = getEntryOrderValue(afterEntry, insertAfterIndex)
    local nextOrder = nextEntry and getEntryOrderValue(nextEntry, insertAfterIndex + 1) or (afterOrder + CUSTOM_ORDER_GAP)
    return afterOrder + ((nextOrder - afterOrder) / 2)
end

local function resolveInsertOrderBefore(renderableEntries, beforeEntryId)
    if #renderableEntries == 0 then
        return CUSTOM_ORDER_GAP
    end

    local insertBeforeIndex = findRenderableEntryIndex(renderableEntries, beforeEntryId)
    if not insertBeforeIndex then
        return getEntryOrderValue(renderableEntries[#renderableEntries], #renderableEntries) + CUSTOM_ORDER_GAP
    end

    local beforeEntry = renderableEntries[insertBeforeIndex]
    local beforeOrder = getEntryOrderValue(beforeEntry, insertBeforeIndex)
    if insertBeforeIndex == 1 then
        return beforeOrder / 2
    end

    local previousEntry = renderableEntries[insertBeforeIndex - 1]
    local previousOrder = getEntryOrderValue(previousEntry, insertBeforeIndex - 1)
    return previousOrder + ((beforeOrder - previousOrder) / 2)
end

local function compareEntriesLegacy(left, right)
    local leftDays = type(left.daysPassed) == "number" and left.daysPassed or math.huge
    local rightDays = type(right.daysPassed) == "number" and right.daysPassed or math.huge
    if leftDays ~= rightDays then
        return leftDays < rightDays
    end

    local leftIsDate = isDateEntry(left)
    local rightIsDate = isDateEntry(right)
    if leftIsDate ~= rightIsDate then
        return leftIsDate
    end

    local leftSource = tostring(left.source or "")
    local rightSource = tostring(right.source or "")
    if leftSource ~= rightSource then
        return leftSource < rightSource
    end

    local leftQuestId = tostring(left.questId or left.displayDate or "")
    local rightQuestId = tostring(right.questId or right.displayDate or "")
    if leftQuestId ~= rightQuestId then
        return leftQuestId < rightQuestId
    end

    local leftQuestIndex = type(left.questIndex) == "number" and left.questIndex or math.huge
    local rightQuestIndex = type(right.questIndex) == "number" and right.questIndex or math.huge
    if leftQuestIndex ~= rightQuestIndex then
        return leftQuestIndex < rightQuestIndex
    end

    return tostring(left.id or "") < tostring(right.id or "")
end

-- Custom order wins when present; legacy chronological order remains the
-- fallback for older or partially initialized data.
local function compareEntries(left, right)
    local leftOrder = type(left.customOrder) == "number" and left.customOrder or nil
    local rightOrder = type(right.customOrder) == "number" and right.customOrder or nil

    if leftOrder ~= nil and rightOrder ~= nil and leftOrder ~= rightOrder then
        return leftOrder < rightOrder
    end

    return compareEntriesLegacy(left, right)
end

-- Renderable entries are the non-deleted subset, optionally sorted by custom
-- order when that feature has been initialized.
local function collectRenderableEntries(useCustomOrder)
    local loadedState = requireLoadedState()
    local list = {}

    for _, entry in pairs(loadedState.entries or {}) do
        if type(entry) == "table" and entry.deleted ~= true then
            list[#list + 1] = entry
        end
    end

    table.sort(list, useCustomOrder and compareEntries or compareEntriesLegacy)
    return list
end

-- Assign evenly spaced ordering values so later inserts can land between two
-- existing entries without renumbering everything immediately.
local function assignSequentialCustomOrder(entries)
    for index, entry in ipairs(entries or {}) do
        entry.customOrder = index * CUSTOM_ORDER_GAP
    end

    dirty = true
end

-- Load journal state from Lua data first, then fall back to the legacy config
-- format for one-time migration support.
function M.load(profileKey)
    currentProfileKey = sanitizeProfileKey(profileKey)
    local persistedState = loadPersistedStateFromSave()
    local source = "save"

    if not persistedState then
        local legacyState, legacyPath = loadLegacyState(currentProfileKey)
        if legacyState then
            persistedState = legacyState
            dirty = true
            source = string.format("legacy:%s", legacyPath)
            logger.info(
                "Legacy journal data found for '%s' and will be migrated into the save on the next write.",
                currentProfileKey
            )
        else
            persistedState = getPersistentDefaults()
            dirty = false
            source = "new"
        end
    else
        dirty = false
    end

    state = initializeRuntimeState(persistedState)
    if normalizeLoadedDateState(state) then
        dirty = true
    end
    local insertedDateEntries = M.ensureDateEntriesInitialized()
    if insertedDateEntries > 0 then
        logger.info("Date entries initialized for save '%s': %d.", currentProfileKey, insertedDateEntries)
    end
    logger.debug("Journal data loaded for '%s' (%s).", currentProfileKey, source)
    return state
end

function M.save()
    requireLoadedState()
    dirty = true
    logger.debug(
        "Journal data marked as changed in the in-memory state for save '%s'.",
        tostring(currentProfileKey)
    )
    return state
end

-- Push the persisted snapshot into tes3.player.data right before the game save
-- is written.
function M.flush(saveFilename)
    local loadedState = requireLoadedState()
    if saveFilename ~= nil then
        currentProfileKey = sanitizeProfileKey(saveFilename)
    end

    if not dirty then
        return loadedState, false
    end

    local playerData, player = requirePlayerData()
    if type(playerData[saveDataKey]) ~= "table" then
        playerData[saveDataKey] = {}
    end

    syncLuaDataTable(playerData[saveDataKey], buildPersistentSnapshot(loadedState))
    player.modified = true
    dirty = false
    logger.debug("Journal data prepared to persist inside save '%s'.", currentProfileKey)
    return loadedState, true
end

function M.isDirty()
    return dirty == true
end

function M.getState()
    return requireLoadedState()
end

function M.getProfileKey()
    return currentProfileKey
end

function M.getDataPath()
    return saveDataPath
end

function M.getEntry(id)
    return requireLoadedState().entries[id]
end

function M.getEntries()
    return requireLoadedState().entries
end

-- Engine entries preserve user edits and visibility flags if the same quest
-- step is captured again later.
function M.upsertEngineEntry(entry)
    entry.source = "engine"
    entry.dateCaptured = entry.dateCaptured == true and journalDate.hasWorldDate(entry) or false
    entry.dateKey = entry.dateCaptured and journalDate.buildDateKey(entry) or nil

    local existing = M.getEntry(entry.id)
    if existing then
        entry.editedText = existing.editedText or entry.editedText or entry.originalText or ""
        entry.deleted = existing.deleted == true
        entry.customOrder = existing.customOrder
        entry.tags = existing.tags or entry.tags
        entry.lastKnownPage = existing.lastKnownPage
        entry.entryType = existing.entryType or entry.entryType
        entry.displayDate = existing.displayDate or entry.displayDate
        if existing.dateCaptured == true then
            entry.dateCaptured = true
            entry.dateKey = existing.dateKey or entry.dateKey
            entry.calendarDay = existing.calendarDay or entry.calendarDay
            entry.calendarMonth = existing.calendarMonth or entry.calendarMonth
            entry.calendarYear = existing.calendarYear or entry.calendarYear
        end
    elseif hasInitializedCustomOrder() then
        entry.customOrder = (getHighestCustomOrder() or 0) + CUSTOM_ORDER_GAP
    end

    return upsertEntry(entry)
end

-- Player-created notes and date entries share one constructor so persistence,
-- ordering, and defaults stay consistent.
function M.createPlayerEntry(params)
    local entryType = params.entryType == ENTRY_TYPE_DATE and ENTRY_TYPE_DATE or ENTRY_TYPE_NOTE
    local dateKind = params.dateKind == DATE_KIND_AUTO and DATE_KIND_AUTO or DATE_KIND_MANUAL
    local dateCaptured = entryType ~= ENTRY_TYPE_DATE and params.dateCaptured == true and journalDate.hasWorldDate(params) or nil
    local displayDate = params.displayDate
    if displayDate == nil then
        if entryType == ENTRY_TYPE_DATE then
            displayDate = journalDate.resolveEntryDateLabel(params)
        else
            displayDate = params.source == "player" and "Note" or "Journal entry"
        end
    end

    local originalText = params.originalText or params.editedText or ""
    local editedText = params.editedText or params.originalText or ""
    if entryType == ENTRY_TYPE_DATE then
        local label = journalDate.normalizeLabel(displayDate)
        if label == "" then
            label = journalDate.buildDisplayDate(params)
        end
        originalText = label
        editedText = label
        displayDate = label
    end

    local entry = {
        id = params.id or generateEntryId("player"),
        questId = params.questId,
        questIndex = params.questIndex,
        originalText = originalText,
        editedText = editedText,
        displayDate = displayDate,
        daysPassed = params.daysPassed,
        calendarDay = (entryType == ENTRY_TYPE_DATE or dateCaptured == true) and params.calendarDay or nil,
        calendarMonth = (entryType == ENTRY_TYPE_DATE or dateCaptured == true) and params.calendarMonth or nil,
        calendarYear = (entryType == ENTRY_TYPE_DATE or dateCaptured == true) and params.calendarYear or nil,
        dateCaptured = dateCaptured == true,
        dateKey = params.dateKey or ((entryType == ENTRY_TYPE_DATE or dateCaptured == true) and journalDate.buildDateKey(params) or nil),
        dateKind = entryType == ENTRY_TYPE_DATE and dateKind or nil,
        dateLabelOverride = params.dateLabelOverride,
        entryType = entryType,
        source = params.source or "player",
        deleted = params.deleted or false,
        customOrder = params.customOrder,
        tags = params.tags or {},
        lastKnownPage = params.lastKnownPage,
    }

    return upsertEntry(entry)
end

-- Insert a new player entry after the chosen anchor using the current custom
-- order gaps.
function M.createPlayerEntryAfter(afterEntryId, params)
    M.ensureCustomOrderInitialized()

    local renderableEntries = collectRenderableEntries(true)
    local customOrder = resolveInsertOrderAfter(renderableEntries, afterEntryId)

    local entryParams = clone(params or {})
    entryParams.customOrder = customOrder
    return M.createPlayerEntry(entryParams)
end

-- Insert a new player entry before the chosen anchor using the current custom
-- order gaps.
function M.createPlayerEntryBefore(beforeEntryId, params)
    M.ensureCustomOrderInitialized()

    local renderableEntries = collectRenderableEntries(true)
    local customOrder = resolveInsertOrderBefore(renderableEntries, beforeEntryId)

    local entryParams = clone(params or {})
    entryParams.customOrder = customOrder
    return M.createPlayerEntry(entryParams)
end

-- Date entries are specialized player entries with stricter label handling.
function M.createDateEntry(params)
    local entryParams = clone(params or {})
    entryParams.entryType = ENTRY_TYPE_DATE
    entryParams.dateKind = entryParams.dateKind or DATE_KIND_MANUAL
    entryParams.source = entryParams.source or "player"
    return M.createPlayerEntry(entryParams)
end

function M.createDateEntryAfter(afterEntryId, params)
    local entryParams = clone(params or {})
    entryParams.entryType = ENTRY_TYPE_DATE
    entryParams.source = entryParams.source or "player"
    return M.createPlayerEntryAfter(afterEntryId, entryParams)
end

function M.createDateEntryBefore(beforeEntryId, params)
    local entryParams = clone(params or {})
    entryParams.entryType = ENTRY_TYPE_DATE
    entryParams.source = entryParams.source or "player"
    return M.createPlayerEntryBefore(beforeEntryId, entryParams)
end

-- Editing a date entry updates the resolved label fields, while regular entries
-- only replace editedText.
function M.updateEditedText(id, text)
    local entry = M.getEntry(id)
    if not entry then
        return nil
    end

    if isDateEntry(entry) then
        local normalizedLabel = journalDate.normalizeLabel(text)
        if getDateKind(entry) == DATE_KIND_AUTO and normalizedLabel == "" then
            entry.dateLabelOverride = nil
        else
            entry.dateLabelOverride = normalizedLabel ~= "" and normalizedLabel or nil
        end

        local label = journalDate.resolveEntryDateLabel(entry)
        entry.originalText = label
        entry.editedText = label
        entry.displayDate = label
    else
        entry.editedText = text
    end

    return entry
end

function M.markDeleted(id, deleted)
    local entry = M.getEntry(id)
    if not entry then
        return nil
    end

    entry.deleted = deleted ~= false
    return entry
end

function M.setCustomOrder(id, order)
    local entry = M.getEntry(id)
    if not entry then
        return nil
    end

    entry.customOrder = order
    return entry
end

function M.setLastKnownPage(id, page)
    local entry = M.getEntry(id)
    if not entry then
        return nil
    end

    entry.lastKnownPage = page
    return entry
end

function M.setSelectedEntry(id)
    local loadedState = requireLoadedState()
    loadedState.selectedEntryId = id
    return loadedState.selectedEntryId
end

function M.getRenderableEntries()
    return collectRenderableEntries(true)
end

function M.isDateEntry(value)
    if type(value) == "string" then
        return isDateEntry(M.getEntry(value))
    end

    return isDateEntry(value)
end

-- Automatic date entries are created lazily the first time a dated note for a
-- given calendar day appears.
function M.ensureDateEntryForEntry(entryId)
    local entry = M.getEntry(entryId)
    if not entry or entry.deleted == true or isDateEntry(entry) or not isCapturedDatedNote(entry) then
        return nil, false
    end

    local dateKey = entry.dateKey or journalDate.buildDateKey(entry)
    if not dateKey then
        return nil, false
    end

    local existing = findAutoDateEntryByKey(dateKey)
    if existing then
        return existing, false
    end

    local label = journalDate.buildDisplayDate(entry)
    local created = M.createDateEntryBefore(entry.id, {
        dateKind = DATE_KIND_AUTO,
        displayDate = label,
        originalText = label,
        editedText = label,
        daysPassed = entry.daysPassed,
        calendarDay = entry.calendarDay,
        calendarMonth = entry.calendarMonth,
        calendarYear = entry.calendarYear,
        dateKey = dateKey,
    })

    return created, created ~= nil
end

-- Rebuild missing automatic date entries for older saves or newly migrated
-- journal data.
function M.ensureDateEntriesInitialized()
    local renderableEntries = collectRenderableEntries(false)
    if #renderableEntries == 0 then
        return 0
    end

    M.ensureCustomOrderInitialized()

    local orderedEntries = collectRenderableEntries(true)
    local seenDateKeys = {}
    local pendingDates = {}

    for _, entry in ipairs(orderedEntries) do
        local dateKey = isCapturedDatedNote(entry) and (entry.dateKey or journalDate.buildDateKey(entry)) or nil
        if dateKey and not seenDateKeys[dateKey] then
            pendingDates[#pendingDates + 1] = {
                anchorId = entry.id,
                calendarDay = entry.calendarDay,
                calendarMonth = entry.calendarMonth,
                calendarYear = entry.calendarYear,
                dateKey = dateKey,
                dateKind = DATE_KIND_AUTO,
                daysPassed = entry.daysPassed,
                displayDate = journalDate.buildDisplayDate(entry),
            }
            seenDateKeys[dateKey] = true
        end
    end

    local createdCount = 0
    for _, pendingDate in ipairs(pendingDates) do
        if not findAutoDateEntryByKey(pendingDate.dateKey) then
            M.createDateEntryBefore(pendingDate.anchorId, pendingDate)
            createdCount = createdCount + 1
        end
    end

    if createdCount > 0 then
        M.save()
    end

    return createdCount
end

-- Initialize custom order only when the current data shape needs it.
function M.ensureCustomOrderInitialized()
    local renderableEntries = collectRenderableEntries(false)
    local seen = {}
    local needsInitialization = false

    for _, entry in ipairs(renderableEntries) do
        local customOrder = entry.customOrder
        if type(customOrder) ~= "number" or seen[customOrder] then
            needsInitialization = true
            break
        end
        seen[customOrder] = true
    end

    if not needsInitialization then
        return false
    end

    assignSequentialCustomOrder(renderableEntries)
    return true
end

-- Debug seeding gives the save a known local entry that proves save-scoped
-- persistence is working.
function M.ensureDebugSeedEntry()
    local loadedState = requireLoadedState()
    local existing = loadedState.entries.debug_seed_note

    if existing then
        return existing, false
    end

    local created = M.createPlayerEntry({
        id = "debug_seed_note",
        editedText = "Debug note created automatically to validate local journal_custom persistence.",
        displayDate = "Debug",
        tags = { "debug" },
    })

    M.save()
    return created, true
end

-- Input and mapping consume ordered ids without needing full entry tables.
function M.getOrderedEntryIds()
    local list = collectRenderableEntries(true)

    local ids = {}
    for _, entry in ipairs(list) do
        ids[#ids + 1] = entry.id
    end

    return ids
end

return M
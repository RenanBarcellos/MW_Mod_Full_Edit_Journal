local configPath = "journal_custom\\config"
local currentSchemaVersion = 3

local legacyFeatureDefaultsV2 = {
    debugLogging = true,
    enableVanillaJournalBlock = false,
    enableBookMode = false,
    enableMigration = false,
    enableSelection = false,
    enableEditMode = true,
    enableSearch = false,
    enableCustomOrder = false,
    syncPlayerNotesToVanilla = false,
}

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

local function matchesFeatureDefaults(featureFlags, expectedFlags)
    if type(featureFlags) ~= "table" then
        return false
    end

    for key, value in pairs(expectedFlags or {}) do
        if featureFlags[key] ~= value then
            return false
        end
    end

    return true
end

local function buildDefaultShortcuts()
    return {
        cancelModal = {
            isAltDown = false,
            isControlDown = false,
            isShiftDown = false,
            keyCode = tes3.scanCode.escape,
        },
        createDate = {
            isAltDown = false,
            isControlDown = false,
            isShiftDown = true,
            keyCode = tes3.scanCode.d,
        },
        createNote = {
            isAltDown = false,
            isControlDown = false,
            isShiftDown = true,
            keyCode = tes3.scanCode.n,
        },
        editEntry = {
            isAltDown = false,
            isControlDown = false,
            isShiftDown = false,
            keyCode = tes3.scanCode.enter,
        },
        help = {
            isAltDown = false,
            isControlDown = false,
            isShiftDown = false,
            keyCode = tes3.scanCode.h,
        },
        saveModal = {
            isAltDown = false,
            isControlDown = true,
            isShiftDown = false,
            keyCode = tes3.scanCode.enter,
        },
    }
end

local defaults = {
    schemaVersion = currentSchemaVersion,
    settings = {
        shortcuts = buildDefaultShortcuts(),
    },
    featureFlags = {
        debugLogging = false,
        enableVanillaJournalBlock = true,
        enableBookMode = true,
        enableMigration = false,
        enableSelection = true,
        enableEditMode = true,
        enableSearch = false,
        enableCustomOrder = false,
        syncPlayerNotesToVanilla = false,
    },
}

local state

local M = {}

local function migrateLoadedState(loadedState)
    local resolvedState = loadedState or M.getDefaults()
    local schemaVersion = tonumber(resolvedState.schemaVersion) or 1

    resolvedState.settings = resolvedState.settings or {}
    resolvedState.featureFlags = resolvedState.featureFlags or {}

    if schemaVersion < 2 then
        resolvedState.featureFlags.enableEditMode = true
    end

    if schemaVersion < 3 and matchesFeatureDefaults(resolvedState.featureFlags, legacyFeatureDefaultsV2) then
        resolvedState.featureFlags = clone(defaults.featureFlags)
    end

    ensureDefaults(resolvedState, M.getDefaults())
    resolvedState.schemaVersion = currentSchemaVersion
    return resolvedState
end

function M.getDefaults()
    return clone(defaults)
end

function M.load()
    state = mwse.loadConfig(configPath, M.getDefaults())
    state = migrateLoadedState(state)
    mwse.saveConfig(configPath, state)
    return state
end

function M.reload()
    state = nil
    return M.load()
end

function M.get()
    if not state then
        return M.load()
    end

    return state
end

function M.save(newState)
    state = newState or M.get()
    mwse.saveConfig(configPath, state)
    return state
end

return M
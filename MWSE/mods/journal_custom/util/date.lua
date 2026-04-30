local text = require("journal_custom.util.text")

local M = {}

local MONTH_GMSTS = {
    tes3.gmst.sMonthMorningstar,
    tes3.gmst.sMonthSunsdawn,
    tes3.gmst.sMonthFirstseed,
    tes3.gmst.sMonthRainshand,
    tes3.gmst.sMonthSecondseed,
    tes3.gmst.sMonthMidyear,
    tes3.gmst.sMonthSunsheight,
    tes3.gmst.sMonthLastseed,
    tes3.gmst.sMonthHeartfire,
    tes3.gmst.sMonthFrostfall,
    tes3.gmst.sMonthSunsdusk,
    tes3.gmst.sMonthEveningstar,
}

-- Some world date values come from engine globals that may be missing during
-- early load phases, so guard those reads carefully.
local function getGlobalValue(globalVariable)
    if globalVariable == nil then
        return nil
    end

    local ok, value = pcall(function()
        return globalVariable.value
    end)
    if not ok then
        return nil
    end

    return tonumber(value)
end

-- Resolve the localized month name through GMSTs instead of hardcoding it.
local function getMonthName(monthIndex)
    local resolvedIndex = tonumber(monthIndex)
    if resolvedIndex == nil then
        return nil
    end

    local gmstId = MONTH_GMSTS[resolvedIndex + 1]
    if not gmstId then
        return nil
    end

    local gmst = tes3.findGMST(gmstId)
    if not gmst or type(gmst.value) ~= "string" or gmst.value == "" then
        return nil
    end

    return gmst.value
end

-- Date labels move through multiple systems, so normalize them before display
-- comparisons or persistence decisions.
function M.normalizeLabel(label)
    local normalized = text.stripJournalMarkup(label or "")
    normalized = text.normalizeWhitespace(normalized)
    return normalized
end

-- Read the current in-world calendar fields from the controller in one place.
function M.getCurrentDateFields()
    local worldController = tes3.worldController
    if not worldController then
        return {}
    end

    return {
        calendarDay = getGlobalValue(worldController.day),
        calendarMonth = getGlobalValue(worldController.month),
        calendarYear = getGlobalValue(worldController.year),
        daysPassed = getGlobalValue(worldController.daysPassed),
    }
end

-- Date-aware features only run when the entry has a complete calendar stamp.
function M.hasWorldDate(value)
    local resolvedValue = value or {}
    return tonumber(resolvedValue.calendarDay or resolvedValue.day) ~= nil
        and tonumber(resolvedValue.calendarMonth or resolvedValue.month) ~= nil
        and tonumber(resolvedValue.calendarYear or resolvedValue.year) ~= nil
end

    -- Use a stable YYYY-MM-DD-style key so automatic date entries can be reused.
function M.buildDateKey(value)
    local resolvedValue = value or {}
    local calendarYear = tonumber(resolvedValue.calendarYear or resolvedValue.year)
    local calendarMonth = tonumber(resolvedValue.calendarMonth or resolvedValue.month)
    local calendarDay = tonumber(resolvedValue.calendarDay or resolvedValue.day)

    if calendarYear and calendarMonth and calendarDay then
        return string.format("%04d-%02d-%02d", calendarYear, calendarMonth + 1, calendarDay)
    end

    return nil
end

-- Build the vanilla-style visible label for dated entries and note headers.
function M.buildWorldDateLabel(value)
    local resolvedValue = value or {}
    local calendarMonth = tonumber(resolvedValue.calendarMonth or resolvedValue.month)
    local calendarDay = tonumber(resolvedValue.calendarDay or resolvedValue.day)
    local daysPassed = tonumber(resolvedValue.daysPassed)

    if calendarMonth == nil or calendarDay == nil then
        return nil
    end

    local monthName = getMonthName(calendarMonth)
    if not monthName then
        return nil
    end

    local daySuffix = ""
    if daysPassed ~= nil then
        daySuffix = string.format(" (Day %d)", math.floor(daysPassed))
    end

    return string.format("%d %s%s", calendarDay, monthName, daySuffix)
end

-- Prefer captured world dates, but fall back to an existing label when the
-- entry came from older data or a manual date entry.
function M.buildDisplayDate(value)
    local resolvedValue = value or {}
    local worldDateLabel = M.buildWorldDateLabel(resolvedValue)

    if worldDateLabel then
        return worldDateLabel
    end

    local existingLabel = M.normalizeLabel(resolvedValue.displayDate)
    if existingLabel ~= "" then
        return existingLabel
    end

    return "Unknown date"
end

-- Manual date entries may override the generated label, so resolve the final
-- visible string in one place.
function M.resolveEntryDateLabel(entry)
    local resolvedEntry = entry or {}
    local overrideLabel = M.normalizeLabel(resolvedEntry.dateLabelOverride)
    if overrideLabel ~= "" then
        return overrideLabel
    end

    local editedText = M.normalizeLabel(resolvedEntry.editedText)
    if resolvedEntry.entryType == "date" and resolvedEntry.dateKind == "manual" and editedText ~= "" then
        return editedText
    end

    local displayDate = M.normalizeLabel(resolvedEntry.displayDate)
    if resolvedEntry.entryType == "date" and resolvedEntry.dateKind == "manual" and displayDate ~= "" then
        return displayDate
    end

    local originalText = M.normalizeLabel(resolvedEntry.originalText)
    if resolvedEntry.entryType == "date" and resolvedEntry.dateKind == "manual" and originalText ~= "" then
        return originalText
    end

    return M.buildDisplayDate(resolvedEntry)
end

return M

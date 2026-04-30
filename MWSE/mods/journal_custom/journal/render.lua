local data = require("journal_custom.journal.data")
local journalDate = require("journal_custom.util.date")
local text = require("journal_custom.util.text")

local M = {}
local DEFAULT_ENTRY_COLOR = "000000"
local DATE_ENTRY_COLOR = "9F0000"
local DATE_ENTRY_EMPTY_TEXT = "(no date)"

-- Keep the renderer's HTML shape simple and deterministic so MenuBook
-- pagination and mapping stay predictable.
local function wrapEntryMarkup(markup, alignment)
    return string.format('<div align="%s">%s</div>', alignment or "left", markup)
end

local function isDateEntry(entry)
    return data.isDateEntry(entry)
end

-- Date entries behave like separators, so they use tighter trailing spacing
-- than regular note entries.
local function buildSpacingAfter(entry, nextEntry)
    if isDateEntry(entry) then
        return '<br>'
    end

    if nextEntry and isDateEntry(nextEntry) then
        return '<br><br>'
    end

    return '<br><br><br>'
end

-- Headers are currently implicit, but the title builder still centralizes the
-- logic used by help text, logging, and future UI labels.
function M.buildHeaderTitle(entry)
    if isDateEntry(entry) then
        return journalDate.resolveEntryDateLabel(entry)
    end

    if entry.source == "engine" then
        if entry.questId and type(entry.questIndex) == "number" then
            return string.format("%s [%d]", tostring(entry.questId), entry.questIndex)
        end

        if entry.displayDate then
            return tostring(entry.displayDate)
        end

        local questId = tostring(entry.questId or "Quest")
        local questIndex = type(entry.questIndex) == "number" and entry.questIndex or 0
        return string.format("%s [%d]", questId, questIndex)
    end

    return tostring(entry.displayDate or "Note")
end

-- Subtitle generation keeps entry metadata phrased consistently anywhere the
-- UI needs a short secondary description.
function M.buildHeaderSubtitle(entry)
    if isDateEntry(entry) then
        return "Date entry"
    end

    if type(entry.daysPassed) == "number" then
        return string.format("Day %d", entry.daysPassed)
    end

    if entry.source == "player" then
        return "Player entry"
    end

    if not entry.questId then
        return "Journal entry"
    end

    return "Recorded entry"
end

-- Date entries render their resolved label, while notes render sanitized body
-- text with line-break rules based on their source.
function M.buildEntryBody(entry)
    if isDateEntry(entry) then
        local label = text.sanitizeBookText(journalDate.resolveEntryDateLabel(entry))
        if label == "" then
            return DATE_ENTRY_EMPTY_TEXT
        end

        return label
    end

    local rawBody = entry.editedText or entry.originalText or ""
    local bodyOptions

    if entry.source == "player" then
        bodyOptions = {
            knownTopics = data.getKnownTopics(),
            preserveSingleLineBreaks = true,
        }
    else
        local preserveJournalMarkup = rawBody:find("@([^#]+)#") ~= nil
        bodyOptions = {
            knownTopics = preserveJournalMarkup and nil or data.getKnownTopics(),
            preserveJournalMarkup = preserveJournalMarkup,
        }
    end

    local body = text.sanitizeBookBodyText(rawBody, bodyOptions)

    if body == "" then
        return "(no text)"
    end

    return body
end

function M.renderHeader(entry, context)
    local _, _ = entry, context
    return ""
end

function M.renderEntry(entry, context)
    local header = M.renderHeader(entry, context)
    local body = M.buildEntryBody(entry)
    local _ = context

    if isDateEntry(entry) then
        return wrapEntryMarkup(string.format('%s<font color="%s" size="3">%s</font>', header, DATE_ENTRY_COLOR, body), "left")
    end

    return wrapEntryMarkup(string.format('%s<font color="%s" size="3">%s</font>', header, DEFAULT_ENTRY_COLOR, body))
end

-- Render the current journal snapshot into one deterministic HTML string for
-- MenuBook.
function M.renderBook(entries, context)
    local _ = entries
    local resolvedContext = context or {}
    local parts = {}

    local list = data.getRenderableEntries()
    if #list == 0 then
        parts[#parts + 1] = wrapEntryMarkup('<font color="000000" size="3">No entries found.</font>') .. '<br>'
        return table.concat(parts)
    end

    for index, entry in ipairs(list) do
        local nextEntry = list[index + 1]
        parts[#parts + 1] = M.renderEntry(entry, resolvedContext) .. buildSpacingAfter(entry, nextEntry)
    end

    parts[#parts + 1] = '<br>'
    return table.concat(parts)
end

return M
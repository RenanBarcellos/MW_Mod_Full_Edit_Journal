local M = {}
local NBSP = string.char(194, 160)
local PARAGRAPH_SENTINEL = "\31"

local function escapeBookHtmlText(text)
    local value = tostring(text or "")
    value = value:gsub("&", "&amp;")
    value = value:gsub("<", "&lt;")
    value = value:gsub(">", "&gt;")
    value = value:gsub('"', "&quot;")
    return value
end

local function isTopicBoundaryCharacter(character)
    return character == nil or character == "" or not character:match("[%w]")
end

local function buildKnownTopicCandidates(knownTopics)
    local candidates = {}
    local seen = {}

    for _, topic in pairs(type(knownTopics) == "table" and knownTopics or {}) do
        if type(topic) == "string" then
            local topicKey = M.buildTopicKey(topic)
            local displayText = M.normalizeWhitespace(topic)

            if topicKey and displayText ~= "" and not seen[topicKey] then
                seen[topicKey] = true
                candidates[#candidates + 1] = {
                    key = topicKey,
                    length = #topicKey,
                }
            end
        end
    end

    table.sort(candidates, function(left, right)
        if left.length ~= right.length then
            return left.length > right.length
        end

        return left.key < right.key
    end)

    return candidates
end

-- Escape book HTML while leaving journal topic delimiters intact so MenuBook can
-- still interpret them as links.
local function escapeBookHtmlPreservingJournalMarkup(text)
    local value = tostring(text or "")
    local parts = {}
    local startIndex = 1

    while true do
        local tagStart, tagEnd, topicText = value:find("@([^#]+)#", startIndex)
        if not tagStart then
            parts[#parts + 1] = escapeBookHtmlText(value:sub(startIndex))
            break
        end

        parts[#parts + 1] = escapeBookHtmlText(value:sub(startIndex, tagStart - 1))
        parts[#parts + 1] = string.format("@%s#", escapeBookHtmlText(topicText))
        startIndex = tagEnd + 1
    end

    return table.concat(parts):gsub("\n", "<br>")
end

-- Normalize user and journal text into a predictable whitespace layout before
-- it is compared, saved, or rendered.
function M.normalizeWhitespace(text)
    local value = tostring(text or "")
    value = value:gsub("\r\n", "\n")
    value = value:gsub("\r", "\n")
    value = value:gsub("[\t ]+", " ")
    value = value:gsub(" ?\n ?", "\n")
    value = value:gsub("\n\n\n+", "\n\n")
    value = value:gsub("^%s+", "")
    value = value:gsub("%s+$", "")
    return value
end

-- Book body normalization preserves paragraph breaks but can optionally keep
-- single-line breaks for player-authored notes.
function M.normalizeBookBodyWhitespace(text, options)
    local value = tostring(text or "")
    local preserveSingleLineBreaks = options and options.preserveSingleLineBreaks == true

    value = value:gsub("\r\n", "\n")
    value = value:gsub("\r", "\n")
    value = value:gsub("[\t ]+", " ")
    value = value:gsub(" ?\n ?", "\n")
    value = value:gsub("\n\n\n+", "\n\n")

    if not preserveSingleLineBreaks then
        value = value:gsub("\n\n", PARAGRAPH_SENTINEL)
        value = value:gsub("\n", " ")
        value = value:gsub(" +", " ")
        value = value:gsub(PARAGRAPH_SENTINEL, "\n\n")
    end

    value = value:gsub("^%s+", "")
    value = value:gsub("%s+$", "")
    return value
end

-- Journal topic markup uses @Topic# syntax, which needs to disappear when the
-- mod is building plain-text comparison keys.
function M.stripJournalMarkup(text)
    local value = tostring(text or "")
    return value:gsub("@([^#]+)#", "%1")
end

-- Topic keys use the player-visible text surface instead of quest ids because
-- journal hyperlinks are written with the topic label itself.
function M.buildTopicKey(topic)
    local value = M.stripJournalMarkup(topic)
    value = M.normalizeWhitespace(value)
    value = value:lower()

    if value == "" then
        return nil
    end

    return value
end

-- Extract all linked journal topics from an engine-authored entry so the save
-- can remember which topics are already unlocked.
function M.extractJournalTopics(text)
    local value = tostring(text or "")
    local topics = {}
    local seen = {}

    for topic in value:gmatch("@([^#]+)#") do
        local topicKey = M.buildTopicKey(topic)
        local displayText = M.normalizeWhitespace(topic)

        if topicKey and displayText ~= "" and not seen[topicKey] then
            seen[topicKey] = true
            topics[#topics + 1] = displayText
        end
    end

    return topics
end

-- Player-authored text is stored as plain text and only receives hyperlink
-- delimiters for topics the save has already unlocked.
function M.applyKnownJournalMarkup(text, knownTopics)
    local value = M.stripJournalMarkup(text)
    local candidates = buildKnownTopicCandidates(knownTopics)

    if #candidates == 0 then
        return value
    end

    local lowerValue = value:lower()
    local parts = {}
    local index = 1

    while index <= #value do
        local matchedText
        local matchedLength

        for _, candidate in ipairs(candidates) do
            local endIndex = index + candidate.length - 1
            if lowerValue:sub(index, endIndex) == candidate.key then
                local before = index > 1 and value:sub(index - 1, index - 1) or nil
                local after = endIndex < #value and value:sub(endIndex + 1, endIndex + 1) or nil

                if isTopicBoundaryCharacter(before) and isTopicBoundaryCharacter(after) then
                    matchedText = value:sub(index, endIndex)
                    matchedLength = candidate.length
                    break
                end
            end
        end

        if matchedText then
            parts[#parts + 1] = string.format("@%s#", matchedText)
            index = index + matchedLength
        else
            parts[#parts + 1] = value:sub(index, index)
            index = index + 1
        end
    end

    return table.concat(parts)
end

-- Mapping and editor flows need plain text, so strip the subset of HTML that
-- MenuBook renders back into visible content.
function M.stripBookHtml(text)
    local value = tostring(text or "")
    value = value:gsub("<[Bb][Rr]%s*/?>", "\n")
    value = value:gsub("</?[Pp]>", "\n\n")
    value = value:gsub("</?[Dd][Ii][Vv][^>]*>", "\n")
    value = value:gsub("</?[Ff][Oo][Nn][Tt][^>]*>", "")
    value = value:gsub("</?[Ii][Mm][Gg][^>]*>", "")
    value = value:gsub("<[^>]+>", "")
    value = value:gsub(NBSP, " ")
    value = value:gsub("&nbsp;", " ")
    value = value:gsub("&#160;", " ")
    value = value:gsub("&#xA0;", " ")
    value = value:gsub("&lt;", "<")
    value = value:gsub("&gt;", ">")
    value = value:gsub("&quot;", '"')
    value = value:gsub("&amp;", "&")
    return M.normalizeWhitespace(value)
end

-- Escape a single-line value so it is safe to embed directly in book HTML.
function M.sanitizeBookText(text, options)
    local value = tostring(text or "")
    local preserveJournalMarkup = options and options.preserveJournalMarkup == true
    local knownTopics = options and options.knownTopics or nil

    if preserveJournalMarkup then
        value = M.normalizeWhitespace(value)
    else
        value = knownTopics and M.applyKnownJournalMarkup(value, knownTopics) or M.stripJournalMarkup(value)
        value = M.normalizeWhitespace(value)
    end

    return escapeBookHtmlPreservingJournalMarkup(value)
end

-- Body sanitization uses the same escaping but keeps the body-specific
-- whitespace rules centralized in one place.
function M.sanitizeBookBodyText(text, options)
    local value = tostring(text or "")
    local preserveJournalMarkup = options and options.preserveJournalMarkup == true
    local knownTopics = options and options.knownTopics or nil

    if preserveJournalMarkup then
        value = M.normalizeBookBodyWhitespace(value, options)
    else
        value = knownTopics and M.applyKnownJournalMarkup(value, knownTopics) or M.stripJournalMarkup(value)
        value = M.normalizeBookBodyWhitespace(value, options)
    end

    return escapeBookHtmlPreservingJournalMarkup(value)
end

-- Selection, mapping, and search work on the visible text surface instead of
-- the underlying journal link delimiters or book HTML tags.
function M.normalizeVisibleBookText(text)
    local value = M.stripJournalMarkup(text)
    value = M.stripBookHtml(value)
    value = value:gsub("%-+", " ")
    return M.normalizeWhitespace(value)
end

-- Anchor keys are short, stable identifiers used by mapping and freeform-entry
-- ids to correlate rendered text with saved data.
function M.buildAnchorKey(text)
    local value = M.stripJournalMarkup(text)
    value = M.normalizeWhitespace(value)
    value = value:lower()
    value = value:gsub("[^%w]+", "_")
    value = value:gsub("_+", "_")
    value = value:gsub("^_", "")
    value = value:gsub("_$", "")

    if value == "" then
        return "empty"
    end

    return value:sub(1, 64)
end

return M
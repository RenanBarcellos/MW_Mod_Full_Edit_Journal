local data = require("journal_custom.journal.data")
local logger = require("journal_custom.util.logger")
local render = require("journal_custom.journal.render")
local text = require("journal_custom.util.text")

local M = {}

local BODY_SEGMENT_LENGTH = 56
local BODY_SEGMENT_MIN_LENGTH = 20
local BODY_SEGMENT_STEP = 24
local BODY_SEGMENT_LIMIT = 18
local BODY_WORD_WINDOW_MIN = 3
local BODY_WORD_WINDOW_MAX = 5
local BODY_WORD_WINDOW_STEP = 2

-- Matching is tolerant to layout whitespace and hyphenation because MenuBook
-- can split the same body text differently between pages.
local function collapseMatchWhitespace(value)
    local collapsed = tostring(value or "")
    collapsed = collapsed:gsub("%s+", " ")
    collapsed = collapsed:gsub("^%s+", "")
    collapsed = collapsed:gsub("%s+$", "")
    return collapsed
end

local PAGE_SPECS = {
    { pageSide = "left", pageOffset = 0 },
    { pageSide = "right", pageOffset = 1 },
}

local PAGE_ELEMENT_IDS = {
    left = "MenuBook_page_1",
    right = "MenuBook_page_2",
}

local sessionState = {
    currentSpreadStart = nil,
    lastSpreadSignature = nil,
    signatureToPage = {},
}

-- Normalize any rendered fragment into the same comparison surface used by the
-- entry matchers.
local function normalizeMatchText(value)
    return collapseMatchWhitespace(text.normalizeVisibleBookText(value))
end

-- Larger entries use longer fragments, while short entries still get a usable
-- minimum-sized matching window.
local function resolveSegmentLength(textLength)
    if textLength <= BODY_SEGMENT_MIN_LENGTH then
        return textLength
    end

    return math.min(BODY_SEGMENT_LENGTH, math.max(BODY_SEGMENT_MIN_LENGTH, math.floor(textLength * 0.6)))
end

-- Keep matcher order aligned with render order so later sorting can reproduce
-- the same visual sequence.
local function getRenderableEntries(state)
    local list = {}

    for _, entryId in ipairs(data.getOrderedEntryIds()) do
        local entry = state.entries and state.entries[entryId] or nil
        if type(entry) == "table" and entry.deleted ~= true then
            list[#list + 1] = entry
        end
    end

    return list
end

local function appendUnique(target, seen, value)
    if value == "" or seen[value] then
        return
    end

    seen[value] = true
    target[#target + 1] = value
end

-- Build overlapping fragments and short word windows so matching still works
-- when MenuBook shows only part of an entry body on a page.
local function collectBodySegments(body)
    local normalizedBody = normalizeMatchText(body)
    if normalizedBody == "" then
        return {}
    end

    local segmentLength = resolveSegmentLength(#normalizedBody)
    if #normalizedBody <= segmentLength then
        return { normalizedBody }
    end

    local segments = {}
    local seen = {}
    local maxStart = math.max(1, #normalizedBody - segmentLength + 1)
    local offset = 1

    while offset <= maxStart and #segments < BODY_SEGMENT_LIMIT do
        appendUnique(segments, seen, normalizedBody:sub(offset, offset + segmentLength - 1))
        offset = offset + BODY_SEGMENT_STEP
    end

    appendUnique(segments, seen, normalizedBody:sub(-segmentLength))

    local words = {}
    for word in normalizedBody:gmatch("%S+") do
        words[#words + 1] = word
    end

    for windowSize = BODY_WORD_WINDOW_MAX, BODY_WORD_WINDOW_MIN, -1 do
        local index = 1
        while index <= #words - windowSize + 1 and #segments < (BODY_SEGMENT_LIMIT * 2) do
            appendUnique(segments, seen, table.concat(words, " ", index, index + windowSize - 1))
            index = index + BODY_WORD_WINDOW_STEP
        end
    end

    return segments
end

-- Each entry matcher combines exact fragments with smaller fallback segments.
local function buildEntryMatcher(entry)
    local exactFragments = {}
    local seenFragments = {}
    appendUnique(exactFragments, seenFragments, normalizeMatchText(render.buildEntryBody(entry)))

    return {
        id = entry.id,
        exactFragments = exactFragments,
        isDateEntry = data.isDateEntry(entry),
        bodySegments = collectBodySegments(render.buildEntryBody(entry)),
    }
end

-- Collect normalized visible text from a concrete page element tree.
local function collectVisibleText(element, fragments)
    if not element or element.visible == false then
        return fragments
    end

    local elementText = element.text
    if type(elementText) == "string" then
        local normalized = normalizeMatchText(elementText)
        if normalized ~= "" then
            fragments[#fragments + 1] = normalized
        end
    end

    for _, child in ipairs(element.children or {}) do
        collectVisibleText(child, fragments)
    end

    return fragments
end

local function resolvePageSide(menuWidth, elementLeft, elementWidth)
    local resolvedWidth = type(elementWidth) == "number" and elementWidth or 0
    local centerX = elementLeft + math.max(0, resolvedWidth) / 2

    if centerX <= (menuWidth / 2) then
        return "left"
    end

    return "right"
end

local function collectVisibleTextBySide(element, fragmentsBySide, menuWidth, accumulatedX)
    if not element or element.visible == false then
        return fragmentsBySide
    end

    local localX = accumulatedX + (type(element.positionX) == "number" and element.positionX or 0)
    local pageSide = resolvePageSide(menuWidth, localX, element.width)

    local elementText = element.text
    if type(elementText) == "string" then
        local normalized = normalizeMatchText(elementText)
        if normalized ~= "" then
            fragmentsBySide[pageSide][#fragmentsBySide[pageSide] + 1] = normalized
        end
    end

    for _, child in ipairs(element.children or {}) do
        collectVisibleTextBySide(child, fragmentsBySide, menuWidth, localX)
    end

    return fragmentsBySide
end

local function findPageElement(menu, pageSide)
    local pageElementId = PAGE_ELEMENT_IDS[pageSide]
    if not pageElementId or not menu then
        return nil
    end

    return menu:findChild(tes3ui.registerID(pageElementId)) or menu:findChild(pageElementId)
end

local function parseSpreadStart(value)
    if type(value) ~= "string" then
        return nil
    end

    local pageNumber = tonumber(value:match("%d+"))
    if not pageNumber then
        return nil
    end

    if value:find("%-$") then
        pageNumber = pageNumber - 1
    end

    if pageNumber % 2 == 0 then
        pageNumber = pageNumber - 1
    end

    return math.max(1, pageNumber)
end

local function buildSpreadSignature(blocks)
    local parts = {}

    for _, block in ipairs(blocks or {}) do
        parts[#parts + 1] = string.format("%s:%s:%s", block.pageSide or "?", block.entryId or "?", block.field or "entry")
    end

    table.sort(parts)
    return table.concat(parts, "|")
end

local function getKnownSpreadStart(state, blocks)
    local bestPage

    for _, block in ipairs(blocks) do
        local entry = state.entries and state.entries[block.entryId]
        if entry and type(entry.lastKnownPage) == "number" then
            local candidate = entry.lastKnownPage - (block.pageSide == "right" and 1 or 0)
            if not bestPage or candidate < bestPage then
                bestPage = candidate
            end
        end
    end

    return bestPage
end

-- If the current spread cannot be read directly, fall back to historical page
-- data saved on entries and page-cache signatures.
local function resolveSpreadStart(state, blocks)
    local signature = buildSpreadSignature(blocks)
    if signature == "" then
        return nil, signature
    end

    local cachedSessionPage = sessionState.signatureToPage[signature]
    if type(cachedSessionPage) == "number" then
        return cachedSessionPage, signature
    end

    for pageKey, pageCache in pairs(state.pageCache or {}) do
        if type(pageCache) == "table" and pageCache.spreadSignature == signature then
            local cachedPage = tonumber(pageKey)
            if cachedPage then
                sessionState.signatureToPage[signature] = cachedPage
                return cachedPage, signature
            end
        end
    end

    local knownSpreadStart = getKnownSpreadStart(state, blocks)
    if knownSpreadStart then
        return math.max(1, knownSpreadStart), signature
    end

    if type(sessionState.currentSpreadStart) == "number" then
        return sessionState.currentSpreadStart + 2, signature
    end

    return 1, signature
end

-- Prefer exact body matches, then fall back to partial body segments.
local function scorePageMatch(pageText, matcher)
    for _, fragment in ipairs(matcher.exactFragments or {}) do
        if fragment ~= "" and pageText:find(fragment, 1, true) then
            return matcher.isDateEntry and 4 or 3, "body"
        end
    end

    local score = 0
    local field

    for _, segment in ipairs(matcher.bodySegments) do
        if segment ~= "" and pageText:find(segment, 1, true) then
            score = math.max(score, 2)
            field = "body"
            break
        end
    end

    return score, field
end

function M.getCurrentSpreadStart(menu)
    if not menu then
        return nil
    end

    local pageNumberElement = menu:findChild(tes3ui.registerID("MenuBook_page_number_1"))
        or menu:findChild("MenuBook_page_number_1")
    if not pageNumberElement then
        return nil
    end

    return parseSpreadStart(tostring(pageNumberElement.text or ""))
end

-- Rebuild the visible block list by matching rendered page text back to the
-- ordered saved entries.
function M.collectVisibleBlocks(menu, state)
    local blocks = {}

    if not menu or type(state) ~= "table" then
        return blocks
    end

    local pageSnapshots = {}
    local hasExplicitPageElements = true

    for _, page in ipairs(PAGE_SPECS) do
        if not findPageElement(menu, page.pageSide) then
            hasExplicitPageElements = false
            break
        end
    end

    if hasExplicitPageElements then
        for _, page in ipairs(PAGE_SPECS) do
            local fragments = collectVisibleText(findPageElement(menu, page.pageSide), {})
            local pageText = normalizeMatchText(table.concat(fragments, " "))
            if pageText ~= "" then
                pageSnapshots[#pageSnapshots + 1] = {
                    pageSide = page.pageSide,
                    pageOffset = page.pageOffset,
                    text = pageText,
                }
            end
        end
    else
        local menuWidth = type(menu.width) == "number" and menu.width or 0
        local fragmentsBySide = {
            left = {},
            right = {},
        }

        collectVisibleTextBySide(menu, fragmentsBySide, menuWidth, 0)

        for _, page in ipairs(PAGE_SPECS) do
            local pageText = normalizeMatchText(table.concat(fragmentsBySide[page.pageSide] or {}, " "))
            if pageText ~= "" then
                pageSnapshots[#pageSnapshots + 1] = {
                    pageSide = page.pageSide,
                    pageOffset = page.pageOffset,
                    text = pageText,
                }
            end
        end
    end

    if #pageSnapshots == 0 then
        logger.warn("journal_custom mapping found no visible text in MenuBook.")
        return blocks
    end

    local renderableEntries = getRenderableEntries(state)
    local entryOrder = {}
    for index, entry in ipairs(renderableEntries) do
        entryOrder[entry.id] = index
    end

    for _, entry in ipairs(renderableEntries) do
        local matcher = buildEntryMatcher(entry)
        for _, pageSnapshot in ipairs(pageSnapshots) do
            local score, field = scorePageMatch(pageSnapshot.text, matcher)
            if field and score >= 2 then
                blocks[#blocks + 1] = {
                    entryId = entry.id,
                    field = field,
                    pageSide = pageSnapshot.pageSide,
                    pageOffset = pageSnapshot.pageOffset,
                    confidence = score,
                }
            end
        end
    end

    table.sort(blocks, function(left, right)
        if left.pageOffset ~= right.pageOffset then
            return left.pageOffset < right.pageOffset
        end

        if left.entryId ~= right.entryId then
            return (entryOrder[left.entryId] or math.huge) < (entryOrder[right.entryId] or math.huge)
        end

        return tostring(left.field or "") < tostring(right.field or "")
    end)

    local signature = buildSpreadSignature(blocks)
    local spreadStart = M.getCurrentSpreadStart(menu)
    if not spreadStart then
        spreadStart, signature = resolveSpreadStart(state, blocks)
    end

    if not spreadStart then
        return {}
    end

    sessionState.currentSpreadStart = spreadStart
    sessionState.lastSpreadSignature = signature
    if signature ~= "" then
        sessionState.signatureToPage[signature] = spreadStart
    end

    blocks.spreadStart = spreadStart
    blocks.spreadSignature = signature

    for _, block in ipairs(blocks) do
        block.pageNumber = spreadStart + (block.pageOffset or 0)
    end

    return blocks
end

function M.findBlockByEntryId(blocks, entryId)
    for _, block in ipairs(blocks or {}) do
        if block.entryId == entryId then
            return block
        end
    end

    return nil
end

-- Persist only the minimal signature needed to restore context on later opens.
function M.updatePageCache(state, pageNumber, blocks)
    if type(state) ~= "table" or type(pageNumber) ~= "number" then
        return false
    end

    state.pageCache = state.pageCache or {}

    local pageBlocks = {}
    for _, block in ipairs(blocks or {}) do
        pageBlocks[#pageBlocks + 1] = {
            entryId = block.entryId,
            field = block.field,
            pageSide = block.pageSide,
        }
    end

    table.sort(pageBlocks, function(left, right)
        if left.entryId ~= right.entryId then
            return tostring(left.entryId) < tostring(right.entryId)
        end

        if left.field ~= right.field then
            return tostring(left.field) < tostring(right.field)
        end

        return tostring(left.pageSide) < tostring(right.pageSide)
    end)

    local signatureParts = {}
    local entryIds = {}
    for _, block in ipairs(pageBlocks) do
        signatureParts[#signatureParts + 1] = string.format("%s:%s:%s", block.pageSide or "?", block.entryId or "?", block.field or "entry")
        entryIds[#entryIds + 1] = block.entryId
    end

    local newCache = {
        spreadSignature = sessionState.lastSpreadSignature,
        entryIds = entryIds,
        blockSignature = table.concat(signatureParts, "|"),
    }

    local key = tostring(pageNumber)
    local existing = state.pageCache[key]
    if type(existing) == "table"
        and existing.spreadSignature == newCache.spreadSignature
        and existing.blockSignature == newCache.blockSignature
    then
        return false
    end

    state.pageCache[key] = newCache
    return true
end

return M
local M = {}
local NBSP = string.char(194, 160)
local PARAGRAPH_SENTINEL = "\31"

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

function M.stripJournalMarkup(text)
    local value = tostring(text or "")
    return value:gsub("@([^#]+)#", "%1")
end

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

function M.sanitizeBookText(text)
    local value = M.stripJournalMarkup(text)
    value = M.normalizeWhitespace(value)
    value = value:gsub("&", "&amp;")
    value = value:gsub("<", "&lt;")
    value = value:gsub(">", "&gt;")
    value = value:gsub('"', "&quot;")
    value = value:gsub("\n", "<br>")
    return value
end

function M.sanitizeBookBodyText(text, options)
    local value = M.stripJournalMarkup(text)
    value = M.normalizeBookBodyWhitespace(value, options)
    value = value:gsub("&", "&amp;")
    value = value:gsub("<", "&lt;")
    value = value:gsub(">", "&gt;")
    value = value:gsub('"', "&quot;")
    value = value:gsub("\n", "<br>")
    return value
end

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
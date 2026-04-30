local config = require("journal_custom.config")

local logger = mwse.Logger.new("Mod 1 - Journal Customizado")

local M = {}

local function isDebugEnabled()
    local state = config.get()
    local featureFlags = state.featureFlags or {}
    return featureFlags.debugLogging == true
end

function M.get()
    return logger
end

function M.debug(...)
    if isDebugEnabled() then
        logger:debug(...)
    end
end

function M.info(...)
    logger:info(...)
end

function M.warn(...)
    logger:warn(...)
end

function M.error(...)
    logger:error(...)
end

return M
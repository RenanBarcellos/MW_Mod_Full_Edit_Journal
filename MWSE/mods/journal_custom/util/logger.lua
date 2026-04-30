local config = require("journal_custom.config")

local logger = mwse.Logger.new("Mod 1 - Custom Journal")

local M = {}

-- Debug logging is feature-gated so noisy traces can be enabled for testing
-- without flooding normal gameplay sessions.
local function isDebugEnabled()
    local state = config.get()
    local featureFlags = state.featureFlags or {}
    return featureFlags.debugLogging == true
end

function M.get()
    return logger
end

-- Keep debug filtering here so call sites do not need to repeat the flag check.
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
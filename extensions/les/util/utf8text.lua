--  SPDX-License-Identifier: MIT
--  UTF-8 validation helpers for user-visible character limits.

local utf8text = {}

--- Return the number of Unicode code points in a valid UTF-8 string.
--- Malformed UTF-8 and non-string values are rejected with nil.
---@param value any
---@return integer|nil length
function utf8text.length(value)
    if type(value) ~= "string" then return nil end
    local ok, length = pcall(utf8.len, value)
    if not ok or type(length) ~= "number" then return nil end
    return length
end

--- Check a valid UTF-8 string against a non-negative character limit.
---@param value any
---@param maximum number
---@return boolean
function utf8text.isWithinLimit(value, maximum)
    local length = utf8text.length(value)
    local limit = tonumber(maximum)
    return length ~= nil and limit ~= nil and limit >= 0 and length <= math.floor(limit)
end

return utf8text

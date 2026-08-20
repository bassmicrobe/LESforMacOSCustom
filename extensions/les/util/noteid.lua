--  SPDX-License-Identifier: MIT
--  Stable identifiers for project and track-note records.

local noteid = {}
local fallbackSequence = 0

local function isValid(value)
    return type(value) == "string"
        and #value > 0
        and #value <= 128
        and value:match("^[%w%._:%-]+$") ~= nil
end

---@param value any
---@param timestamp number
---@param index number
---@return string
function noteid.normalize(value, timestamp, index)
    if isValid(value) then return value end
    return string.format("legacy-%d-%d", math.floor(tonumber(timestamp) or 0), math.max(1, index or 1))
end

---@return string
function noteid.create()
    if hs and hs.host and type(hs.host.uuid) == "function" then
        local ok, value = pcall(hs.host.uuid)
        if ok and isValid(value) then return value end
    end

    fallbackSequence = fallbackSequence + 1
    local epoch = 0
    if hs and hs.timer and type(hs.timer.secondsSinceEpoch) == "function" then
        local ok, value = pcall(hs.timer.secondsSinceEpoch)
        if ok then epoch = tonumber(value) or 0 end
    end
    return string.format("local-%d-%d", math.floor(epoch * 1000000), fallbackSequence)
end

return noteid

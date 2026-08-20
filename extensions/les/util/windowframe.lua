--  SPDX-License-Identifier: MIT
--  Pure helpers for keeping auxiliary windows inside the visible screen frame.

local windowframe = {}

local function boundedSize(screen, preferredWidth, preferredHeight, margin)
    if type(screen) ~= "table" then return nil end
    local inset = math.max(0, tonumber(margin) or 0)
    local screenWidth = math.max(1, tonumber(screen.w) or 1)
    local screenHeight = math.max(1, tonumber(screen.h) or 1)
    local width = math.min(math.max(1, tonumber(preferredWidth) or 1), math.max(1, screenWidth - inset * 2))
    local height = math.min(math.max(1, tonumber(preferredHeight) or 1), math.max(1, screenHeight - inset * 2))
    return width, height, inset
end

---@param screen table
---@param preferredWidth number
---@param preferredHeight number
---@param margin number|nil
---@return table
function windowframe.center(screen, preferredWidth, preferredHeight, margin)
    local width, height = boundedSize(screen, preferredWidth, preferredHeight, margin)
    if not width then return {x = 0, y = 0, w = 1, h = 1} end
    local screenX = tonumber(screen.x) or 0
    local screenY = tonumber(screen.y) or 0
    return {
        x = math.floor(screenX + ((tonumber(screen.w) or width) - width) / 2),
        y = math.floor(screenY + ((tonumber(screen.h) or height) - height) / 2),
        w = width,
        h = height,
    }
end

---@param screen table
---@param preferredWidth number
---@param preferredHeight number
---@param margin number|nil
---@param topOffset number|nil
---@return table
function windowframe.right(screen, preferredWidth, preferredHeight, margin, topOffset)
    local width, height, inset = boundedSize(screen, preferredWidth, preferredHeight, margin)
    if not width then return {x = 0, y = 0, w = 1, h = 1} end
    local screenX = tonumber(screen.x) or 0
    local screenY = tonumber(screen.y) or 0
    local screenWidth = tonumber(screen.w) or width
    local screenHeight = tonumber(screen.h) or height
    local requestedY = screenY + math.max(inset, tonumber(topOffset) or inset)
    local maximumY = screenY + screenHeight - height - inset
    return {
        x = math.floor(screenX + screenWidth - width - inset),
        y = math.floor(math.min(requestedY, maximumY)),
        w = width,
        h = height,
    }
end

return windowframe

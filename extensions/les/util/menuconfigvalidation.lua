-- SPDX-License-Identifier: MIT
-- Validate the bridge payload before serializing the line-based menu format.

local M = {}

local function isArray(value)
    if type(value) ~= "table" then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
        count = count + 1
    end
    return count == #value
end

local function isLine(value)
    return type(value) == "string" and value:match("%S") ~= nil
        and value:find("[%z\1-\31\127]") == nil
end

local function pluginsFrom(value)
    if not isArray(value) then return nil end
    local result = {}
    for _, plugin in ipairs(value) do
        if type(plugin) ~= "table" or not isLine(plugin.name) or not isLine(plugin.query) then return nil end
        local name = plugin.name:match("^%s*(.-)%s*$")
        if name:find('^[/;"]') or name == "End" or name == ".." or name == "--" or name == "—" then return nil end
        result[#result + 1] = {name = name, query = plugin.query}
    end
    return result
end

---@param data any
---@param comments table
---@return table|nil
function M.normalize(data, comments)
    if type(data) ~= "table" or not isArray(data.categories) then return nil end
    local uncategorized = pluginsFrom(data.nocategory)
    if not uncategorized then return nil end
    local categories, names = {}, {}
    for _, category in ipairs(data.categories) do
        if type(category) ~= "table" or not isLine(category.name) then return nil end
        local name = category.name:match("^%s*(.-)%s*$")
        if name:sub(1, 1) == "/" or name == "nocategory" or names[name] then return nil end
        local plugins = pluginsFrom(category.plugins)
        if not plugins then return nil end
        categories[#categories + 1] = {name = name, plugins = plugins}
        names[name] = true
    end
    return {comments = comments, categories = categories, nocategory = uncategorized}
end

return M

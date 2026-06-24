--  SPDX-License-Identifier: MIT
--
--  Copyright (c) 2019-2023 LESforMacOS authors, see AUTHORS.txt
--  for a list
--
--  Distributed under the MIT software license, see the accompanying
--  file COPYING.txt or visit https://opensource.org/license/mit/

-----------------------------------------
--  Plugin Usage Statistics Tracker    --
--  Tracks add date, last use, count   --
--  Stored as JSON in ~/.les/resources --
-----------------------------------------

local pluginStats = {}

local STATS_FILE = "plugin_stats.json"

--- Get the full path to the stats file.
---@return string
local function statsFilePath()
    return strJoinPaths(ScriptUserResourcesPath, STATS_FILE)
end

-- Short-TTL read cache. openPluginChooser() and the AI summary call load()
-- several times in quick succession; re-reading + JSON-decoding the file each
-- time is wasteful (#37). Mutators (save) refresh this, and Hammerspoon runs
-- single-threaded on the run loop, so within-TTL reads stay consistent.
local _statsCache = nil
local _statsCacheTime = -1
local STATS_CACHE_TTL = 2

local function _now()
    return (hs and hs.timer and hs.timer.secondsSinceEpoch and hs.timer.secondsSinceEpoch()) or 0
end

--- Load stats from disk. Returns a table keyed by plugin name.
---@return table<string, {added_at: number, last_used_at: number, use_count: number}>
function pluginStats.load()
    local now = _now()
    if _statsCache ~= nil and (now - _statsCacheTime) < STATS_CACHE_TTL then
        return _statsCache
    end
    local path = statsFilePath()
    local data = {}
    local f = io.open(path, "r")
    if f then
        local raw = f:read("*a")
        f:close()
        if raw and raw ~= "" then
            local ok, decoded = pcall(hs.json.decode, raw)
            if ok and type(decoded) == "table" then data = decoded end
        end
    end
    _statsCache = data
    _statsCacheTime = now
    return data
end

--- Save stats table to disk.
---@param data table
function pluginStats.save(data)
    ShellCreateDirectory(ScriptUserResourcesPath)
    local path = statsFilePath()
    -- Guard the encode (nil on a bad table would otherwise truncate the file)
    -- and write atomically via a temp file + rename.
    local ok, json = pcall(hs.json.encode, data, true)
    if not ok or type(json) ~= "string" then return end
    local tmp = path .. ".tmp"
    local f = io.open(tmp, "w")
    if not f then return end
    f:write(json)
    if not f:close() then
        os.remove(tmp)
        return
    end
    if os.rename(tmp, path) then
        -- Keep the read cache consistent with what was just persisted (#37).
        _statsCache = data
        _statsCacheTime = _now()
    end
end

--- Record a plugin use event.
--- Creates entry if first time, updates last_used_at and increments use_count.
---@param pluginName string  The display name of the plugin
function pluginStats.recordUse(pluginName)
    if not pluginName or pluginName == "" then return end
    -- Defer the read/modify/write off the plugin-insertion hot path (it runs
    -- from loadPlugin on every insert). The return value is never used, so
    -- running on the next run-loop tick costs nothing and removes the
    -- synchronous file I/O latency from the user's click.
    hs.timer.doAfter(0, function()
        local data = pluginStats.load()
        local now = math.floor(hs.timer.secondsSinceEpoch())
        local entry = data[pluginName]
        if entry then
            entry.last_used_at = now
            entry.use_count = (entry.use_count or 0) + 1
        else
            data[pluginName] = {
                added_at     = now,
                last_used_at = now,
                use_count    = 1,
            }
        end
        pluginStats.save(data)
    end)
end

--- Get stats for a single plugin. Returns nil if not tracked.
---@param pluginName string
---@return table|nil
function pluginStats.get(pluginName)
    local data = pluginStats.load()
    return data[pluginName]
end

--- Get all stats.
---@return table
function pluginStats.getAll()
    return pluginStats.load()
end

--- Toggle favorite status for a plugin.
--- Creates an entry if none exists. Returns new favorite state.
---@param pluginName string
---@return boolean
function pluginStats.toggleFavorite(pluginName)
    if not pluginName or pluginName == "" then return false end
    local data = pluginStats.load()
    local now = math.floor(hs.timer.secondsSinceEpoch())
    local entry = data[pluginName]
    if entry then
        entry.favorited = not entry.favorited
    else
        data[pluginName] = {
            added_at     = now,
            last_used_at = 0,
            use_count    = 0,
            favorited    = true,
        }
    end
    pluginStats.save(data)
    return data[pluginName].favorited
end

--- Check if a plugin is favorited.
---@param pluginName string
---@return boolean
function pluginStats.isFavorite(pluginName)
    local data = pluginStats.load()
    local entry = data[pluginName]
    return entry ~= nil and entry.favorited == true
end

--- Get all favorited plugin names, sorted alphabetically.
---@return table
function pluginStats.getFavorites()
    local data = pluginStats.load()
    local favs = {}
    for name, entry in pairs(data) do
        if entry.favorited == true then
            favs[#favs + 1] = name
        end
    end
    table.sort(favs)
    return favs
end

return pluginStats

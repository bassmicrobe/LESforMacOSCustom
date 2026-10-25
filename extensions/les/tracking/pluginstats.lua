--  SPDX-License-Identifier: MIT
--
--  Copyright (c) 2019-2023 LESforMacOS authors, see AUTHORS.txt
--  for a list
--
--  Distributed under the MIT software license, see the accompanying
--  file COPYING.txt or visit https://opensource.org/license/mit/
--
-- Validated, cached plugin statistics with coalesced usage writes.

local pluginStats = {}
local STATS_FILE = "plugin_stats.json"
local STATS_CACHE_TTL = 2
local _statsCache, _statsCacheTime, _statsCacheError = nil, -1, nil
local _pendingUses, _flushScheduled = nil, false

local function now()
    return hs.timer.secondsSinceEpoch()
end

local function count(value)
    local number = tonumber(value)
    if not number or number ~= number or number < 0 or number == math.huge then return 0 end
    return math.tointeger(math.floor(number)) or 0
end

local function timestamp(value)
    local number = count(value)
    if number == 0 then return 0 end
    return pcall(os.date, "%Y", number) and number or 0
end

local function copyEntry(entry)
    return {
        added_at = timestamp(entry.added_at),
        last_used_at = timestamp(entry.last_used_at),
        use_count = count(entry.use_count),
        favorited = entry.favorited == true,
    }
end

local function snapshot(data)
    local result = {}
    for name, entry in pairs(data) do
        if type(name) == "string" and name ~= "" and type(entry) == "table" then
            result[name] = copyEntry(entry)
        end
    end
    return result
end

local function readDisk()
    local file, _, code = io.open(strJoinPaths(ScriptUserResourcesPath, STATS_FILE), "r")
    if not file then
        if code == 2 then return {} end -- ENOENT: first use, not a damaged file.
        return {}, "statistics file is unreadable"
    end
    local raw = file:read("*a")
    local closed = file:close()
    if not raw or raw == "" or not closed then return {}, "statistics file could not be read" end
    local ok, decoded = pcall(hs.json.decode, raw)
    if not ok or type(decoded) ~= "table" then return {}, "statistics JSON is invalid" end
    return snapshot(decoded)
end

local function cached()
    local current = now()
    if _statsCache == nil or current < _statsCacheTime or current - _statsCacheTime >= STATS_CACHE_TTL then
        _statsCache, _statsCacheError = readDisk()
        _statsCacheTime = current
    end
    return _statsCache, _statsCacheError
end

--- Return an independent snapshot; callers cannot mutate cached state.
function pluginStats.load()
    local data, err = cached()
    return snapshot(data), err
end

--- Commit cache changes only after the complete file is safely replaced.
---@return boolean ok
---@return string|nil err
function pluginStats.save(data)
    if type(data) ~= "table" then return false, "statistics must be a table" end
    local updated = snapshot(data)
    local encoded, json = pcall(hs.json.encode, updated, true)
    if not encoded or type(json) ~= "string" then return false, "statistics encoding failed" end
    ShellCreateDirectory(ScriptUserResourcesPath)
    local path = strJoinPaths(ScriptUserResourcesPath, STATS_FILE)
    local tempPath = path .. ".tmp"
    local file = io.open(tempPath, "w")
    if not file then return false, "statistics temporary file could not be opened" end
    local written = file:write(json)
    local closed = file:close()
    if not written or not closed then
        local removed = os.remove(tempPath)
        if not removed then print("[pluginstats] unable to remove failed temporary file") end
        return false, "statistics write failed"
    end
    local renamed = os.rename(tempPath, path)
    if not renamed then
        local removed = os.remove(tempPath)
        if not removed then print("[pluginstats] unable to remove uncommitted temporary file") end
        return false, "statistics replacement failed"
    end
    _statsCache, _statsCacheTime, _statsCacheError = updated, now(), nil
    return true
end

local function validName(name)
    return type(name) == "string" and name ~= ""
end

local function flushUses()
    local pending = _pendingUses
    _pendingUses, _flushScheduled = nil, false
    local current, readError = cached()
    if readError then
        print("[pluginstats] usage not saved: " .. readError)
        return
    end
    local updated = snapshot(current)
    while pending do
        local entry = updated[pending.name]
        updated[pending.name] = {
            added_at = entry and math.min(entry.added_at, pending.time) or pending.time,
            last_used_at = math.max(entry and entry.last_used_at or 0, pending.time),
            use_count = math.min(entry and entry.use_count or 0, math.maxinteger - 1) + 1,
            favorited = entry and entry.favorited == true or false,
        }
        pending = pending.previous
    end
    local saved, err = pluginStats.save(updated)
    if not saved then print("[pluginstats] usage not saved: " .. tostring(err)) end
end

--- One next-tick write for a burst; enqueue without copying the entire history.
function pluginStats.recordUse(pluginName)
    if not validName(pluginName) then return end
    _pendingUses = {name = pluginName, time = math.floor(now()), previous = _pendingUses}
    if _flushScheduled then return end
    _flushScheduled = true
    local scheduled = pcall(hs.timer.doAfter, 0, flushUses)
    if not scheduled then
        _flushScheduled = false
        _pendingUses = nil
        print("[pluginstats] unable to schedule usage update")
    end
end

function pluginStats.get(pluginName)
    local data = cached()
    return data[pluginName] and copyEntry(data[pluginName]) or nil
end

function pluginStats.getAll()
    return pluginStats.load()
end

--- Return the persisted state and, on failure, a separate error.
function pluginStats.toggleFavorite(pluginName)
    if not validName(pluginName) then return false, "invalid plugin name" end
    local current, readError = cached()
    local entry = current[pluginName]
    local previous = entry and entry.favorited == true or false
    if readError then return previous, readError end
    local updated = snapshot(current)
    updated[pluginName] = {
        added_at = entry and entry.added_at or math.floor(now()),
        last_used_at = entry and entry.last_used_at or 0,
        use_count = entry and entry.use_count or 0,
        favorited = not previous,
    }
    local saved, err = pluginStats.save(updated)
    if not saved then return previous, err end
    return not previous
end

function pluginStats.isFavorite(pluginName)
    local data = cached()
    return data[pluginName] ~= nil and data[pluginName].favorited == true
end

function pluginStats.getFavorites()
    local data = cached()
    local favorites = {}
    for name, entry in pairs(data) do
        if entry.favorited then favorites[#favorites + 1] = name end
    end
    table.sort(favorites)
    return favorites
end

return pluginStats

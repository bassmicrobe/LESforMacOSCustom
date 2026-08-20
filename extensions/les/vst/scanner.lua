--  SPDX-License-Identifier: MIT
--
--  Copyright (c) 2019-2023 LESforMacOS authors, see AUTHORS.txt
--  for a list
--
--  Distributed under the MIT software license, see the accompanying
--  file COPYING.txt or visit https://opensource.org/license/mit/

---------------------------------------------------
--  Plugin Scanner                               --
--  Discovers AU/VST3 plugins and auto-          --
--  categorizes them from system metadata        --
--                                               --
--  Supports incremental (diff) scanning:        --
--  caches scan results and only processes new   --
--  or removed plugins on subsequent runs.       --
---------------------------------------------------

local scanner = {}
local MAX_MODULEINFO_BYTES = 4 * 1024 * 1024
local windowframe = require("util.windowframe")

---@type hs.webview|nil
local scanProgressWV = nil
---@type hs.task|nil
local activeAUTask = nil
local scanInProgress = false
local scanProgressPercent = 0
local scanProgressLabel = ""

local function escapeScanHtml(s)
    return (tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function localized(key, fallback)
    if type(L) == "function" then
        local value = L(key)
        if type(value) == "string" and value ~= key then return value end
    end
    return fallback
end

local function localizedFormat(key, fallback, ...)
    return string.format(localized(key, fallback), ...)
end

local function currentLanguage()
    return _G.uiLanguage == "en" and "en" or "ja"
end

local function jsString(value)
    local escaped = tostring(value or ""):gsub("\\", "\\\\"):gsub("'", "\\'")
        :gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("<", "\\x3c"):gsub(">", "\\x3e")
        :gsub("\u{2028}", "\\u2028"):gsub("\u{2029}", "\\u2029")
    return "'" .. escaped .. "'"
end

local function scanProgressHTML(pct, label)
    local p = math.max(0, math.min(100, math.floor(tonumber(pct) or 0)))
    return string.format(
        [[<!DOCTYPE html><html lang="%s"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>
*{box-sizing:border-box;margin:0;padding:0}
body{color-scheme:dark;font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#1c1c1e;color:#e5e5ea;padding:18px 20px;}
h1{font-size:14px;font-weight:600;margin-bottom:12px;color:#fff;}
#barwrap{background:#2c2c2e;border-radius:6px;height:10px;overflow:hidden;margin-bottom:8px;}
#bar{height:100%%;width:%d%%;background:#0a84ff;border-radius:6px;transition:width .2s ease;}
p{font-size:11px;color:#8e8e93;line-height:1.45;}
</style></head><body>
<h1 id="scanLabel" role="status" aria-live="polite">%s</h1>
<div id="barwrap"><div id="bar" role="progressbar" aria-label="%s" aria-valuemin="0" aria-valuemax="100" aria-valuenow="%d"></div></div>
<p>%s</p>
<script>
function setProgress(percent,label){
  var value=Math.max(0,Math.min(100,Math.floor(Number(percent)||0)));
  var bar=document.getElementById('bar');
  bar.style.width=value+'%%';bar.setAttribute('aria-valuenow',String(value));
  var heading=document.getElementById('scanLabel');heading.textContent=label;bar.setAttribute('aria-label',label);
}
</script>
</body></html>]],
        currentLanguage(),
        p,
        escapeScanHtml(label),
        escapeScanHtml(label),
        p,
        escapeScanHtml(localized("scanner_progress_detail",
            "system_profiler と VST3 バンドル走査のため、数十秒かかることがあります。このウィンドウは完了後に閉じます。"))
    )
end

local function openScanProgress()
    if scanProgressWV then
        local previous = scanProgressWV
        scanProgressWV = nil
        previous:delete()
    end
    local screen = hs.screen.mainScreen():frame()
    local frame = windowframe.center(screen, 380, 150, 12)
    scanProgressWV = hs.webview.new(frame)
    if scanProgressWV == nil then return end
    local currentWebview = scanProgressWV
    scanProgressWV:deleteOnClose(true)
    scanProgressWV:windowStyle({ "titled", "closable", "resizable" })
    scanProgressWV:windowTitle(localized("scanner_title", "プラグインスキャン"))
    scanProgressWV:level(hs.drawing.windowLevels.floating)
    scanProgressWV:windowCallback(function(action)
        if action == "closing" and scanProgressWV == currentWebview then scanProgressWV = nil end
    end)
    local label = scanProgressLabel ~= "" and scanProgressLabel
        or localized("scanner_preparing", "準備中…")
    scanProgressWV:html(scanProgressHTML(scanProgressPercent, label))
    scanProgressWV:show()
    scanProgressWV:bringToFront()
end

local function showScanProgress()
    if scanProgressWV == nil then
        openScanProgress()
        return
    end
    scanProgressWV:show()
    scanProgressWV:bringToFront()
end

local function setScanProgress(pct, label)
    scanProgressPercent = math.max(0, math.min(100, math.floor(tonumber(pct) or 0)))
    scanProgressLabel = tostring(label or "")
    local currentWebview = scanProgressWV
    if not currentWebview then return end
    local progress = scanProgressPercent
    local script = string.format("setProgress(%d,%s)", progress, jsString(scanProgressLabel))
    local ok = pcall(function() currentWebview:evaluateJavaScript(script) end)
    if not ok and scanProgressWV == currentWebview then
        currentWebview:html(scanProgressHTML(progress, scanProgressLabel))
    end
end

local function closeScanProgress()
    if scanProgressWV then
        local currentWebview = scanProgressWV
        scanProgressWV = nil
        currentWebview:delete()
    end
end

local CACHE_FILE = "plugin_cache.json"

-- ── Keyword heuristic map ──────────────────────────────────────────────
-- Matched case-insensitively with plain substring search (not Lua patterns).
-- First matching category in this list wins; within a category, first matching keyword wins.
-- Put longer / more specific phrases before shorter substrings (e.g. "sampler" before "sample").
local KEYWORD_CATEGORIES = {
    { category = "Compressor",   keywords = {
        "compressor", "multiband", "de-ess", "deess", "limiter", "expander", "dynamics",
        "transient", "comp",
    } },
    { category = "EQ",           keywords = {
        "equaliz", "equaliser", "equalizer", "parametric", "graphic eq", "linear phase",
        "channel eq", "filter", "tilt",
    } },
    { category = "Reverb",       keywords = {
        "reverb", "convolution", "hall", "room", "plate", "spring", "verb",
    } },
    { category = "Delay",        keywords = { "delay", "echo", "tape" } },
    { category = "Distortion",   keywords = {
        "distort", "saturate", "saturat", "overdrive", "waveshap", "decimate", "bitcrush",
        "crush", "fuzz", "drive", "clip",
    } },
    { category = "Modulation",   keywords = {
        "chorus", "flanger", "phaser", "tremolo", "vibrato", "ensemble", "rotary", "leslie",
    } },
    { category = "Utility",      keywords = {
        "utility", "spectrum", "analyz", "imager", "tuner", "loudness", "meter", "gain",
        "mono", "stereo",
    } },
    { category = "Pitch",        keywords = {
        "autotune", "auto-tune", "harmoniz", "vocoder", "formant", "pitch",
    } },
    { category = "Synthesizer",  keywords = {
        "wavetable", "subtractive", "additive", "granular", "oscillat", "synth", "fm",
        "analog",
    } },
    { category = "Sampler",      keywords = {
        "drum rack", "sampler", "sample", "rompler", "kontakt", "drum",
    } },
    { category = "MIDI Effect",  keywords = {
        "arpeggiator", "arpeggio", "velocity", "chord", "scale", "random", "note", "midi",
    } },
}

-- ── VST3 subcategory string → LES category mapping ────────────────────
-- Ordered array (NOT a hash map): iterated with ipairs so matching is
-- deterministic. Entries are sorted most-specific-first so the bare "Fx" /
-- "Instrument" patterns only match after every "Fx|..." / "Instrument|..."
-- pattern has been tried (plain substring match would otherwise let "Fx"
-- swallow "Fx|Reverb").
local VST3_SUBCAT_MAP = {
    { "Fx|Dynamics",        "Compressor" },
    { "Fx|EQ",              "EQ" },
    { "Fx|Filter",          "EQ" },
    { "Fx|Reverb",          "Reverb" },
    { "Fx|Delay",           "Delay" },
    { "Fx|Distortion",      "Distortion" },
    { "Fx|Modulation",      "Modulation" },
    { "Fx|Pitch Shift",     "Pitch" },
    { "Fx|Tools",           "Utility" },
    { "Fx|Analyzer",        "Utility" },
    { "Fx|Spatial",         "Reverb" },
    { "Fx|Mastering",       "Mastering" },
    { "Fx|Restoration",     "Utility" },
    { "Instrument|Synth",   "Synthesizer" },
    { "Instrument|Drum",    "Sampler" },
    { "Instrument|Sampler", "Sampler" },
    { "Instrument|Piano",   "Instruments" },
    { "Fx",                 "Effects" },
    { "Instrument",         "Instruments" },
}

-- ── Preferred category order for menuconfig.ini generation ─────────────
local CATEGORY_ORDER = {
    "Instruments", "Synthesizer", "Sampler", "Generator",
    "Compressor", "EQ", "Reverb", "Delay", "Distortion",
    "Modulation", "Pitch", "Mastering", "Utility",
    "MIDI Effect", "Effects",
}

-- ═══════════════════════════════════════════════════════════════════════
--  Cache: stores scan results to enable incremental diff scanning
-- ═══════════════════════════════════════════════════════════════════════

---@return string
local function cacheFilePath()
    return strJoinPaths(ScriptUserResourcesPath, CACHE_FILE)
end

--- Load cached scan data from disk.
--- Returns { plugins = { [name] = { category, format } }, scanned_at = timestamp }
---@return table
function scanner.loadCache()
    local path = cacheFilePath()
    local f = io.open(path, "r")
    if not f then return { plugins = {}, scanned_at = 0 } end
    local raw = f:read("*a")
    f:close()
    if not raw or raw == "" then return { plugins = {}, scanned_at = 0 } end
    local ok, data = pcall(hs.json.decode, raw)
    if ok and type(data) == "table" and type(data.plugins) == "table" then
        return data
    end
    return { plugins = {}, scanned_at = 0 }
end

--- Save scan cache to disk.
---@param data table
function scanner.saveCache(data)
    ShellCreateDirectory(ScriptUserResourcesPath)
    local path = cacheFilePath()
    -- Guard + atomic write, and DON'T fail silently: a swallowed write error
    -- left scanned_at unpersisted, degrading every subsequent run to a full rescan.
    local ok, json = pcall(hs.json.encode, data, true)
    if not ok or type(json) ~= "string" then
        print("[LES][scanner] saveCache: JSON encode failed; cache not written")
        return false
    end
    local tmp = path .. ".tmp"
    local f = io.open(tmp, "w")
    if not f then
        print("[LES][scanner] saveCache: cannot open cache for write: " .. tostring(tmp))
        return false
    end
    f:write(json)
    if not f:close() then
        os.remove(tmp)
        print("[LES][scanner] saveCache: failed to finalize cache write")
        return false
    end
    if not os.rename(tmp, path) then
        os.remove(tmp)
        return false
    end
    return true
end

-- ═══════════════════════════════════════════════════════════════════════
--  Classification
-- ═══════════════════════════════════════════════════════════════════════

--- Classify a plugin name using keyword heuristics.
---@param name string
---@return string|nil
function scanner.classifyByKeyword(name)
    local lower = name:lower()
    for _, rule in ipairs(KEYWORD_CATEGORIES) do
        for _, kw in ipairs(rule.keywords) do
            if lower:find(kw, 1, true) then
                return rule.category
            end
        end
    end
    return nil
end

--- Map a VST3 subcategory string to an LES category.
---@param subcat string
---@return string|nil
function scanner.classifyByVST3Subcat(subcat)
    if not subcat then return nil end
    for _, entry in ipairs(VST3_SUBCAT_MAP) do
        if subcat:find(entry[1], 1, true) then
            return entry[2]
        end
    end
    return nil
end

-- ═══════════════════════════════════════════════════════════════════════
--  System scanning (AU + VST3)
-- ═══════════════════════════════════════════════════════════════════════

--- Parse `system_profiler SPAudioDataType` output.
---@param output string|nil
---@return table
function scanner.parseAUOutput(output)
    local results = {}
    if type(output) ~= "string" or output == "" then return results end

    local currentName = nil
    local linesSinceName = 0
    for line in output:gmatch("[^\n]+") do
        local pluginName = line:match("^%s%s%s%s(%S.+):$")
        if pluginName then
            currentName = pluginName
            linesSinceName = 0
        elseif currentName then
            -- A real AU entry has its "Type:" within a few lines of its name.
            -- Section headers captured by the indent pattern don't, so drop a
            -- candidate name that goes too long without a Type (avoids headers
            -- absorbing an unrelated later Type — #44).
            linesSinceName = linesSinceName + 1
            if linesSinceName > 8 then
                currentName = nil
            end
        end
        if currentName then
            local pluginType = line:match("^%s+Type:%s+(.+)$")
            if pluginType then
                local topCat = "Effects"
                local trimmedType = pluginType:match("^%s*(.-)%s*$")
                if trimmedType == "Music Device" or trimmedType == "Music Effect" then
                    topCat = "Instruments"
                elseif trimmedType == "Generator" then
                    topCat = "Generator"
                end
                local subCat = scanner.classifyByKeyword(currentName)
                table.insert(results, {
                    name     = currentName,
                    format   = "AU",
                    category = subCat or topCat,
                })
                currentName = nil
            end
        end
    end
    return results
end

--- Scan Audio Unit plugins synchronously. Retained for non-UI callers.
---@return table
function scanner.scanAU()
    local handle = io.popen("/usr/sbin/system_profiler SPAudioDataType 2>/dev/null")
    if not handle then return {} end
    local output = handle:read("*a")
    handle:close()
    return scanner.parseAUOutput(output)
end

--- Scan Audio Unit plugins without blocking the Hammerspoon run loop.
---@param callback fun(results: table|nil, err: string|nil)
---@return hs.task|nil task
---@return string|nil err
function scanner.scanAUAsync(callback)
    if type(callback) ~= "function" then
        return nil, "Audio Unit scan callback must be a function"
    end
    if activeAUTask ~= nil then
        return nil, "Audio Unit scan is already running"
    end
    if not hs.task or type(hs.task.new) ~= "function" then
        return nil, "hs.task is unavailable"
    end

    local created, taskOrError = pcall(
        hs.task.new,
        "/usr/sbin/system_profiler",
        function(exitCode, stdOut, stdErr)
            activeAUTask = nil
            if exitCode ~= 0 then
                local detail = tostring(stdErr or ""):match("^%s*(.-)%s*$")
                if detail == "" then detail = "exit " .. tostring(exitCode) end
                callback(nil, "system_profiler failed: " .. detail)
                return
            end
            callback(scanner.parseAUOutput(stdOut), nil)
        end,
        {"SPAudioDataType"}
    )
    if not created or taskOrError == nil then
        return nil, "unable to create system_profiler task: " .. tostring(taskOrError)
    end

    activeAUTask = taskOrError
    local started, startResult = pcall(function() return taskOrError:start() end)
    if not started or not startResult then
        activeAUTask = nil
        return nil, "unable to start system_profiler task: " .. tostring(startResult)
    end
    return taskOrError
end

--- Scan VST3 plugins by reading moduleinfo.json from .vst3 bundles.
---@return table
function scanner.scanVST3()
    local results = {}
    local searchPaths = {
        "/Library/Audio/Plug-Ins/VST3",
        (os.getenv("HOME") or "") .. "/Library/Audio/Plug-Ins/VST3",
    }

    for _, dir in ipairs(searchPaths) do
        -- Use hs.fs.dir instead of shelling out to `ls`; pcall it and tolerate
        -- a missing directory (hs.fs.dir errors if the path does not exist).
        local ok, iter, dirObj = pcall(hs.fs.dir, dir)
        if ok and iter then
            for entry in iter, dirObj do
                if entry ~= "." and entry ~= ".." and entry:match("%.vst3$") then
                    local bundlePath = dir .. "/" .. entry
                    local pluginName = entry:gsub("%.vst3$", "")

                    local category = nil
                    local miPath = bundlePath .. "/Contents/moduleinfo.json"
                    local mf = io.open(miPath, "r")
                    if mf then
                        local raw = mf:read(MAX_MODULEINFO_BYTES + 1)
                        mf:close()
                        if raw and #raw <= MAX_MODULEINFO_BYTES then
                            local subcat = raw:match('"sub_categories"%s*:%s*"([^"]+)"')
                                or raw:match('"subcategories"%s*:%s*%[%s*"([^"]+)"')
                                or raw:match('"category"%s*:%s*"([^"]+)"')
                            category = scanner.classifyByVST3Subcat(subcat)
                        end
                    end

                    if not category then
                        category = scanner.classifyByKeyword(pluginName) or "Effects"
                    end

                    table.insert(results, {
                        name     = pluginName,
                        format   = "VST3",
                        category = category,
                    })
                end
            end
        end
    end
    return results
end

-- ═══════════════════════════════════════════════════════════════════════
--  Full scan: merge AU + VST3, deduplicate
-- ═══════════════════════════════════════════════════════════════════════

---@param auPlugins table
---@param vst3Plugins table
---@return table<string, table>
local function mergePluginLists(auPlugins, vst3Plugins)
    local byName = {}
    for _, p in ipairs(auPlugins) do
        byName[p.name] = { category = p.category, format = p.format }
    end
    for _, p in ipairs(vst3Plugins) do
        local existing = byName[p.name]
        if not existing then
            byName[p.name] = { category = p.category, format = p.format }
        else
            -- Plugin exists in both AU and VST3: always mark it dual-format
            -- (once), regardless of category. The old code only updated the
            -- format when the AU category was generic, so a plugin AU-classified
            -- with a specific category stayed "AU" only (#45).
            if not existing.format:find("VST3", 1, true) then
                existing.format = existing.format .. "/VST3"
            end
            -- Prefer a specific VST3 category over a generic AU one.
            if (existing.category == "Effects" or existing.category == "Instruments")
                and p.category ~= "Effects" and p.category ~= "Instruments" then
                existing.category = p.category
            end
        end
    end
    return byName
end

--- Run a full scan, return flat map { [name] = { category, format } }.
---@return table<string, table>
function scanner.fullScan()
    return mergePluginLists(scanner.scanAU(), scanner.scanVST3())
end

-- ═══════════════════════════════════════════════════════════════════════
--  Incremental scan: compare with cache, return diff
-- ═══════════════════════════════════════════════════════════════════════

---@param cache table
---@param current table<string, table>
---@return table added
---@return table removed
---@return table all
local function computeDiffAndUpdateCache(cache, current)
    local added = {}
    local removed = {}

    for name, info in pairs(current) do
        if not cache.plugins[name] then
            added[name] = info
        end
    end

    for name, info in pairs(cache.plugins) do
        if not current[name] then
            removed[name] = info
        end
    end

    local cacheSaved = scanner.saveCache({
        plugins    = current,
        scanned_at = math.floor(hs.timer.secondsSinceEpoch()),
    })

    local cacheError = cacheSaved and nil or "plugin cache write failed"
    return added, removed, current, cacheError
end

--- Perform incremental scan. Returns added, removed, and full results.
---@return table added   { [name] = { category, format } }
---@return table removed { [name] = { category, format } }
---@return table all     { [name] = { category, format } }
function scanner.incrementalScan()
    local cache = scanner.loadCache()
    local current = scanner.fullScan()
    return computeDiffAndUpdateCache(cache, current)
end

-- ═══════════════════════════════════════════════════════════════════════
--  menuconfig.ini generation and merging
-- ═══════════════════════════════════════════════════════════════════════

--- Group a flat plugin map by category.
---@param plugins table<string, table>
---@return table<string, table[]>
local function groupByCategory(plugins)
    local categorized = {}
    for name, info in pairs(plugins) do
        local cat = info.category
        if not categorized[cat] then categorized[cat] = {} end
        table.insert(categorized[cat], { name = name, format = info.format })
    end
    for _, list in pairs(categorized) do
        table.sort(list, function(a, b) return a.name < b.name end)
    end
    return categorized
end

--- Generate a full menuconfig.ini string from a plugin map.
---@param plugins table<string, table>
---@return string
function scanner.generateMenuconfig(plugins)
    local categorized = groupByCategory(plugins)
    local lines = {}
    local function add(line) lines[#lines + 1] = line end

    add("; Auto-generated by LES Plugin Scanner")
    add("; " .. os.date("%Y-%m-%d %H:%M:%S"))
    add("; Feel free to edit, rearrange, or add plugins manually")
    add("")

    local used = {}
    for _, cat in ipairs(CATEGORY_ORDER) do
        local list = categorized[cat]
        if list and #list > 0 then
            used[cat] = true
            add("/" .. cat)
            for _, p in ipairs(list) do
                add(p.name)
                add('"' .. p.name .. '"')
                add("")
            end
        end
    end

    -- Remaining categories
    local remaining = {}
    for cat, _ in pairs(categorized) do
        if not used[cat] then remaining[#remaining + 1] = cat end
    end
    table.sort(remaining)
    for _, cat in ipairs(remaining) do
        local list = categorized[cat]
        if list and #list > 0 then
            add("/" .. cat)
            for _, p in ipairs(list) do
                add(p.name)
                add('"' .. p.name .. '"')
                add("")
            end
        end
    end

    add("")
    add(";V DONT REMOVE THIS OR THE PROGRAM WILL NOT WORK V")
    add("End")
    return table.concat(lines, "\n")
end

--- Extract plugin names already present in menuconfig.ini.
---@return table<string, boolean>  Set of known plugin names (lowercased)
local function getExistingPluginNames()
    local existing = {}
    local menuLines = {}
    local ok = pcall(function() fileToTable(GetDataPath(MenuConfigFile), menuLines) end)
    if not ok then return existing end

    for _, line in ipairs(menuLines) do
        if type(line) ~= "string" then goto continue end
        -- Skip comments, categories, separators, control lines
        if line:match("^%s*;") or line:match("^%s*$") or line:match("^/")
           or line:match("^%.%.") or line:match("^%-%-") or line:match("^End")
           or line:match('^"') then
            goto continue
        end
        -- This should be a plugin display name
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            existing[trimmed:lower()] = true
        end
        ::continue::
    end
    return existing
end

--- Append new plugins to existing menuconfig.ini (before the End marker).
--- Only adds plugins not already present. Groups by category.
---@param newPlugins table<string, table>  { [name] = { category, format } }
---@return number|nil count Count of plugins actually appended, or nil on persistence failure
---@return string|nil errorMessage
function scanner.appendToMenuconfig(newPlugins)
    local existing = getExistingPluginNames()

    -- Filter out plugins already in menuconfig
    local toAdd = {}
    for name, info in pairs(newPlugins) do
        if not existing[name:lower()] then
            toAdd[name] = info
        end
    end

    -- Count
    local count = 0
    for _ in pairs(toAdd) do count = count + 1 end
    if count == 0 then return 0 end

    -- Read current menuconfig.ini
    local menuLines = {}
    local readCallOK, readResult = pcall(fileToTable, GetDataPath(MenuConfigFile), menuLines)
    if not readCallOK or readResult ~= true then
        return nil, "menuconfig read failed"
    end

    -- Find the "End" marker line index
    local endIdx = nil
    for i = #menuLines, 1, -1 do
        if menuLines[i] and menuLines[i]:find("^End") then
            endIdx = i
            break
        end
    end
    if not endIdx then
        return nil, "menuconfig End marker missing"
    end

    -- Build insertion lines grouped by category
    local categorized = groupByCategory(toAdd)
    local insertLines = {}
    local function add(line) insertLines[#insertLines + 1] = line end

    add("")
    add("; ── New plugins detected " .. os.date("%Y-%m-%d %H:%M") .. " ──")

    for _, cat in ipairs(CATEGORY_ORDER) do
        local list = categorized[cat]
        if list and #list > 0 then
            add("/" .. cat)
            for _, p in ipairs(list) do
                add(p.name)
                add('"' .. p.name .. '"')
                add("")
            end
        end
    end
    -- Remaining categories
    local remaining = {}
    for cat, _ in pairs(categorized) do
        local found = false
        for _, c in ipairs(CATEGORY_ORDER) do
            if c == cat then found = true; break end
        end
        if not found then remaining[#remaining + 1] = cat end
    end
    table.sort(remaining)
    for _, cat in ipairs(remaining) do
        local list = categorized[cat]
        if list and #list > 0 then
            add("/" .. cat)
            for _, p in ipairs(list) do
                add(p.name)
                add('"' .. p.name .. '"')
                add("")
            end
        end
    end

    add("/nocategory")

    -- Insert before End marker
    for i = #insertLines, 1, -1 do
        table.insert(menuLines, endIdx, insertLines[i])
    end

    local writeCallOK, persisted = pcall(tableToFile, GetDataPath(MenuConfigFile), menuLines)
    if not writeCallOK or persisted ~= true then
        return nil, "menuconfig write failed"
    end
    return count
end

--- Back up and atomically replace menuconfig.ini with a generated configuration.
---@param plugins table<string, table>
---@param timestamp number|nil
---@return boolean ok
---@return string|nil errorMessage
---@return string|nil backupFilename
function scanner.saveGeneratedMenuconfig(plugins, timestamp)
    local path = GetDataPath(MenuConfigFile)
    local backupFilename = nil
    local backupTimestamp = math.floor(tonumber(timestamp) or hs.timer.secondsSinceEpoch())
    local hasExistingFile = type(ioIsFilePresent) == "function" and ioIsFilePresent(path)

    if hasExistingFile then
        backupFilename = string.format("menuconfig_%d.ini", backupTimestamp)
        local backupPath = GetDataPath(backupFilename)
        if type(ShellCopy) ~= "function" or ShellCopy(path, backupPath) ~= true then
            return false, "menuconfig backup failed"
        end
    end

    local content = scanner.generateMenuconfig(plugins)
    local lines = {}
    for line in (content .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
    end
    local writeCallOK, persisted = pcall(tableToFile, path, lines)
    if not writeCallOK or persisted ~= true then
        return false, "menuconfig write failed"
    end

    return true, nil, backupFilename
end

-- ═══════════════════════════════════════════════════════════════════════
--  User-facing scan actions (called from menu bar)
-- ═══════════════════════════════════════════════════════════════════════

--- Present dialogs after a scan (added / removed / menuconfig prompts).
---@param hasCache boolean
---@param added table
---@param removed table
---@param all table
local function presentPluginScanResults(hasCache, added, removed, all)
    local addedCount = 0
    for _ in pairs(added) do addedCount = addedCount + 1 end
    local removedCount = 0
    for _ in pairs(removed) do removedCount = removedCount + 1 end
    local totalCount = 0
    for _ in pairs(all) do totalCount = totalCount + 1 end

    if totalCount == 0 then
        HSMakeAlert(
            programName,
            localized("scanner_no_plugins",
                "プラグインが見つかりませんでした。\n\nAU / VST3 プラグインがインストールされているか確認してください。"),
            true
        )
        return
    end

    if not hasCache then
        local message = localizedFormat(
            "scanner_first_scan_prompt",
            "初回スキャン: %d 個のプラグインを検出しました。\n\nカテゴリ分類済みの menuconfig.ini を生成しますか？\n（現在のファイルはバックアップされます）",
            totalCount
        )
        if HSMakeQuery(programName, message) then
            local timestamp = math.floor(hs.timer.secondsSinceEpoch())
            local saved, saveError, backupFilename = scanner.saveGeneratedMenuconfig(all, timestamp)
            if not saved then
                print("[LES][scanner] menuconfig generation failed: " .. tostring(saveError))
                HSMakeAlert(
                    programName,
                    localized("scanner_menuconfig_save_failed",
                        "menuconfig.ini の保存に失敗しました。既存の設定は変更していません。"),
                    true,
                    "warning"
                )
                return
            end
            local backupMessage = backupFilename and ("\n" .. localizedFormat(
                "scanner_backup_created", "バックアップ: %s", backupFilename)) or ""
            HSMakeAlert(
                programName,
                localizedFormat(
                    "scanner_menuconfig_generated",
                    "menuconfig.ini を生成しました（%d プラグイン）%s",
                    totalCount, backupMessage
                ),
                true
            )
            reloadLES()
        end
        return
    end

    if addedCount == 0 and removedCount == 0 then
        HSMakeAlert(
            programName,
            localizedFormat(
                "scanner_no_changes",
                "変更なし（%d プラグイン検出済み）\n\n新しいプラグインは見つかりませんでした。",
                totalCount
            ),
            true
        )
        return
    end

    local parts = {}
    if addedCount > 0 then
        parts[#parts + 1] = localizedFormat("scanner_new_count", "新規: %d 個", addedCount)
        local names = {}
        for name, _ in pairs(added) do
            names[#names + 1] = name
            if #names >= 5 then break end
        end
        table.sort(names)
        for _, n in ipairs(names) do
            parts[#parts + 1] = "  + " .. n
        end
        if addedCount > 5 then
            parts[#parts + 1] = localizedFormat(
                "scanner_more_count", "  ... 他 %d 個", addedCount - 5)
        end
    end
    if removedCount > 0 then
        parts[#parts + 1] = localizedFormat(
            "scanner_removed_count", "\nアンインストール済み: %d 個", removedCount)
    end

    local message = table.concat(parts, "\n")
        .. "\n\n" .. localized("scanner_append_prompt",
            "新規プラグインを menuconfig.ini に追加しますか？\n（既存のメニュー構成は維持されます）")

    if HSMakeQuery(programName, message) then
        local appended, appendError = scanner.appendToMenuconfig(added)
        if appended == nil then
            print("[LES][scanner] menuconfig append failed: " .. tostring(appendError))
            HSMakeAlert(
                programName,
                localized("scanner_menuconfig_save_failed",
                    "menuconfig.ini の保存に失敗しました。既存の設定は変更していません。"),
                true,
                "warning"
            )
        elseif appended > 0 then
            HSMakeAlert(
                programName,
                localizedFormat(
                    "scanner_plugins_appended",
                    "%d 個のプラグインを menuconfig.ini に追加しました。",
                    appended),
                true
            )
            reloadLES()
        else
            HSMakeAlert(
                programName,
                localized("scanner_plugins_already_present",
                    "追加対象のプラグインはすべて menuconfig.ini に存在していました。"),
                true
            )
        end
    end
end

--- Incremental scan: detect new plugins and append to menuconfig.ini.
--- Shows a progress window (AU → VST3 → merge) so long system_profiler runs are visible.
function scanner.scanAndPrompt()
    if scanInProgress then
        showScanProgress()
        return false
    end

    scanInProgress = true
    scanProgressPercent = 0
    scanProgressLabel = localized("scanner_preparing", "準備中…")
    openScanProgress()
    setScanProgress(2, localized("scanner_preparing", "準備中…"))

    hs.timer.doAfter(0.08, function()
        local ok, err = pcall(function()
            local cache = scanner.loadCache()
            local hasCache = cache.scanned_at > 0
            setScanProgress(10, localized("scanner_detecting_au", "Audio Units を検出中（system_profiler）…"))
            local task, taskError = scanner.scanAUAsync(function(auPlugins, auError)
                if auError then
                    scanInProgress = false
                    closeScanProgress()
                    HSMakeAlert(programName, localizedFormat(
                        "scanner_au_error", "Audio Unit スキャンでエラー:\n%s", auError), true, "critical")
                    return
                end

                hs.timer.doAfter(0.08, function()
                    local ok2, err2 = pcall(function()
                        setScanProgress(44, localized("scanner_detecting_vst3", "VST3 バンドルを検出中…"))
                        local vst3Plugins = scanner.scanVST3()
                        hs.timer.doAfter(0.08, function()
                            local ok3, err3 = pcall(function()
                                setScanProgress(78, localized("scanner_updating_cache", "統合とキャッシュを更新…"))
                                local merged = mergePluginLists(auPlugins, vst3Plugins)
                                local added, removed, _, cacheError = computeDiffAndUpdateCache(cache, merged)
                                if cacheError then
                                    scanInProgress = false
                                    closeScanProgress()
                                    HSMakeAlert(
                                        programName,
                                        localized("scanner_cache_save_failed",
                                            "Plugin cache could not be saved. Check folder permissions and free space."),
                                        true,
                                        "warning"
                                    )
                                    return
                                end
                                setScanProgress(100, localized("scanner_complete", "完了"))
                                scanInProgress = false
                                closeScanProgress()
                                presentPluginScanResults(hasCache, added, removed, merged)
                            end)
                            if not ok3 then
                                scanInProgress = false
                                closeScanProgress()
                                HSMakeAlert(programName, localizedFormat(
                                    "scanner_finish_error", "スキャン完了処理でエラー:\n%s", tostring(err3)),
                                    true, "critical")
                            end
                        end)
                    end)
                    if not ok2 then
                        scanInProgress = false
                        closeScanProgress()
                        HSMakeAlert(programName, localizedFormat(
                            "scanner_vst3_error", "VST3 スキャンでエラー:\n%s", tostring(err2)),
                            true, "critical")
                    end
                end)
            end)
            if not task then error(taskError) end
        end)
        if not ok then
            scanInProgress = false
            closeScanProgress()
            HSMakeAlert(programName, localizedFormat(
                "scanner_start_error", "スキャン開始でエラー:\n%s", tostring(err)), true, "critical")
        end
    end)
    return true
end

--- Force a full rescan, ignoring cache. Regenerates menuconfig.ini entirely.
function scanner.forceFullScan()
    if scanInProgress then
        showScanProgress()
        return false
    end
    -- Clear cache to force fresh scan
    if not scanner.saveCache({ plugins = {}, scanned_at = 0 }) then
        HSMakeAlert(
            programName,
            localized("scanner_cache_clear_failed",
                "Plugin cache could not be cleared. The full scan was not started."),
            true,
            "warning"
        )
        return false
    end
    scanner.scanAndPrompt()
    return true
end

return scanner

--  SPDX-License-Identifier: MIT
--
--  Copyright (c) 2019-2023 LESforMacOS authors, see AUTHORS.txt
--  for a list
--
--  Distributed under the MIT software license, see the accompanying
--  file COPYING.txt or visit https://opensource.org/license/mit/

require("globals.constants")
require("helpers")

-- TODO: use default keys to allow repairing the settings
--       file without forcing a complete rewrite of its values
settingsManager = {
  ["autoadd"]                 = { ["value"] = nil, ["default"] = "1"  , ["type"] = "bin",
                                  ["desc"] = { "Automatically add plugins after looking them up" } },
  ["resettobrowserbookmark"]  = { ["value"] = nil, ["default"] = "0"  , ["type"] = "bin",
                                  ["desc"] = { "Optional feature where LES will click a certain point on your screen after using the menu.",
                                               "This can be used to click a collection, or close a browser", "",
                                               "Due to limitations in macOS, this feature is only enabled on fullscreen mode" } },
  ["disableloop"]             = { ["value"] = nil, ["default"] = "1"  , ["type"] = "bin",
                                  ["desc"] = { "This prevents the loop button from being enabled by default in MIDI clips created",
                                               "with the Cmd + Shift + M shortcut" } },
  ["saveasnewver"]            = { ["value"] = nil, ["default"] = "1"  , ["type"] = "bin",
                                  ["desc"] = { "Toggles the cmd + alt + s shortcut that duplicates and saves your project as a new version",
                                               "similar to FL Studio. The syntax is in this format [project name]_[version]" } },
  ["altgrmarker"]             = { ["value"] = nil, ["default"] = "1"  , ["type"] = "bin",
                                  ["desc"] = { "Switches the marker shortcut from Shift + L to Alt + L",
                                               "It is recommended to keep this on in the mac version if you like capitalising letters" } },
  ["double0todelete"]         = { ["value"] = nil, ["default"] = "1"  , ["type"] = "bin",
                                  ["desc"] = { "Toggles the double 0 to delete shortcut" } },
  ["absolutereplace"]         = { ["value"] = nil, ["default"] = "1"  , ["type"] = "bin",
                                  ["desc"] = { "Toggles the shortcuts Ctrl + Alt + D and Ctrl + Alt + V", "",
                                               "It's best to disable this feature if you want to use video in your project files since",
                                               "Ctrl + Alt + V is actually a taken shortcut in this scenario" } },
  ["ctrlabsoluteduplicate"]   = { ["value"] = nil, ["default"] = "0"  , ["type"] = "bin",
                                  ["desc"] = { "Maps the absolute duplicate shortcut to Cmd + Ctrl + D if you don't want to disable or",
                                               "overwrite the default dock hide/unhide shortcut on Preferences > Keyboard > Shortcuts" } },
  ["enableclosewindow"]       = { ["value"] = nil, ["default"] = "1"  , ["type"] = "bin",
                                  ["desc"] = { "Toggles Cmd+W and Cmd+Alt+W (or Cmd+Alt+Esc) for plugin windows" } },
  ["vstshortcuts"]            = { ["value"] = nil, ["default"] = "1"  , ["type"] = "bin",
                                  ["desc"] = { "Toggles the suite of VST specific shortcuts" } },
  ["dynamicreload"]           = { ["value"] = nil, ["default"] = "0"  , ["type"] = "bin",
                                  ["desc"] = { "Setting that sets LES to refresh menuconfig.ini contents every time the menu is opened",
                                               "Not recommended to be used alongside large config files. Performance hit depends on hardware" } },
  ["texticon"]                = { ["value"] = nil, ["default"] = "0"  , ["type"] = "bin",
                                  ["desc"] = { "Replaces the menubar icon graphic in the top right with text saying \"LES\"" } },
  ["addtostartup"]            = { ["value"] = nil, ["default"] = "0"  , ["type"] = "bin",
                                  ["desc"] = { "Sets LES to launch on login" } },
  ["enabledebug"]             = { ["value"] = nil, ["default"] = "0"  , ["type"] = "bin",
                                  ["desc"] = { "Toggles access to debug options used for development, such as the console" } },
  ["pianorollmacro"]          = { ["value"] = nil, ["default"] = "`"  , ["type"] = "str",
                                  ["desc"] = { "The key that is used as the piano roll macro", "",
                                               "If you want to remap the piano roll macro, remove the set value and then replace it",
                                               "with the character that the key you want to remap it to corresponds to without modifiers", "",
                                               "So if you want to remap it to the 1 key, just type \"1\"" } },
  ["bookmarkx"]               = { ["value"] = nil, ["default"] = "500", ["type"] = "int",
                                  ["desc"] = { "The X coordinates (in pixels) which is clicked at, selected at random"} },
  ["bookmarky"]               = { ["value"] = nil, ["default"] = "500", ["type"] = "int",
                                  ["desc"] = { "The Y coordinates (in pixels) which is clicked at, selected at random" } },
  ["loadspeed"]               = { ["value"] = nil, ["default"] = "0.3", ["type"] = "flt",
                                  ["desc"] = { "Amount of seconds it takes for LES to attempt to add the item after looking it up", "",
                                               "Increase this value if you have a slow hard disk, which could cause LES to try to add",
                                               "items before they've been found" } },
  ["checksanity"]             = { ["value"] = nil, ["default"] = "1"  , ["type"] = "bin",
                                  ["desc"] = { "Toggles validation of supported macOS and Ableton Live versions" } },
  ["launchwithlive"]          = { ["value"] = nil, ["default"] = "0"  , ["type"] = "bin",
                                  ["desc"] = { "Launches LES automatically when Ableton Live is started",
                                               "Uses a background Launch Agent to monitor for the Live process" } },
  ["notifyexport"]            = { ["value"] = nil, ["default"] = "1"  , ["type"] = "bin",
                                  ["desc"] = { "Show a macOS notification when Ableton Live finishes rendering/exporting" } },
  ["notifyhourly"]            = { ["value"] = nil, ["default"] = "1"  , ["type"] = "bin",
                                  ["desc"] = { "Show a macOS notification each time the current project session reaches a new hour" } },
  ["openaikey"]               = { ["value"] = nil, ["default"] = "未設定", ["type"] = "str",
                                  ["desc"] = { "OpenAI API key for AI features (chat assistant, plugin recommendations, etc.)",
                                               "Get your key at https://platform.openai.com/api-keys" } },
  ["openaimodel"]             = { ["value"] = nil, ["default"] = "gpt-4o-mini", ["type"] = "str",
                                  ["desc"] = { "OpenAI model name used for AI features",
                                               "Examples: gpt-4o-mini, gpt-4o, gpt-4.1-mini" } },
  ["language"]                = { ["value"] = nil, ["default"] = "ja", ["type"] = "str",
                                  ["desc"] = { "UI language: en or ja" } },
}

function settingsManager.bind(self)
  -- Avoid touching functions
  for key, val in pairs(self) do
    if type(val) == "table" then
      self[key]["value"] = nil
    end
  end
end

function settingsPanicAndExit(message, range)
  panicExit(
    string.format([[settingsPanicAndExit(): Value for "%s" is not %s]], message, range),
    function()
      ShellNSOpen(strJoinPaths(ScriptUserPath, "settings.ini"), "TextEdit")
    end
  )
end

function settingsManager.getVal(self, key)
  return self[key]["value"]
end

--- Validate every settings boundary consistently before updating disk or memory.
--- GUI strings remain compatible with numeric callers, but objects/booleans,
--- non-finite numbers, fractional integers and invalid toggles are rejected.
---@param setting table|nil
---@param value any
---@return boolean
local function isValidSettingValue(setting, value)
  if type(setting) ~= "table" then return false end
  local valueType = type(value)
  if valueType ~= "string" and valueType ~= "number" then return false end
  local num = tonumber(value)
  if valueType == "number" and (num ~= num or num == math.huge or num == -math.huge) then return false end
  local settingType = setting["type"]
  if settingType == "str" then return true end
  if num == nil or num ~= num or num == math.huge or num == -math.huge or num < 0 then return false end
  if settingType == "bin" then return num == 0 or num == 1 end
  if settingType == "int" then return num % 1 == 0 end
  return settingType == "flt"
end

--- Set a value in memory. NON-fatal on bad numeric input: a malformed number
--- is logged and left nil (so init() can self-heal from the default) or falls
--- back to the type default — never panicExit() (that killed the app mid-save).
---@param self table
---@param key string
---@param value string|number
function settingsManager.setVal(self, key, value)
  if type(self[key]) ~= "table" then return false end
  local _type = self[key]["type"]
  if _type == "int"
     or _type == "flt"
     or _type == "bin"
  then
    local num = tonumber(value)
    if isValidSettingValue(self[key], value) then
      self[key]["value"] = num
    else
      -- Do NOT panicExit: log, fall back to the parsed default if possible,
      -- otherwise leave nil so init() backfills it from the default line.
      print(string.format(
        [[setVal(): invalid value for key "%s" of type %s; falling back to default]],
        tostring(key), tostring(_type)
      ))
      self[key]["value"] = tonumber(self[key]["default"])
    end
  else
    if not isValidSettingValue(self[key], value) then
      print("setVal(): invalid string value for key " .. tostring(key))
      return false
    end
    -- String settings (C5/C6 self-heal): heal an already-corrupted
    -- "未設定sk-..." back to "sk-..." by stripping the leading sentinel — BUT
    -- preserve the exact default sentinel '未設定' itself (settings.lua:74).
    -- Gate on '^未設定.+' so a bare '未設定' (the unset default) round-trips
    -- intact; only '未設定'+key is healed. An unconditional gsub turned the
    -- default into '' on every default load (disk/memory divergence).
    if key == "openaikey" and type(value) == "string" and value:match("^未設定.+") then
      value = (value:gsub("^未設定", ""))
    end
    self[key]["value"] = value
  end
end

--- Normalize a raw settings.ini value: trim surrounding whitespace and strip
--- control characters. Deliberately does NOT truncate at ';' — settings.ini is
--- machine-written and full-line ';' comments are handled by
--- isLesIniSkippableLine, so str values (API keys, model names) round-trip
--- intact. Used by both load() and the writers so disk == memory == reloaded.
---@param key string
---@param raw string|number|nil
---@return string
local function normalizeIni(key, raw)
  local v = tostring(raw or ""):match("^%s*(.-)%s*$") or ""
  return (v:gsub("%c", ""))
end

-- One settings.ini assignment line. Never use string.format with user values — a lone "%"
-- in an API key or model name breaks format and can corrupt the file on save.
-- Defined here (before init/writeVal/writeFromGui) so all of them capture it as
-- an upvalue rather than resolving a nil global.
---@param key string
---@param val string|number|nil
---@return string
local function formatSettingsLine(key, val)
  return key .. " = " .. normalizeIni(key, val)
end

-- Skip blank / full-line comment / legacy "End" terminator only (not substring "End" in values).
local function isLesIniSkippableLine(line)
  if type(line) ~= "string" or line == "" then
    return true
  end
  local trimmed = (line:match("^%s*(.-)%s*$") or "")
  if trimmed == "" then
    return true
  end
  if trimmed:sub(1, 1) == ";" then
    return true
  end
  if trimmed:match("^End%s*;?%s*$") then
    return true
  end
  return false
end

function settingsManager.load(self, fileTable)
  -- Invalid on-disk values are skipped without aborting startup. init() can
  -- then backfill them with their declared, type-checked defaults.
  -- O(n) single-pass: extract key from each line, then look up in self
  for idx = 1, #fileTable, 1 do
    local line = fileTable[idx];
    -- skip unparseable lines
    if line == nil or isLesIniSkippableLine(line) then
      goto continue_strmgr_loop
    end
    -- Extract "key = value" with a single pattern match (O(1) per line).
    -- ".-" (non-greedy, B1) lets a present-but-empty line "key = " parse to ""
    -- instead of being dropped, so an explicitly-cleared field stays cleared.
    local key, _val = line:match("^(%w+)%s*=%s*(.-)$")
    if key and type(self[key]) == "table" then
      local sType = self[key]["type"]
      _val = normalizeIni(key, _val)
      -- Legacy AHK-style `key = val ; comment` support ONLY for non-string
      -- types. Truncate at the FIRST ';' (numeric values never contain a
      -- literal ';', so any ';' is a trailing comment, even without preceding
      -- whitespace: "bookmarkx = 800;note" -> "800"). str values (API keys,
      -- model names) must round-trip a literal ';' untouched, so the gate stays.
      if sType ~= "str" then
        local sc = _val:find(";")
        if sc then
          _val = normalizeIni(key, _val:sub(1, sc - 1))
        end
      end
      print(string.format("%s found", key))
      -- Wrap validate+setVal so no validator/setter bug can os.exit() at boot.
      -- A malformed numeric line leaves the value nil → init() backfills it.
      if isValidSettingValue(self[key], _val) then
        local ok, err = pcall(function() self:setVal(key, _val) end)
        if not ok then
          print(string.format("settingsManager.load(): setVal failed for \"%s\": %s", key, tostring(err)))
        end
      else
        print(string.format("settingsManager.load(): skipping malformed value for \"%s\" (self-heal)", key))
      end
    end
    ::continue_strmgr_loop::
  end
end

function settingsManager.map(self)
  -- Consolidated config table for new code to reference.
  -- Prefer _G.LES_CONFIG.key over bare _G.key in new modules.
  _G.LES_CONFIG = _G.LES_CONFIG or {}

  -- Mapping from settingsManager key → global variable name
  -- (most are identical; only "language" differs)
  local KEY_ALIASES = { language = "uiLanguage" }

  -- Sensitive keys (C5): never copy into _G or _G.LES_CONFIG. The API key must
  -- only be reachable via settingsManager["openaikey"]["value"] so it can't leak
  -- through global-state dumps / accidental logging of the config table.
  local SENSITIVE = { openaikey = true }

  -- Defensively clear any stale plaintext of a sensitive key from BOTH global
  -- tables BEFORE the copy loop. A same-VM reload (e.g. after the user deletes
  -- the API key) must never leave a previous value reachable through _G /
  -- _G.LES_CONFIG just because the copy loop skips sensitive keys (it never
  -- overwrites them, so a prior leak would otherwise persist).
  for k in pairs(SENSITIVE) do
    local g = KEY_ALIASES[k] or k
    _G[g] = nil
    if _G.LES_CONFIG then _G.LES_CONFIG[g] = nil end
  end

  for key, val in pairs(self) do
    if type(val) == "table" and not SENSITIVE[key] then
      local globalName = KEY_ALIASES[key] or key
      local value = val["value"]
      _G[globalName] = value
      _G.LES_CONFIG[globalName] = value
    end
  end
end

--- Tighten permissions on the config file (600) and its directory (700) after
--- every write so a stored API key isn't world/group readable. The chmod
--- helpers (C4) live in helpers.lua, which is required before settings; guard
--- with type()=="function" so settings still loads if they aren't present yet.
local function secureSettingsFiles()
  if type(SetSecureDirMode) == "function" then
    SetSecureDirMode(ScriptUserPath)
  end
  if type(SetSecureFileMode) == "function" and ioIsFilePresent(GetDataPath(ConfigFile)) then
    SetSecureFileMode(GetDataPath(ConfigFile))
  end

  -- Older versions created timestamped backups using the default umask. Secure
  -- every retained backup as well so an API key cannot remain group-readable.
  if type(SetSecureFileMode) == "function" then
    local ok, scanError = pcall(function()
      -- Keep the complete iterator tuple, including the native directory state
      -- and Lua 5.4 close value, by iterating directly inside the protected call.
      for file in hs.fs.dir(ScriptUserPath) do
        if type(file) == "string" and file:match("^settings_%d+%.ini$") then
          SetSecureFileMode(strJoinPaths(ScriptUserPath, file))
        end
      end
    end)
    if not ok then
      print("[settings] unable to secure retained backups: " .. tostring(scanError))
    end
  end
end

--- Backfill missing settings into settings.ini. Existing lines whose key is
--- present (e.g. a malformed numeric that load() skipped) are rewritten IN
--- PLACE via formatSettingsLine; a key with no line at all is appended with its
--- description block. _depth guards against infinite re-init / backup spam:
--- init() re-attempts the load at most once.
---@param self table
---@param _depth integer|nil  internal recursion depth (do not pass externally)
function settingsManager.init(self, _depth)
  _depth = _depth or 0
  ShellCreateDirectory(ScriptUserPath)

  -- Create new settings file if it doesn't exist
  if ioIsFilePresent(GetDataPath(ConfigFile)) == false then
    -- ioIsFilePresent checks readability, not existence. Never truncate an
    -- existing unreadable file (or dangling link) when handling first run.
    if hs and hs.fs and type(hs.fs.symlinkAttributes) == "function" then
      local inspected, existing = pcall(hs.fs.symlinkAttributes, GetDataPath(ConfigFile))
      if not inspected or existing ~= nil then
        print("settingsManager.init(): existing settings.ini is unavailable; keeping current settings")
        return false
      end
    end
    ShellCreateEmptyFile(GetDataPath(ConfigFile))
  end
  -- Apply permissions on every startup, including already-valid files created
  -- by older versions where no write/backfill would otherwise occur.
  secureSettingsFiles()

  -- Read settings file and load it (always under ~/.les/, never CWD-relative)
  local settingsFile = {}
  if not fileToTable(GetDataPath(ConfigFile), settingsFile) then
    print("settingsManager.init(): unable to read settings.ini; preserving file and loaded values")
    return false
  end
  -- Only replace loaded values after a successful read. A transient read error
  -- must not erase the working configuration or trigger a destructive backfill.
  self:bind()
  self:load(settingsFile)

  -- Check if every settings value has been loaded from the configuration file
  local valuesAllLoaded = true
  local valuesPending = {}
  for key, val in pairs(self) do
    -- We're only interested in inspecting values, not functions
    if type(val) == "table" then
      if self:getVal(key) == nil then
        valuesAllLoaded = false
        table.insert(valuesPending, key)
        print(string.format("settingsManager.init(): unable to load \"%s\", not defined in settings.ini", key))
      end
    end
  end

  if valuesAllLoaded == false then
    -- Stop recursing after the first backfill+reload attempt (avoid infinite
    -- re-init and a flood of timestamped backup files if a value never loads).
    if _depth >= 1 then
      print("settingsManager.init(): backfill did not resolve all values; stopping recursion")
      return false
    end

    -- Backup current settings file. Only when it exists (avoids spamming an
    -- empty timestamped backup on first run), secure the copy to 600 (it holds
    -- the OpenAI key and ShellCopy writes at the default umask = 644), and prune
    -- old backups so they cannot accumulate without bound.
    local srcPath = strJoinPaths(ScriptUserPath, "settings.ini")
    if ioIsFilePresent(srcPath) then
      local backupPath = strJoinPaths(ScriptUserPath,
        string.format("settings_%d.ini", math.floor(hs.timer.secondsSinceEpoch())))
      ShellCopy(srcPath, backupPath)
      if type(SetSecureFileMode) == "function" then SetSecureFileMode(backupPath) end

      -- Keep only the 5 most recent settings_<epoch>.ini backups. Index hs.fs
      -- INSIDE the pcall closure so a missing hs.fs (e.g. test env) is caught
      -- rather than thrown while evaluating the argument.
      local ok, pruneError = pcall(function()
        local backups = {}
        for file in hs.fs.dir(ScriptUserPath) do
          if type(file) == "string" and file:match("^settings_%d+%.ini$") then
            backups[#backups + 1] = file
          end
        end
        table.sort(backups)  -- fixed-width epoch names sort chronologically
        for i = 1, #backups - 5 do
          local removed, removeError = os.remove(strJoinPaths(ScriptUserPath, backups[i]))
          if not removed then
            print("[settings] unable to remove old backup: " .. tostring(removeError))
          end
        end
      end)
      if not ok then
        print("[settings] unable to inspect retained backups for pruning: " .. tostring(pruneError))
      end
    end

    -- Write defaults to settings file in memory
    for _, skey in ipairs(valuesPending) do
      local sval = self[skey]["default"]
      -- If a line for this key already exists on disk (e.g. a malformed value
      -- that load() skipped), rewrite it IN PLACE rather than appending a
      -- duplicate. Only insert a fresh description+default block when absent.
      local found = false
      for idx = 1, #settingsFile, 1 do
        local line = settingsFile[idx]
        if line ~= nil and not isLesIniSkippableLine(line) then
          local lineKey = line:match("^(%w+)%s*=")
          if lineKey == skey then
            settingsFile[idx] = formatSettingsLine(skey, sval)
            found = true
            break
          end
        end
      end
      if not found then
        -- Print out the description of the setting 'key'
        for _, descLine in ipairs(self[skey]["desc"]) do
          table.insert(settingsFile, string.format("; %s", descLine))
        end
        -- Print out the expected default pair
        table.insert(settingsFile, formatSettingsLine(skey, sval))
        -- Add newline to distinguish between each setting
        table.insert(settingsFile, "")
      end
      print(string.format("settingsManager.init(): setting \"%s\" to \"%s\" in settings table", skey, tostring(sval)))
    end

    -- Flush settings file to disk
    if not tableToFile(GetDataPath(ConfigFile), settingsFile) then
      print("settingsManager.init(): unable to write settings.ini defaults")
      return false
    end
    secureSettingsFiles()
    print("settingsManager.init(): flushed settings.ini to disk, reattempting to load configuration file")
    -- Re-load configuration file and hope 'valuesAllLoaded' is true this time
    return self:init(_depth + 1)
  end
  return true
end

-- This is the closest thing we have to a real setVal, current setVal
-- only changes values in memory, this only changes values on disk.
-- Currently we use setVal to set the value of something that has been
-- interpreted after-the-fact in way that the rest of the program depends
-- on.
--
-- Until we have figured out moving all the program's internal state
-- out of the global state and keep it distinct from settings
-- values, it's going to be a bit of a mess...

function settingsManager.writeVal(self, key, val)
    if type(key) ~= "string" or not isValidSettingValue(self[key], val) then
      print("[settings] writeVal: invalid key or value; keeping current settings")
      return false
    end
    ShellCreateDirectory(ScriptUserPath)
    local settingsFile = {}
    if not fileToTable(GetDataPath(ConfigFile), settingsFile) then
      print("[settings] writeVal: unable to read settings.ini; keeping current settings")
      return false
    end
    local replaced = false
    for idx = 1, #settingsFile, 1 do
        local line = settingsFile[idx]
        if line == nil or isLesIniSkippableLine(line) then
            goto continue_writeval_loop
        end

        local lineKey = line:match("^(%w+)%s*=")
        if lineKey == key then
            settingsFile[idx] = formatSettingsLine(key, val)
            replaced = true
        end
        ::continue_writeval_loop::
    end
    if not replaced then
        table.insert(settingsFile, formatSettingsLine(key, val))
    end
    local ok = tableToFile(GetDataPath(ConfigFile), settingsFile)
    if ok then
        secureSettingsFiles()
    end
    return ok
end

--- Apply many settings in one read/write of settings.ini (avoids races and is safer for the GUI).
--- Only keys that exist on settingsManager as a value table are applied; others are ignored.
---@param self table
---@param kv table<string, string|number>  key -> raw value from the settings webview
---@return boolean ok
function settingsManager.writeFromGui(self, kv)
    if type(kv) ~= "table" then
      print("[settings] writeFromGui: kv is not a table (" .. tostring(type(kv)) .. ")")
      return false
    end
    local validPatch = {}
    for key, val in pairs(kv) do
      if type(key) == "string" and type(self[key]) == "table" then
        if not isValidSettingValue(self[key], val) then
          -- Never log raw input: even a malformed field may contain a secret.
          print("[settings] writeFromGui: invalid value for " .. key .. "; keeping current settings")
          return false
        end
        validPatch[key] = val
      end
    end
    if next(validPatch) == nil then return false end
    ShellCreateDirectory(ScriptUserPath)
    local settingsFile = {}
    if not fileToTable(GetDataPath(ConfigFile), settingsFile) then
      print("[settings] writeFromGui: unable to read settings.ini; keeping current settings")
      return false
    end

    local function applyOneKey(key, val)
        if type(key) ~= "string" or type(self[key]) ~= "table" then return end
        local replaced = false
        for idx = 1, #settingsFile, 1 do
            local line = settingsFile[idx]
            if line == nil or isLesIniSkippableLine(line) then
                goto continue_gui_write_loop
            end
            local lineKey = line:match("^(%w+)%s*=")
            if lineKey == key then
                settingsFile[idx] = formatSettingsLine(key, val)
                replaced = true
            end
            ::continue_gui_write_loop::
        end
        if not replaced then
            table.insert(settingsFile, formatSettingsLine(key, val))
        end
    end

    local nPatch = 0
    for key, val in pairs(validPatch) do
        applyOneKey(key, val)
        nPatch = nPatch + 1
    end

    local outPath = GetDataPath(ConfigFile)
    print(string.format("[settings] writeFromGui: writing %d keys to %s", nPatch, tostring(outPath)))
    if not tableToFile(outPath, settingsFile) then
      print("[settings] writeFromGui: tableToFile failed (disk full or permission?) path=" .. tostring(outPath))
      return false
    end
    secureSettingsFiles()

    -- Mirror disk into memory through the SAME normalizeIni() the writer used,
    -- so the in-memory value equals exactly what a fresh load() would parse
    -- (disk == memory == reloaded). pcall keeps a setter bug from bubbling up
    -- out of a GUI save.
    for key, val in pairs(validPatch) do
        local ok, err = pcall(function() self:setVal(key, normalizeIni(key, val)) end)
        if not ok then
            print(string.format("[settings] writeFromGui: setVal failed for %q: %s", key, tostring(err)))
        end
    end
    return true
end

function settingsManager.parse(self)
  -- We are relying on module.init further down the line to make sure
  -- this code path isn't erroneously called again
  if ioIsFilePresent(GetDataPath("resources/firstrun.txt")) == false then
    if HSMakeQuery(programName, L("settings_startup_query")) == true then
      settingsManager:writeVal("addtostartup", "1")
    else
      settingsManager:writeVal("addtostartup", "0")
    end
  end

  if settingsManager:getVal("pianorollmacro") == nil
     or hs.keycodes.map[
        -- We need to explicitly make sure that it is passed as a string
        -- as possible evaluation as a number will return the keycode mapped by
        -- index rather than corresponding keyboard key
        tostring(settingsManager:getVal("pianorollmacro"))
      ] == nil
     and _G.nomacro == nil
  then
    -- there is an alternate error message here because the generic one confused too many people.
    HSMakeAlert(programName, L("settings_pianoroll_error"), true, "critical")
    ShellNSOpen(strJoinPaths(ScriptUserPath, "settings.ini"), "TextEdit")
    _G.nomacro = true
  else
    -- We're not doing the assignment through setVal because
    -- while "pianorollmacro" _is_ stored as a string, we substitute
    -- the global from the configuration value to its equivalent hammerspoon
    -- mapping code, which is numerical and _not_ the same as the
    -- configuration value
    --
    -- TODO: Make the corresponding keycode a distinct variable so we can offer
    --       reset capabilities
    settingsManager["pianorollmacro"]["value"] =
      tonumber(
        hs.keycodes.map[
          tostring(settingsManager:getVal("pianorollmacro"))
        ]
      )
    _G.nomacro = false
  end
end

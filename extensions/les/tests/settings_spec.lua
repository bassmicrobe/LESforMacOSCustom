--  SPDX-License-Identifier: MIT
--
--  LES unit tests for settings.lua
--
--  These tests exercise the full settings GUI save → reload round trip:
--  settingsManager:init() (default generation), writeFromGui() (GUI save),
--  writeVal(), and load() re-parsing what was written to disk.
--
--  Run with: busted extensions/les/tests/
--  Or via Docker: docker build -f Dockerfile.test -t les-test . && docker run --rm les-test

-- ── Test sandbox ──────────────────────────────────────────────────────

local TEST_DIR = "/tmp/lua_les_settings_test"
os.execute("rm -rf '" .. TEST_DIR .. "' && mkdir -p '" .. TEST_DIR .. "'")

-- Mock hs before anything requires it
local hs_mock = {
    timer = {
        secondsSinceEpoch = function() return 1000000 end,
    },
    keycodes = {
        map = { ["`"] = 50, ["1"] = 18 },
    },
}
rawset(_G, "hs", rawget(_G, "hs") or hs_mock)

package.path = package.path .. ";extensions/les/?.lua"

-- helpers.lua pulls in hs APIs we don't have here; the few helper globals
-- settings.lua actually calls are stubbed below instead
package.preload["helpers"] = function() end

require("globals.constants")
require("util.string")
require("util.io")

-- Globals normally provided by globals/* and helpers.lua.
-- NOTE: rawset on _G is required — busted insulates plain global writes in
-- spec files, but settings.lua (loaded via require) resolves through real _G.
rawset(_G, "ScriptUserPath", TEST_DIR)
rawset(_G, "ConfigFile", "settings.ini")
rawset(_G, "programName", "LES-test")
rawset(_G, "GetDataPath", function(path) return strJoinPaths(ScriptUserPath, path) end)
rawset(_G, "L", function(key) return key end)
rawset(_G, "ShellNSOpen", function() end)
rawset(_G, "ShellCopy", function() end)
rawset(_G, "ShellCreateDirectory", function(path) os.execute("mkdir -p '" .. path .. "'") end)
rawset(_G, "ShellCreateEmptyFile", function(path) local f = io.open(path, "w"); if f then f:close() end end)
rawset(_G, "HSMakeQuery", function() return false end)
rawset(_G, "HSMakeAlert", function() end)

local secureFileCalls = 0
local secureDirCalls = 0
rawset(_G, "SetSecureFileMode", function() secureFileCalls = secureFileCalls + 1 end)
rawset(_G, "SetSecureDirMode", function() secureDirCalls = secureDirCalls + 1 end)

-- panicExit must be observable: record the message instead of killing busted
local panicMessage = nil
rawset(_G, "panicExit", function(message)
    panicMessage = message
    error("panicExit: " .. tostring(message), 0)
end)

require("settings")

-- ── Helpers ───────────────────────────────────────────────────────────

local function freshInit()
    panicMessage = nil
    os.execute("rm -f '" .. TEST_DIR .. "/settings.ini'")
    settingsManager:init()
end

--- Simulate quitting and restarting LES: re-read settings.ini from disk.
local function simulateRestart()
    settingsManager:init()
end

local function readSettings()
    local file = assert(io.open(TEST_DIR .. "/settings.ini", "r"))
    local content = assert(file:read("*a"))
    assert(file:close())
    return content
end

-- ── Tests ─────────────────────────────────────────────────────────────

describe("settingsManager", function()
    before_each(function()
        freshInit()
    end)

    describe("init", function()
        it("generates a complete settings.ini with defaults", function()
            assert.are.equal(1, settingsManager:getVal("autoadd"))
            assert.are.equal(0.3, settingsManager:getVal("loadspeed"))
            assert.are.equal("`", settingsManager:getVal("pianorollmacro"))
            assert.are.equal("gpt-4o-mini", settingsManager:getVal("openaimodel"))
        end)

        it("re-applies restrictive permissions to an existing valid settings file", function()
            secureFileCalls = 0
            secureDirCalls = 0

            simulateRestart()

            assert.is_true(secureFileCalls > 0)
            assert.is_true(secureDirCalls > 0)
        end)

        it("does not recreate an existing settings file merely because it cannot be read", function()
            local original = readSettings()
            local originalHS = rawget(_G, "hs")
            local originalPresence = rawget(_G, "ioIsFilePresent")
            local originalRead = rawget(_G, "fileToTable")
            local originalCreate = rawget(_G, "ShellCreateEmptyFile")
            local createCalls = 0
            rawset(_G, "hs", { fs = { symlinkAttributes = function() return { mode = "file" } end } })
            rawset(_G, "ioIsFilePresent", function() return false end)
            rawset(_G, "fileToTable", function() return false end)
            rawset(_G, "ShellCreateEmptyFile", function() createCalls = createCalls + 1 end)
            local ok, result = pcall(settingsManager.init, settingsManager)
            rawset(_G, "hs", originalHS)
            rawset(_G, "ioIsFilePresent", originalPresence)
            rawset(_G, "fileToTable", originalRead)
            rawset(_G, "ShellCreateEmptyFile", originalCreate)
            assert.is_true(ok)
            assert.is_false(result)
            assert.are.equal(0, createCalls)
            assert.are.equal(original, readSettings())
            assert.are.equal(1, settingsManager:getVal("autoadd"))
        end)

        it("secures retained backups using the native directory iterator state and closes it", function()
            local originalHS = rawget(_G, "hs")
            local originalSecure = rawget(_G, "SetSecureFileMode")
            local secured = {}
            local closed = 0
            rawset(_G, "hs", { fs = { dir = function()
                local entries = { ".", "settings_100.ini", "settings_200.ini", "other.ini" }
                local state = setmetatable({}, { __close = function() closed = closed + 1 end })
                local index = 0
                local function iterator(actualState)
                    assert.are.equal(state, actualState)
                    index = index + 1
                    return entries[index]
                end
                return iterator, state, nil, state
            end } })
            rawset(_G, "SetSecureFileMode", function(path) secured[path] = true end)
            local ok, result = pcall(settingsManager.init, settingsManager)
            rawset(_G, "hs", originalHS)
            rawset(_G, "SetSecureFileMode", originalSecure)
            assert.is_true(ok)
            assert.is_true(result)
            assert.is_true(secured[TEST_DIR .. "/settings_100.ini"])
            assert.is_true(secured[TEST_DIR .. "/settings_200.ini"])
            assert.is_nil(secured[TEST_DIR .. "/other.ini"])
            assert.are.equal(1, closed)
        end)

        it("prunes old backups using the native iterator state and closes its directory handles", function()
            local originalHS = rawget(_G, "hs")
            local originalOS = rawget(_G, "os")
            local removed = {}
            local closed = 0
            assert.is_true(tableToFile(TEST_DIR .. "/settings.ini", { "autoadd = 0" }))
            rawset(_G, "hs", {
                timer = { secondsSinceEpoch = function() return 1000000 end },
                fs = { dir = function()
                    local entries = { "settings_100.ini", "settings_200.ini", "settings_300.ini", "settings_400.ini",
                        "settings_500.ini", "settings_600.ini", "settings_700.ini" }
                    local state = setmetatable({}, { __close = function() closed = closed + 1 end })
                    local index = 0
                    local function iterator(actualState)
                        assert.are.equal(state, actualState)
                        index = index + 1
                        return entries[index]
                    end
                    return iterator, state, nil, state
                end },
            })
            rawset(_G, "os", setmetatable({
                remove = function(path) removed[#removed + 1] = path; return true end,
            }, { __index = originalOS }))
            local ok, result = pcall(settingsManager.init, settingsManager)
            rawset(_G, "hs", originalHS)
            rawset(_G, "os", originalOS)
            assert.is_true(ok)
            assert.is_true(result)
            assert.are.same({ TEST_DIR .. "/settings_100.ini", TEST_DIR .. "/settings_200.ini" }, removed)
            -- Secure before loading, prune, secure after writing, then secure
            -- once more when the backfilled settings are reloaded.
            assert.are.equal(4, closed)
        end)
    end)

    describe("writeVal", function()
        it("persists a single value across restart", function()
            assert.is_true(settingsManager:writeVal("autoadd", "0"))
            simulateRestart()
            assert.are.equal(0, settingsManager:getVal("autoadd"))
        end)

        it("rejects an unknown key or invalid setting without changing the file", function()
            local original = readSettings()
            assert.is_false(settingsManager:writeVal("unrecognized", "value"))
            assert.is_false(settingsManager:writeVal("autoadd", "2"))
            assert.are.equal(original, readSettings())
        end)
    end)

    describe("writeFromGui (settings GUI save)", function()
        it("persists toggle values across restart", function()
            local ok = settingsManager:writeFromGui({ autoadd = "0", texticon = "1" })
            assert.is_true(ok)
            simulateRestart()
            assert.are.equal(0, settingsManager:getVal("autoadd"))
            assert.are.equal(1, settingsManager:getVal("texticon"))
        end)

        it("persists numeric values across restart", function()
            local ok = settingsManager:writeFromGui({ loadspeed = "0.5", bookmarkx = "800" })
            assert.is_true(ok)
            simulateRestart()
            assert.are.equal(0.5, settingsManager:getVal("loadspeed"))
            assert.are.equal(800, settingsManager:getVal("bookmarkx"))
        end)

        it("persists string values across restart", function()
            local ok = settingsManager:writeFromGui({
                openaikey = "sk-test-abc123",
                openaimodel = "gpt-4o",
                pianorollmacro = "1",
            })
            assert.is_true(ok)
            simulateRestart()
            assert.are.equal("sk-test-abc123", settingsManager:getVal("openaikey"))
            assert.are.equal("gpt-4o", settingsManager:getVal("openaimodel"))
            assert.are.equal("1", settingsManager:getVal("pianorollmacro"))
        end)

        it("persists an API key containing a percent sign", function()
            local ok = settingsManager:writeFromGui({ openaikey = "sk-100%valid" })
            assert.is_true(ok)
            simulateRestart()
            assert.are.equal("sk-100%valid", settingsManager:getVal("openaikey"))
        end)

        it("persists a full GUI save (every key at once) across restart", function()
            -- This is exactly what the settings webview sends: every data-key
            local patch = {}
            for key, val in pairs(settingsManager) do
                if type(val) == "table" then
                    patch[key] = tostring(settingsManager:getVal(key))
                end
            end
            patch.autoadd = "0"
            patch.notifyhourly = "0"
            patch.loadspeed = "1.2"
            local ok = settingsManager:writeFromGui(patch)
            assert.is_true(ok)
            simulateRestart()
            assert.are.equal(0, settingsManager:getVal("autoadd"))
            assert.are.equal(0, settingsManager:getVal("notifyhourly"))
            assert.are.equal(1.2, settingsManager:getVal("loadspeed"))
        end)

        it("does not lose a cleared (empty) text field", function()
            local ok = settingsManager:writeFromGui({ openaikey = "" })
            assert.is_true(ok)
            simulateRestart()
            -- An empty value must survive as empty, not resurrect the default
            assert.are.equal("", settingsManager:getVal("openaikey"))
        end)

        it("does not crash on an empty numeric field (invalid number input sends \"\")", function()
            -- <input type=number> with invalid content reports value="" in JS
            local ok = pcall(function()
                settingsManager:writeFromGui({ loadspeed = "" })
            end)
            assert.is_true(ok, "writeFromGui must not panic on empty numeric value, got: " .. tostring(panicMessage))
            simulateRestart()
            -- Value must still be a usable number after restart
            assert.is_number(settingsManager:getVal("loadspeed"))
        end)

        it("accepts bookmark coordinate 0 (GUI min is 0)", function()
            settingsManager:writeFromGui({ bookmarkx = "0" })
            local ok = pcall(simulateRestart)
            assert.is_true(ok, "restart must not panic on bookmarkx=0, got: " .. tostring(panicMessage))
            assert.are.equal(0, settingsManager:getVal("bookmarkx"))
        end)

        it("rejects an invalid patch as a whole without persisting its valid fields", function()
            for _, invalid in ipairs({
                { autoadd = "2" },
                { autoadd = true },
                { bookmarkx = "0.5" },
                { bookmarkx = "-1" },
                { loadspeed = "1e309" },
                { loadspeed = math.huge },
                { loadspeed = 0 / 0 },
                { loadspeed = "" },
                { openaimodel = {} },
                { openaikey = false },
            }) do
                local patch = { texticon = "1" }
                for key, value in pairs(invalid) do patch[key] = value end
                local original = readSettings()
                assert.is_false(settingsManager:writeFromGui(patch))
                assert.are.equal(original, readSettings())
                assert.are.equal(0, settingsManager:getVal("texticon"))
                assert.are.equal(1, settingsManager:getVal("autoadd"))
                assert.are.equal(500, settingsManager:getVal("bookmarkx"))
                assert.are.equal(0.3, settingsManager:getVal("loadspeed"))
                assert.are.equal("gpt-4o-mini", settingsManager:getVal("openaimodel"))
                assert.are.equal("未設定", settingsManager:getVal("openaikey"))
            end
        end)

        it("does not replace settings after a read failure", function()
            local original = readSettings()
            local readFile = rawget(_G, "fileToTable")
            rawset(_G, "fileToTable", function() return false end)
            local guiCallOK, guiResult = pcall(settingsManager.writeFromGui, settingsManager, { texticon = "1" })
            local singleCallOK, singleResult = pcall(settingsManager.writeVal, settingsManager, "autoadd", "0")
            local initCallOK, initResult = pcall(settingsManager.init, settingsManager)
            rawset(_G, "fileToTable", readFile)
            assert.is_true(guiCallOK)
            assert.is_false(guiResult)
            assert.is_true(singleCallOK)
            assert.is_false(singleResult)
            assert.is_true(initCallOK)
            assert.is_false(initResult)
            assert.are.equal(original, readSettings())
            assert.are.equal(0, settingsManager:getVal("texticon"))
            assert.are.equal(1, settingsManager:getVal("autoadd"))
        end)
    end)

    -- ── Regression: parser semantics, self-heal, no boot panic ──────────
    describe("regression", function()
        --- Overwrite settings.ini on disk with raw lines, then re-init (a cold
        --- start reading exactly these bytes). Returns whether init panicked.
        local function writeRawIniAndRestart(lines)
            panicMessage = nil
            local f = assert(io.open(TEST_DIR .. "/settings.ini", "w"))
            f:write(table.concat(lines, "\n") .. "\n")
            f:close()
            return pcall(simulateRestart)
        end

        it("an empty str value persists as \"\" across restart (key = )", function()
            assert.is_true(settingsManager:writeFromGui({ openaimodel = "" }))
            simulateRestart()
            assert.are.equal("", settingsManager:getVal("openaimodel"))
        end)

        it("a str value containing ';' round-trips intact", function()
            assert.is_true(settingsManager:writeFromGui({ openaimodel = "gpt;weird;name" }))
            simulateRestart()
            assert.are.equal("gpt;weird;name", settingsManager:getVal("openaimodel"))
        end)

        it("malformed numeric on disk does NOT panic; init self-heals", function()
            -- DISCRIMINATING case: "999px" prefix (999) differs from the declared
            -- default (500). If init() parsed the malformed prefix it would yield
            -- 999; asserting 500 proves it instead REJECTS the line and backfills
            -- the declared type default — no number parsing of the prefix.
            local ok = writeRawIniAndRestart({
                "bookmarkx = 999px",
                "loadspeed = 0.3s",
                "autoadd = 1x",
            })
            assert.is_true(ok, "init must not panic on malformed numerics, got: " .. tostring(panicMessage))
            -- self-heal: malformed value rejected; init backfills the declared
            -- type default; no prefix parsing.
            local bookmarkxDefault = tonumber(settingsManager["bookmarkx"]["default"])
            assert.are.equal(bookmarkxDefault, settingsManager:getVal("bookmarkx"))
            assert.are.equal(500, settingsManager:getVal("bookmarkx"))
            assert.are.equal(0.3, settingsManager:getVal("loadspeed"))
            assert.are.equal(1, settingsManager:getVal("autoadd"))
        end)

        it("self-heals fractional integers, negative delays, and non-finite numbers on disk", function()
            local ok = writeRawIniAndRestart({
                "bookmarkx = 800.5",
                "bookmarky = 1e309",
                "loadspeed = -0.5",
                "autoadd = 2",
            })
            assert.is_true(ok)
            assert.are.equal(500, settingsManager:getVal("bookmarkx"))
            assert.are.equal(500, settingsManager:getVal("bookmarky"))
            assert.are.equal(0.3, settingsManager:getVal("loadspeed"))
            assert.are.equal(1, settingsManager:getVal("autoadd"))
        end)

        it("on-disk 'openaikey = 未設定sk-abc' self-heals to 'sk-abc'", function()
            local ok = writeRawIniAndRestart({ "openaikey = 未設定sk-abc" })
            assert.is_true(ok, "init must not panic, got: " .. tostring(panicMessage))
            assert.are.equal("sk-abc", settingsManager:getVal("openaikey"))
        end)

        it("openaikey is NOT mirrored into _G / _G.LES_CONFIG (sensitive)", function()
            assert.is_true(settingsManager:writeFromGui({ openaikey = "sk-secret-xyz" }))
            settingsManager:map()
            assert.is_nil(rawget(_G, "openaikey"))
            assert.is_nil((_G.LES_CONFIG or {})["openaikey"])
            -- still retrievable via the manager itself
            assert.are.equal("sk-secret-xyz", settingsManager["openaikey"]["value"])
        end)
    end)
end)

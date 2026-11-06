-- SPDX-License-Identifier: MIT

-- Run the actual startup compatibility checks with isolated application APIs.
-- No user settings or installed applications are read or modified.
local function startupOn(macOSVersion, liveVersion)
    liveVersion = liveVersion or 12
    local alerts, queries, settingWrites = {}, {}, {}
    local function noop() end
    local environment = setmetatable({}, { __index = _G })
    environment._G = environment
    environment.checksanity = 1
    environment.print = noop
    environment.require = function(name)
        if name == "globals.constants" then
            assert(loadfile("extensions/les/globals/constants.lua", "t", environment))()
        end
    end
    environment.hs = {
        processInfo = { bundleID = "org.les.Live-Enhancement-Suite-Custom" },
        dockIcon = noop,
        menuIcon = noop,
        uploadCrashData = noop,
        openConsoleOnDockClick = noop,
        automaticallyCheckForUpdates = noop,
        accessibilityState = function() return true end,
        application = {
            enableSpotlightForNameSearches = noop,
            find = function() return { allWindows = function() return {} end } end,
        },
    }
    environment.ShellExec = function(command)
        assert.are.equal("sw_vers -productVersion", command)
        return { stdout = macOSVersion }
    end
    environment.settingsManager = {
        init = noop,
        parse = noop,
        map = noop,
        writeVal = function(_, key, value) settingWrites[key] = value end,
    }
    environment.L = function(key)
        if key == "version_fail" then return "%s supports %s to %s; current %s; %s %s" end
        return key
    end
    environment.HSMakeAlert = function(title, message)
        alerts[#alerts + 1] = { title = title, message = message }
    end
    environment.HSMakeQuery = function(_, message)
        queries[#queries + 1] = message
        return false
    end
    environment.getLiveHsAppObj = function()
        return { path = function() return "/virtual/Ableton Live " .. liveVersion .. " Suite.app" end }
    end
    environment.getLiveVersion = function() return liveVersion end
    environment.ioIsFilePresent = function() return true end
    environment.GetDataPath = function(path) return "/virtual/les/" .. path end
    environment.io = {
        open = function()
            return {
                lines = function()
                    local pending = true
                    return function()
                        if pending then pending = false; return environment.programVersion end
                    end
                end,
            }
        end,
        close = noop,
    }
    environment.panicExit = function(message) error(message) end

    assert(loadfile("extensions/les/module.lua", "t", environment))()
    environment.module:init()
    return alerts, queries, settingWrites, environment
end

describe("startup platform compatibility", function()
    it("accepts macOS 27.2 and Live 12 with compatibility checking enabled", function()
        local alerts, queries, settingWrites, environment = startupOn("27.2\n", 12)

        assert.same({}, alerts)
        assert.same({}, queries)
        assert.same({}, settingWrites)
        assert.are.equal(27.2, environment.module.macOSVersion)
        assert.are.equal(1, environment.checksanity)
    end)

    it("continues to accept the previously supported macOS version", function()
        local alerts, queries = startupOn("26.7\n")

        assert.same({}, alerts)
        assert.same({}, queries)
    end)

    it("still warns for a newer unsupported major version", function()
        local alerts, queries, settingWrites, environment = startupOn("28.0\n")

        assert.are.equal(1, #alerts)
        assert.is_truthy(alerts[1].message:find("macOS 28", 1, true))
        assert.same({ "version_disable_query" }, queries)
        assert.same({}, settingWrites)
        assert.are.equal(1, environment.checksanity)
    end)

    it("still warns below the minimum supported macOS version", function()
        local alerts, queries = startupOn("11.7\n")

        assert.are.equal(1, #alerts)
        assert.is_truthy(alerts[1].message:find("macOS 11.7", 1, true))
        assert.same({ "version_disable_query" }, queries)
    end)

    it("warns instead of claiming support for Live 13", function()
        local alerts, queries, settingWrites, environment = startupOn("27.2\n", 13)

        assert.are.equal(1, #alerts)
        assert.is_truthy(alerts[1].message:find("current Live 13", 1, true))
        assert.same({ "version_disable_query" }, queries)
        assert.same({}, settingWrites)
        assert.are.equal(1, environment.checksanity)
    end)
end)

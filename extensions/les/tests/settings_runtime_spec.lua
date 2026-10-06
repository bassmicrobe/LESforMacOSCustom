-- SPDX-License-Identifier: MIT

local function reloadHarness(initResult)
    local events = {}
    local function record(name)
        return function() events[#events + 1] = name end
    end
    local pluginMenu = { delete = record("delete plugin menu") }
    local pianoMenu = { delete = record("delete piano menu") }
    local environment = setmetatable({
        _G = { addtostartup = 0, launchwithlive = 0 },
        pluginMenu = pluginMenu,
        pianoMenu = pianoMenu,
        BundleResourcePath = "/test/LES",
        settingsManager = {
            init = function() events[#events + 1] = "init"; return initResult end,
            parse = record("parse"),
            map = record("map"),
        },
        clearcategories = record("clear categories"),
        testmenuconfig = record("validate menu"),
        buildPluginMenu = record("build plugin menu"),
        buildMenuBar = record("build menu bar"),
        rebuildRcMenu = record("rebuild right click menu"),
        strQuote = function(value) return value end,
        hs = { autoLaunch = record("auto launch") },
        os = { getenv = function() return "/test/home" end, execute = record("launchctl"), remove = record("remove") },
        print = function() end,
    }, { __index = _G })
    assert(loadfile("extensions/les/lifecycle/reload.lua", "t", environment))()
    environment.cheats = record("cheats")
    return environment, events, pluginMenu, pianoMenu
end

describe("settings runtime failure boundaries", function()
    it("keeps running menus intact and skips all apply side effects when settings cannot load", function()
        local environment, events, pluginMenu, pianoMenu = reloadHarness(false)
        assert.is_false(environment.reloadLES())
        assert.are.same({ "init" }, events)
        assert.are.equal(pluginMenu, environment.pluginMenu)
        assert.are.equal(pianoMenu, environment.pianoMenu)
    end)

    it("still applies successfully loaded settings and rebuilds menus", function()
        local environment, events = reloadHarness(true)
        assert.is_not_false(environment.reloadLES())
        assert.are.same({
            "init", "clear categories", "delete plugin menu", "delete piano menu", "validate menu",
            "parse", "map", "build plugin menu", "build menu bar", "rebuild right click menu",
            "auto launch", "launchctl", "launchctl", "remove", "cheats",
        }, events)
    end)

    it("reports startup settings failure before parsing or mapping incomplete configuration", function()
        local events = {}
        local function noop() end
        local environment = setmetatable({
            require = function() return {} end,
            programName = "LES Test",
            programBundle = "test.les",
            L = function(key) return key end,
            ShellExec = function() return { stdout = "26.0" } end,
            panicExit = function(reason) events[#events + 1] = reason end,
            settingsManager = {
                init = function() return false end,
                parse = function() events[#events + 1] = "parse" end,
                map = function() events[#events + 1] = "map" end,
            },
            hs = {
                processInfo = { bundleID = "test.les" },
                dockIcon = noop, menuIcon = noop, uploadCrashData = noop, openConsoleOnDockClick = noop,
                automaticallyCheckForUpdates = noop, accessibilityState = function() return true end,
                application = {
                    enableSpotlightForNameSearches = noop,
                    find = function() return { allWindows = function() return {} end } end,
                },
            },
        }, { __index = _G })
        assert(loadfile("extensions/les/module.lua", "t", environment))()
        assert.is_false(environment.module:init())
        assert.are.same({ "settings_load_failed" }, events)
    end)
end)

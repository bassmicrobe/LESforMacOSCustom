--  SPDX-License-Identifier: MIT

package.path = package.path .. ";extensions/les/?.lua"

local SOURCE_PATH = "extensions/les/menus/settingsgui.lua"

local GLOBAL_NAMES = {
    "hs",
    "settingsManager",
    "reloadLES",
    "HSMakeAlert",
    "programName",
    "BundleResourcePath",
    "ScriptUserPath",
    "ConfigFile",
    "GetDataPath",
    "fileToTable",
    "enabledebug",
    "openSettingsGUI",
    "L",
    "uiLanguage",
}

local originalGlobals = {}

local function readSource()
    local file = assert(io.open(SOURCE_PATH, "rb"))
    local source = assert(file:read("*a"))
    assert(file:close())
    return source
end

local function makeHarness(options)
    options = options or {}
    local state = {
        alerts = {},
        notifications = {},
        reloadCalls = 0,
        recoveryCalls = {},
        timers = {},
        usercontents = {},
        webviews = {},
        writes = 0,
    }

    local usercontent = {
        new = function()
            local instance = {}
            function instance:setCallback(callback)
                self.callback = callback
                return self
            end
            state.usercontents[#state.usercontents + 1] = instance
            return instance
        end,
    }

    local webview = {
        usercontent = usercontent,
        new = function()
            local instance = {
                bringToFrontCalls = 0,
                deleted = false,
                evaluations = {},
                showCalls = 0,
            }
            function instance:deleteOnClose() return self end
            function instance:windowCallback(callback) self.closeCallback = callback return self end
            function instance:windowStyle() return self end
            function instance:windowTitle(value) self.title = value return self end
            function instance:allowTextEntry() return self end
            function instance:html(value) self.htmlValue = value return self end
            function instance:show() self.showCalls = self.showCalls + 1 return self end
            function instance:bringToFront() self.bringToFrontCalls = self.bringToFrontCalls + 1 return self end
            function instance:delete() self.deleted = true return self end
            function instance.hswindow()
                return { focus = function() state.focusCalls = (state.focusCalls or 0) + 1 end }
            end
            function instance:evaluateJavaScript(script)
                self.evaluations[#self.evaluations + 1] = script
                return self
            end
            state.webviews[#state.webviews + 1] = instance
            return instance
        end,
    }

    local hs = {
        json = {
            encode = function(value)
                if type(value) == "string" then return string.format("%q", value) end
                return nil
            end,
            decode = function() return nil end,
        },
        notify = {
            new = function(payload)
                return {
                    send = function()
                        state.notifications[#state.notifications + 1] = payload
                    end,
                }
            end,
        },
        screen = {
            mainScreen = function()
                return { frame = function() return {x = 0, y = 0, w = 1200, h = 800} end }
            end,
        },
        timer = {
            doAfter = function(_, callback)
                local timer = { callback = callback, stopped = false }
                function timer:stop() self.stopped = true end
                state.timers[#state.timers + 1] = timer
                return timer
            end,
        },
        webview = webview,
    }

    local manager = {autoadd = {value = "1"}}
    function manager.writeFromGui()
        state.writes = state.writes + 1
        return options.writeResult ~= false
    end
    for _, methodName in ipairs({"init", "parse", "map"}) do
        manager[methodName] = function()
            state.recoveryCalls[#state.recoveryCalls + 1] = methodName
            if options.recoveryErrorAt == methodName then
                error(methodName .. " failed")
            end
        end
    end

    rawset(_G, "hs", hs)
    rawset(_G, "settingsManager", manager)
    rawset(_G, "reloadLES", function()
        state.reloadCalls = state.reloadCalls + 1
        if options.reloadReturnsFalse then return false end
        if options.reloadError then error("reload failed") end
        return true
    end)
    rawset(_G, "HSMakeAlert", function(_, message, _, level)
        state.alerts[#state.alerts + 1] = {message = message, level = level}
    end)
    rawset(_G, "programName", "LES Test")
    rawset(_G, "BundleResourcePath", "extensions/les")
    rawset(_G, "ScriptUserPath", "/tmp/les-settingsgui-test")
    rawset(_G, "ConfigFile", "settings.ini")
    rawset(_G, "GetDataPath", function(path) return "/tmp/" .. tostring(path) end)
    rawset(_G, "fileToTable", function() end)
    rawset(_G, "enabledebug", 0)
    local locale = require("util.locale")
    rawset(_G, "uiLanguage", options.language or "ja")
    rawset(_G, "L", function(key) return locale.translate(key) end)

    assert(loadfile(SOURCE_PATH))()
    return state
end

local function sendSave(state)
    assert.are.equal(1, #state.usercontents)
    state.usercontents[1].callback({
        body = {
            action = "save",
            data = {autoadd = "0"},
        },
    })
end

describe("settings webview lifecycle", function()
    before_each(function()
        for _, name in ipairs(GLOBAL_NAMES) do
            originalGlobals[name] = rawget(_G, name)
        end
    end)

    after_each(function()
        for _, name in ipairs(GLOBAL_NAMES) do
            rawset(_G, name, originalGlobals[name])
        end
    end)

    it("deletes native resources and clears Lua references when closed", function()
        local source = readSource()

        assert.is_truthy(source:find("settingsWebview:deleteOnClose(true)", 1, true))
        assert.is_truthy(source:find("settingsWebview:windowCallback", 1, true))
        assert.is_truthy(source:find("settingsUC = nil", 1, true))
    end)

    it("keeps the existing webview and its draft when opened again", function()
        local state = makeHarness()

        openSettingsGUI()
        local firstView = state.webviews[1]
        openSettingsGUI()

        assert.are.equal(1, #state.webviews)
        assert.is_false(firstView.deleted)
        assert.are.equal(2, firstView.showCalls)
        assert.are.equal(2, firstView.bringToFrontCalls)
    end)

    it("groups settings under labelled level-two section headings", function()
        local state = makeHarness()
        openSettingsGUI()

        local html = state.webviews[1].htmlValue
        local _, sectionCount = html:gsub("<section", "")
        local _, headingCount = html:gsub("<h2", "")
        assert.are.equal(4, sectionCount)
        assert.are.equal(4, headingCount)
        for _, sectionName in ipairs({"toggles", "timing", "mapping", "ai"}) do
            local id = "settings-section-" .. sectionName
            assert.is_truthy(html:find("<section aria-labelledby='" .. id .. "'", 1, true))
            assert.is_truthy(html:find("<h2 id='" .. id .. "'", 1, true))
        end
    end)

    it("keeps the panel open and reports a persisted-but-not-applied result when reload fails", function()
        local state = makeHarness({reloadError = true})
        openSettingsGUI()

        sendSave(state)

        local view = state.webviews[1]
        assert.are.equal(1, state.writes)
        assert.are.equal(1, state.reloadCalls)
        assert.are.same({"init", "parse", "map"}, state.recoveryCalls)
        assert.are.equal(0, #state.timers)
        assert.are.equal(0, #state.notifications)
        assert.is_false(view.deleted)
        assert.matches("ファイル保存済み／反映中", view.evaluations[1], 1, true)
        assert.matches("saveResult%(false", view.evaluations[#view.evaluations])
        assert.matches("ファイル保存済み", view.evaluations[#view.evaluations], 1, true)
        assert.matches("反映に失敗", state.alerts[#state.alerts].message, 1, true)
    end)

    it("evaluates recovery failures and leaves the saved draft visible", function()
        local state = makeHarness({reloadError = true, recoveryErrorAt = "parse"})
        openSettingsGUI()

        sendSave(state)

        local view = state.webviews[1]
        assert.are.same({"init", "parse"}, state.recoveryCalls)
        assert.are.equal(0, #state.timers)
        assert.is_false(view.deleted)
        assert.matches("復旧にも失敗", view.evaluations[#view.evaluations], 1, true)
        assert.matches("復旧にも失敗", state.alerts[#state.alerts].message, 1, true)
    end)

    it("treats an explicit false reload result as an application failure", function()
        local state = makeHarness({reloadReturnsFalse = true})
        openSettingsGUI()

        sendSave(state)

        local view = state.webviews[1]
        assert.are.equal(0, #state.timers)
        assert.are.equal(0, #state.notifications)
        assert.is_false(view.deleted)
        assert.matches("saveResult%(false", view.evaluations[#view.evaluations])
        assert.matches("ファイル保存済み", view.evaluations[#view.evaluations], 1, true)
    end)

    it("closes only after persistence and runtime application both succeed", function()
        local state = makeHarness()
        openSettingsGUI()

        sendSave(state)

        local view = state.webviews[1]
        assert.are.equal(1, #state.timers)
        assert.are.equal(1, #state.notifications)
        assert.matches("ファイル保存済み／反映中", view.evaluations[1], 1, true)
        assert.matches("saveResult%(true", view.evaluations[#view.evaluations])
        assert.is_false(view.deleted)

        state.timers[1].callback()
        assert.is_true(view.deleted)
    end)

    it("localizes the window title and partial-success messages in English", function()
        local state = makeHarness({language = "en", reloadError = true})
        openSettingsGUI()
        sendSave(state)

        local view = state.webviews[1]
        assert.are.equal("LES Settings", view.title)
        assert.matches("File saved / applying", view.evaluations[1], 1, true)
        assert.matches("File saved / apply failed", view.evaluations[#view.evaluations], 1, true)
        assert.matches("saved to the settings file", state.alerts[#state.alerts].message, 1, true)
        assert.is_nil(view.evaluations[#view.evaluations]:match("[ぁ-んァ-ン一-龯]"))
    end)

    it("localizes a settings-file write failure in English", function()
        local state = makeHarness({language = "en", writeResult = false})
        openSettingsGUI()
        sendSave(state)

        local script = state.webviews[1].evaluations[#state.webviews[1].evaluations]
        assert.matches("could not write the settings file", script, 1, true)
        assert.matches("Could not write the settings file", state.alerts[#state.alerts].message, 1, true)
        assert.is_nil(script:match("[ぁ-んァ-ン一-龯]"))
    end)
end)

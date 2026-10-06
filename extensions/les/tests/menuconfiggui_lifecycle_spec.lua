--  SPDX-License-Identifier: MIT

local SOURCE_PATH = "extensions/les/menus/menuconfiggui.lua"
local FIXTURE_DIR = "/tmp/les_menuconfiggui_lifecycle_tests"
local FIXTURE_PATH = FIXTURE_DIR .. "/menuconfig.ini"
package.path = package.path .. ";extensions/les/?.lua"

local function writeFixture()
    assert(os.execute("mkdir -p " .. FIXTURE_DIR))
    local file = assert(io.open(FIXTURE_PATH, "w"))
    assert(file:write('/Effects\nDelay\n"Delay"\n\nEnd\n'))
    assert(file:close())
end

local function createHarness(options)
    options = options or {}
    writeFixture()

    local scheduled = {}
    local webviews = {}
    local userContentCallbacks = {}
    local liveBuildCalls = 0
    local liveRefreshCalls = 0
    local scanCallbacks = {}
    local directoryState = {}
    local iterated = false

    local decodedMessage = options.message or {
        action = "save",
        data = {
            categories = {
                { name = "Effects", plugins = { { name = "Delay", query = "Delay" } } },
            },
            nocategory = {},
        },
    }

    local hsMock = {
        fs = {dir = function()
            return function(state)
                assert.are.equal(directoryState, state)
                iterated = true
                return nil
            end, directoryState
        end},
        json = {
            decode = function()
                if options.decodeError then error("Invalid JSON") end
                return decodedMessage
            end,
        },
        screen = {
            mainScreen = function()
                return { frame = function() return { x = 0, y = 0, w = 1440, h = 900 } end }
            end,
        },
        timer = {
            secondsSinceEpoch = function() return 123 end,
            doAfter = function(delay, callback)
                scheduled[#scheduled + 1] = { delay = delay, callback = callback }
                return scheduled[#scheduled]
            end,
        },
        webview = {
            usercontent = {
                new = function()
                    local userContent = {}
                    function userContent:setCallback(callback)
                        userContentCallbacks[#userContentCallbacks + 1] = callback
                        return self
                    end
                    return userContent
                end,
            },
        },
    }

    hsMock.webview.new = function()
        local nativeWindow = { focusCount = 0 }
        function nativeWindow:focus()
            self.focusCount = self.focusCount + 1
            return true
        end

        local webview = {
            bringCount = 0,
            deleted = false,
            evaluatedScripts = {},
            nativeWindow = nativeWindow,
        }
        local function chain() return webview end
        webview.deleteOnClose = chain
        webview.windowStyle = chain
        function webview:windowTitle(value) self.title = value return self end
        webview.allowTextEntry = chain
        function webview:html(value) self.htmlValue = value return self end
        function webview:navigationCallback(callback) self.navigation = callback return self end
        webview.show = chain
        function webview:bringToFront()
            self.bringCount = self.bringCount + 1
            return self
        end
        function webview:delete()
            self.deleted = true
            return self
        end
        function webview:evaluateJavaScript(script)
            self.evaluatedScripts[#self.evaluatedScripts + 1] = script
            return self
        end
        function webview:hswindow() return self.nativeWindow end
        function webview:windowCallback(callback)
            self.closeCallback = callback
            return self
        end
        webviews[#webviews + 1] = webview
        return webview
    end

    local locale = require("util.locale")
    local environment
    environment = setmetatable({
        _G = false,
        hs = hsMock,
        ScriptUserPath = FIXTURE_DIR,
        programName = "LES Test",
        HSMakeAlert = function() end,
        ShellCopy = function() return not options.backupFails end,
        ioIsFilePresent = function() return options.backupFails == true or options.backupExists == true end,
        io = {open = function(path, mode)
            if options.writeFails and path == FIXTURE_PATH .. ".tmp" and mode == "w" then
                local file = assert(io.open(path, mode))
                return {write = function() return nil, "disk full" end, close = function() return file:close() end}
            end
            return io.open(path, mode)
        end},
        strJoinPaths = function(left, right) return left .. "/" .. right end,
        buildPluginMenu = function()
            liveBuildCalls = liveBuildCalls + 1
            if options.buildError then error(options.buildError) end
        end,
        rebuildRcMenu = function()
            liveRefreshCalls = liveRefreshCalls + 1
            if options.refreshError then error(options.refreshError) end
        end,
        print = function() end,
        uiLanguage = options.language or "ja",
        L = function(key) return locale.translate(key, options.language or "ja") end,
        require = function(name)
            if name == "util.windowframe" then
                return {
                    center = function(_, width, height)
                        return { x = 290, y = 130, w = width, h = height }
                    end,
                }
            end
            if name == "vst.scanner" then
                return {
                    scanVST3 = function() error("UI must not scan synchronously") end,
                    scanVST3Async = function(callback)
                        scanCallbacks[#scanCallbacks + 1] = callback
                        return true
                    end,
                }
            end
            return require(name)
        end,
    }, { __index = _G })
    environment._G = environment

    local chunk = assert(loadfile(SOURCE_PATH, "t", environment))
    chunk()

    return {
        environment = environment,
        scheduled = scheduled,
        webviews = webviews,
        scans = scanCallbacks,
        iterated = function() return iterated end,
        callback = function() return userContentCallbacks[#userContentCallbacks] end,
        liveBuildCalls = function() return liveBuildCalls end,
        liveRefreshCalls = function() return liveRefreshCalls end,
    }
end

local function lastScript(webview)
    return webview.evaluatedScripts[#webview.evaluatedScripts] or ""
end

local function readSource()
    local file = assert(io.open(SOURCE_PATH, "r"))
    local source = assert(file:read("*a"))
    assert(file:close())
    return source
end

describe("menu configuration editor lifecycle", function()
    it("shows the editor before scanning and updates only the plugin picker", function()
        local harness = createHarness()
        harness.environment.openMenuConfigGUI()
        local view = harness.webviews[1]
        assert.is_truthy(view.htmlValue:find("Ableton", 1, true))
        assert.are.equal(0, #harness.scans)
        assert.is_function(view.navigation)
        view.navigation("didFinishNavigation")
        assert.are.equal(1, #harness.scans)
        harness.scans[1]({{name = "Test VST3", category = "FX"}})
        assert.is_truthy(lastScript(view):find("setAvailablePlugins(", 1, true))
        assert.is_truthy(lastScript(view):find("Test VST3", 1, true))
    end)

    it("ignores an old scan result after the editor is closed and reopened", function()
        local harness = createHarness()
        harness.environment.openMenuConfigGUI()
        local oldView = harness.webviews[1]
        assert.is_function(oldView.navigation)
        oldView.navigation("didFinishNavigation")
        oldView.closeCallback("closing")
        harness.environment.openMenuConfigGUI()
        harness.scans[1]({{name = "Stale VST3", category = "FX"}})
        assert.are.equal(0, #oldView.evaluatedScripts)
        assert.are.equal(0, #harness.webviews[2].evaluatedScripts)
    end)

    it("keeps the original and removes the temporary file after a write failure", function()
        local harness = createHarness({writeFails = true})
        harness.environment.openMenuConfigGUI()
        harness.callback()({body = "save"})
        local file = assert(io.open(FIXTURE_PATH, "r"))
        local content = file:read("*a")
        file:close()
        assert.are.equal('/Effects\nDelay\n"Delay"\n\nEnd\n', content)
        assert.is_nil(io.open(FIXTURE_PATH .. ".tmp", "r"))
        assert.is_truthy(lastScript(harness.webviews[1]):find("saveResult(false", 1, true))
        assert.are.equal(0, harness.liveBuildCalls())
    end)

    it("passes the directory state while pruning backups before a successful save", function()
        local harness = createHarness({backupExists = true})
        harness.environment.openMenuConfigGUI()
        assert.has_no.errors(function() harness.callback()({body = "save"}) end)
        assert.is_true(harness.iterated())
        assert.is_truthy(lastScript(harness.webviews[1]):find("saveResult(true", 1, true))
        assert.are.equal(1, harness.liveBuildCalls())
    end)

    it("shows a scan error without replacing the editor or its draft", function()
        local harness = createHarness()
        harness.environment.openMenuConfigGUI()
        local view = harness.webviews[1]
        view.navigation("didFinishNavigation")
        harness.scans[1](nil, "directory read failed")
        assert.is_truthy(lastScript(view):find("directory read failed", 1, true))
        assert.is_truthy(lastScript(view):find("setAvailablePlugins([]", 1, true))
        assert.is_false(view.deleted)
    end)

    it("rejects malformed messages without overwriting the existing file", function()
        for _, message in ipairs({
            {action = "save", data = {categories = {4}, nocategory = {}}},
            {action = "save", data = {categories = {{name = "/Nested", plugins = {}}}, nocategory = {}}},
            {action = "save", data = {categories = {{name = "nocategory", plugins = {}}}, nocategory = {}}},
            {action = "save", data = {categories = {{name = "FX\nEnd", plugins = {}}}, nocategory = {}}},
            {action = "save", data = {categories = {}, nocategory = {{name = "Delay", query = "Delay\nEnd"}}}},
            {action = "save", data = {categories = {}}},
        }) do
            local harness = createHarness({message = message})
            harness.environment.openMenuConfigGUI()
            assert.has_no.errors(function() harness.callback()({body = "save"}) end)
            local file = assert(io.open(FIXTURE_PATH, "r"))
            local content = file:read("*a")
            file:close()
            assert.are.equal('/Effects\nDelay\n"Delay"\n\nEnd\n', content)
            assert.are.equal(0, harness.liveBuildCalls())
            assert.is_truthy(lastScript(harness.webviews[1]):find("saveResult(false", 1, true))
        end
    end)

    it("reports a malformed JSON message immediately", function()
        local harness = createHarness({decodeError = true})
        harness.environment.openMenuConfigGUI()
        assert.has_no.errors(function() harness.callback()({body = "bad json"}) end)
        assert.is_truthy(lastScript(harness.webviews[1]):find("saveResult(false", 1, true))
        assert.are.equal(0, harness.liveBuildCalls())
    end)

    it("preserves the original when its required backup fails", function()
        local harness = createHarness({backupFails = true})
        harness.environment.openMenuConfigGUI()
        harness.callback()({body = "save"})
        local file = assert(io.open(FIXTURE_PATH, "r"))
        local content = file:read("*a")
        file:close()
        assert.are.equal('/Effects\nDelay\n"Delay"\n\nEnd\n', content)
        assert.is_truthy(lastScript(harness.webviews[1]):find("saveResult(false", 1, true))
        assert.are.equal(0, harness.liveBuildCalls())
    end)

    it("keeps the editor open after saving so later edits cannot be discarded by a close timer", function()
        local harness = createHarness()
        harness.environment.openMenuConfigGUI()
        local webview = harness.webviews[1]

        harness.callback()({ body = "save" })

        assert.are.equal(0, #harness.scheduled)
        assert.is_false(webview.deleted)
        assert.is_truthy(lastScript(webview):find("保存しました", 1, true))
    end)

    it("keeps edits made while a save response is pending marked as unsaved", function()
        local source = readSource()

        assert.is_truthy(source:find("var editRevision=0;", 1, true))
        assert.is_truthy(source:find("savingRevision=editRevision;", 1, true))
        assert.is_truthy(source:find("savingRevision===editRevision", 1, true))
        assert.is_truthy(source:find("i18n.newerEditsSuffix", 1, true))
        assert.is_truthy(source:find('L("menuconfig_newer_edits_suffix")', 1, true))
    end)

    it("reports a partial success and keeps the editor open when live menu building fails", function()
        local harness = createHarness({ buildError = "menu build failed" })
        harness.environment.openMenuConfigGUI()
        local webview = harness.webviews[1]

        harness.callback()({ body = "save" })

        assert.are.equal(1, harness.liveBuildCalls())
        assert.are.equal(0, harness.liveRefreshCalls())
        assert.is_truthy(lastScript(webview):find("ライブメニューへの反映に失敗", 1, true))
        assert.is_truthy(lastScript(webview):find(",true)", 1, true))
        assert.are.equal(0, #harness.scheduled)
        assert.is_false(webview.deleted)
    end)

    it("reports a partial success when refreshing the live menu fails", function()
        local harness = createHarness({ refreshError = "menu refresh failed" })
        harness.environment.openMenuConfigGUI()
        local webview = harness.webviews[1]

        harness.callback()({ body = "save" })

        assert.are.equal(1, harness.liveBuildCalls())
        assert.are.equal(1, harness.liveRefreshCalls())
        assert.is_truthy(lastScript(webview):find("ライブメニューへの反映に失敗", 1, true))
        assert.is_false(webview.deleted)
    end)

    it("focuses the existing editor instead of deleting dirty state on a repeated open", function()
        local harness = createHarness()
        harness.environment.openMenuConfigGUI()
        local firstWebview = harness.webviews[1]

        harness.environment.openMenuConfigGUI()

        assert.are.equal(1, #harness.webviews)
        assert.is_false(firstWebview.deleted)
        assert.are.equal(2, firstWebview.bringCount)
        assert.are.equal(1, firstWebview.nativeWindow.focusCount)
    end)

    it("localizes the window title and partial save result in English", function()
        local harness = createHarness({ language = "en", buildError = "menu build failed" })
        harness.environment.openMenuConfigGUI()
        local webview = harness.webviews[1]

        harness.callback()({ body = "save" })

        assert.are.equal("Plugin Menu Settings — Live Enhancement Suite Custom", webview.title)
        assert.is_truthy(lastScript(webview):find("File saved, but applying it to the live menu failed", 1, true))
        assert.is_nil(lastScript(webview):match("[ぁ-んァ-ン一-龯]"))
    end)

    it("localizes a successful save result in English", function()
        local harness = createHarness({ language = "en" })
        harness.environment.openMenuConfigGUI()
        local webview = harness.webviews[1]

        harness.callback()({ body = "save" })

        assert.is_truthy(lastScript(webview):find("Saved.", 1, true))
        assert.is_nil(lastScript(webview):match("[ぁ-んァ-ン一-龯]"))
    end)
end)

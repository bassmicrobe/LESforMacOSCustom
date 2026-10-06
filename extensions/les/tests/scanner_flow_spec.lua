--  SPDX-License-Identifier: MIT

package.path = package.path .. ";extensions/les/?.lua"

local function createHarness(options)
    options = options or {}
    local scheduled = {}
    local alerts = {}
    local prompts = {}
    local webviews = {}
    local writes = 0
    local asyncScans = 0
    local hsMock = {
        screen = {mainScreen = function()
            return {frame = function() return {x = 0, y = 0, w = 1280, h = 800} end}
        end},
        drawing = {windowLevels = {floating = 1}},
        timer = {
            secondsSinceEpoch = function() return 123 end,
            doAfter = function(_, callback)
                scheduled[#scheduled + 1] = callback
                return {}
            end,
        },
        webview = {new = function()
            local view = {deleted = false}
            local function chain() return view end
            view.deleteOnClose = chain
            view.windowStyle = chain
            view.windowTitle = chain
            view.level = chain
            view.windowCallback = chain
            view.html = chain
            view.show = chain
            view.bringToFront = chain
            view.evaluateJavaScript = chain
            function view:delete() self.deleted = true end
            webviews[#webviews + 1] = view
            return view
        end},
    }
    local environment = setmetatable({
        hs = hsMock,
        programName = "LES Test",
        L = function(key) return key end,
        HSMakeAlert = function(_, message) alerts[#alerts + 1] = message end,
        HSMakeQuery = function(_, message)
            prompts[#prompts + 1] = message
            return false
        end,
    }, {__index = _G})
    local scanner = assert(loadfile("extensions/les/vst/scanner.lua", "t", environment))()
    scanner.loadCache = function() return {plugins = {}, scanned_at = 0} end
    scanner.saveCache = function()
        writes = writes + 1
        return true
    end
    scanner.scanAUAsync = function(callback)
        hsMock.timer.doAfter(0, function() callback({}, nil) end)
        return {}
    end
    scanner.scanVST3 = function() error("UI must not scan VST3 synchronously") end
    scanner.scanVST3Async = function(callback)
        asyncScans = asyncScans + 1
        hsMock.timer.doAfter(0, function()
            if options.vst3Error then
                callback(nil, options.vst3Error)
                return
            end
            callback({
                {name = "Example Reverb", category = "Reverb", format = "VST3"},
            }, nil)
        end)
        return true
    end
    return {
        scanner = scanner,
        alerts = alerts,
        prompts = prompts,
        webviews = webviews,
        writes = function() return writes end,
        asyncScans = function() return asyncScans end,
        finish = function()
            while #scheduled > 0 do table.remove(scheduled, 1)() end
        end,
    }
end

describe("plugin scanner UI flow", function()
    it("finishes a successful asynchronous scan and shows the generation prompt", function()
        local harness = createHarness()
        assert.is_true(harness.scanner.scanAndPrompt())
        harness.finish()

        assert.are.equal(1, harness.asyncScans())
        assert.are.equal(1, harness.writes())
        assert.are.equal(1, #harness.prompts)
        assert.are.equal(0, #harness.alerts)
        assert.is_true(harness.webviews[1].deleted)
        assert.is_true(harness.scanner.scanAndPrompt())
        harness.finish()
    end)

    it("preserves the cache and allows retry after an asynchronous VST3 error", function()
        local harness = createHarness({vst3Error = "metadata unavailable"})
        assert.is_true(harness.scanner.scanAndPrompt())
        harness.finish()

        assert.are.equal(0, harness.writes())
        assert.are.equal(0, #harness.prompts)
        assert.are.equal(1, #harness.alerts)
        assert.matches("metadata unavailable", harness.alerts[1], 1, true)
        assert.is_true(harness.webviews[1].deleted)
        assert.is_true(harness.scanner.scanAndPrompt())
        harness.finish()
    end)
end)

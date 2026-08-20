--  SPDX-License-Identifier: MIT

package.path = package.path .. ";extensions/les/?.lua"

local originalHs = rawget(_G, "hs")
local originalAlert = rawget(_G, "HSMakeAlert")
local originalProgramName = rawget(_G, "programName")
local originalOpenAIPreload = package.preload["ai.openai"]
local originalStatsPreload = package.preload["tracking.pluginstats"]
local originalL = rawget(_G, "L")
local originalUiLanguage = rawget(_G, "uiLanguage")
local originalLocaleModule = package.loaded["util.locale"]

local function makeOpenAIHarness()
    local harness = { callbacks = {}, requests = {} }
    harness.module = {
        isConfigured = function() return true end,
        chat = function(messages, callback)
            harness.requests[#harness.requests + 1] = messages
            harness.callbacks[#harness.callbacks + 1] = callback
        end,
    }
    return harness
end

local function makeRecommendHs(screenFrame, failWebviewCreation)
    local state = { usercontents = {}, webviews = {} }
    local frame = screenFrame or { x = 0, y = 0, w = 1200, h = 800 }

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
        new = function(windowFrame)
            if failWebviewCreation then return nil end
            local instance = { evaluations = {}, deleted = false, frame = windowFrame }
            function instance:windowStyle() return self end
            function instance:windowTitle(value) self.title = value return self end
            function instance:allowTextEntry() return self end
            function instance:html(value) self.htmlValue = value return self end
            function instance:windowCallback(callback) self.closeCallback = callback return self end
            function instance:deleteOnClose() return self end
            function instance:show() return self end
            function instance:bringToFront() return self end
            function instance:delete() self.deleted = true return self end
            function instance:evaluateJavaScript(script)
                self.evaluations[#self.evaluations + 1] = script
                return self
            end
            state.webviews[#state.webviews + 1] = instance
            return instance
        end,
    }

    return {
        webview = webview,
        screen = { mainScreen = function() return { frame = function() return frame end } end },
    }, state
end

local function makeNamegenHs()
    local state = { choosers = {} }
    local hs = {
        chooser = {
            new = function(callback)
                local instance = { callback = callback, choiceUpdates = {}, deleted = false }
                function instance:placeholderText(value) self.placeholder = value return self end
                function instance:choices(value)
                    self.choiceUpdates[#self.choiceUpdates + 1] = value
                    return self
                end
                function instance:show() self.shown = true return self end
                function instance:delete() self.deleted = true return self end
                function instance:refreshChoicesCallback() self.refreshed = true return self end
                state.choosers[#state.choosers + 1] = instance
                return instance
            end,
        },
        pasteboard = { setContents = function(value) state.clipboard = value end },
    }
    return hs, state
end

local function resetModules()
    package.loaded["ai.openai"] = nil
    package.loaded["tracking.pluginstats"] = nil
    package.loaded["ai.recommend"] = nil
    package.loaded["ai.namegen"] = nil
end

describe("AI UI asynchronous request lifecycle", function()
    before_each(function()
        resetModules()
        package.loaded["util.locale"] = nil
        require("util.locale")
        rawset(_G, "uiLanguage", "ja")
        rawset(_G, "HSMakeAlert", function() end)
        rawset(_G, "programName", "LES Test")
    end)

    after_each(function()
        resetModules()
        package.preload["ai.openai"] = originalOpenAIPreload
        package.preload["tracking.pluginstats"] = originalStatsPreload
        package.loaded["util.locale"] = originalLocaleModule
        rawset(_G, "hs", originalHs)
        rawset(_G, "HSMakeAlert", originalAlert)
        rawset(_G, "programName", originalProgramName)
        rawset(_G, "L", originalL)
        rawset(_G, "uiLanguage", originalUiLanguage)
    end)

    it("focuses an existing recommendation panel and drops stale replies after a real close", function()
        local openai = makeOpenAIHarness()
        local hs, ui = makeRecommendHs()
        package.preload["ai.openai"] = function() return openai.module end
        package.preload["tracking.pluginstats"] = function()
            return { getAll = function() return {} end }
        end
        rawset(_G, "hs", hs)

        local recommend = require("ai.recommend")
        recommend.open()
        local firstView = ui.webviews[1]
        local firstContent = ui.usercontents[1]
        assert.are.equal(1, #openai.callbacks)

        firstContent.callback({ body = { action = "ask", extra = "warm" } })
        assert.are.equal(1, #openai.callbacks)

        openai.callbacks[1]("initial result", nil)
        firstContent.callback({ body = { action = "ask", extra = "warm" } })
        firstContent.callback({ body = { action = "ask", extra = "duplicate" } })
        assert.are.equal(2, #openai.callbacks)

        recommend.open()
        assert.are.equal(1, #ui.webviews)
        assert.are.equal(2, #openai.callbacks)
        assert.is_false(firstView.deleted)

        firstView.closeCallback("closing")
        recommend.open()
        local secondView = ui.webviews[2]
        assert.are.equal(3, #openai.callbacks)
        local evaluationsBeforeStaleReply = #secondView.evaluations

        openai.callbacks[2]("stale result", nil)
        assert.are.equal(evaluationsBeforeStaleReply, #secondView.evaluations)

        openai.callbacks[3]("fresh result", nil)
        assert.matches("fresh result", secondView.evaluations[#secondView.evaluations], 1, true)
    end)

    it("keeps recommendation input until success and exposes a busy state", function()
        local openai = makeOpenAIHarness()
        local hs, ui = makeRecommendHs()
        package.preload["ai.openai"] = function() return openai.module end
        package.preload["tracking.pluginstats"] = function()
            return { getAll = function() return {} end }
        end
        rawset(_G, "hs", hs)

        require("ai.recommend").open()
        local html = ui.webviews[1].htmlValue

        assert.matches("requestPending", html, 1, true)
        assert.matches("aria%-busy", html)
        assert.matches("recommendRequestResult", html, 1, true)
        assert.matches("if %(ok%)", html)
        assert.is_nil(html:match("function ask%b()%s*{.-inp%.value%s*=%s*''.-postMessage"))
    end)

    it("uses a dark color scheme and clamps the recommendation window to a small screen", function()
        local openai = makeOpenAIHarness()
        local hs, ui = makeRecommendHs({ x = 0, y = 0, w = 320, h = 480 })
        package.preload["ai.openai"] = function() return openai.module end
        package.preload["tracking.pluginstats"] = function()
            return { getAll = function() return {} end }
        end
        rawset(_G, "hs", hs)

        require("ai.recommend").open()

        assert.are.same({ x = 12, y = 12, w = 296, h = 456 }, ui.webviews[1].frame)
        assert.matches("color%-scheme:%s*dark", ui.webviews[1].htmlValue)
    end)

    it("returns safely when the recommendation WebView cannot be created", function()
        local openai = makeOpenAIHarness()
        local hs = makeRecommendHs(nil, true)
        package.preload["ai.openai"] = function() return openai.module end
        package.preload["tracking.pluginstats"] = function()
            return { getAll = function() return {} end }
        end
        rawset(_G, "hs", hs)

        assert.has_no.errors(function()
            require("ai.recommend").open()
        end)
        assert.are.equal(0, #openai.requests)
    end)

    it("rejects oversized recommendation input without leaving the UI locked", function()
        local openai = makeOpenAIHarness()
        local hs, ui = makeRecommendHs()
        package.preload["ai.openai"] = function() return openai.module end
        package.preload["tracking.pluginstats"] = function()
            return { getAll = function() return {} end }
        end
        rawset(_G, "hs", hs)

        require("ai.recommend").open()
        openai.callbacks[1]("initial result", nil)
        ui.usercontents[1].callback({ body = { action = "ask", extra = string.rep("x", 4001) } })

        assert.are.equal(1, #openai.callbacks)
        assert.matches("入力は4000文字以内", ui.webviews[1].evaluations[#ui.webviews[1].evaluations], 1, true)
        assert.matches("recommendRequestResult%(false%)", ui.webviews[1].evaluations[#ui.webviews[1].evaluations])
    end)

    it("drops old name generator replies after reopen and after cancellation", function()
        local openai = makeOpenAIHarness()
        local hs, ui = makeNamegenHs()
        package.preload["ai.openai"] = function() return openai.module end
        package.preload["tracking.pluginstats"] = function()
            return { getAll = function() return {} end }
        end
        rawset(_G, "hs", hs)

        local namegen = require("ai.namegen")
        namegen.open("first")
        local firstChooser = ui.choosers[1]
        namegen.open("duplicate")
        assert.are.equal(1, #openai.callbacks)

        firstChooser.callback(nil)
        namegen.open("second")
        local secondChooser = ui.choosers[2]
        assert.are.equal(2, #openai.callbacks)

        openai.callbacks[1]("Old Name (old)", nil)
        assert.are.equal(1, #secondChooser.choiceUpdates)

        openai.callbacks[2]("Fresh Name (fresh)", nil)
        assert.are.equal(2, #secondChooser.choiceUpdates)
        assert.are.equal("Fresh Name", secondChooser.choiceUpdates[2][1].text)

        namegen.open("cancelled")
        local cancelledChooser = ui.choosers[3]
        cancelledChooser.callback(nil)
        openai.callbacks[3]("Too Late (ignored)", nil)
        assert.are.equal(1, #cancelledChooser.choiceUpdates)
    end)

    it("does not copy loading, error, or empty-result state rows as generated names", function()
        local openai = makeOpenAIHarness()
        local hs, ui = makeNamegenHs()
        package.preload["ai.openai"] = function() return openai.module end
        package.preload["tracking.pluginstats"] = function()
            return { getAll = function() return {} end }
        end
        rawset(_G, "hs", hs)

        local namegen = require("ai.namegen")
        namegen.open()
        local firstChooser = ui.choosers[1]
        firstChooser.callback(firstChooser.choiceUpdates[1][1])
        assert.is_nil(ui.clipboard)

        openai.callbacks[1](nil, "network error")
        firstChooser.callback(firstChooser.choiceUpdates[2][1])
        assert.is_nil(ui.clipboard)

        namegen.open()
        local secondChooser = ui.choosers[2]
        openai.callbacks[2]("\n", nil)
        secondChooser.callback(secondChooser.choiceUpdates[2][1])
        assert.is_nil(ui.clipboard)
    end)

    it("uses the selected language for recommendation and name-generation prompts", function()
        rawset(_G, "uiLanguage", "en")
        local openai = makeOpenAIHarness()
        package.preload["ai.openai"] = function() return openai.module end
        package.preload["tracking.pluginstats"] = function()
            return { getAll = function() return {} end }
        end

        local recommendHs, recommendUI = makeRecommendHs()
        rawset(_G, "hs", recommendHs)
        require("ai.recommend").open()
        assert.matches("respond in English", openai.requests[1][1].content, 1, true)
        assert.are.equal("AI Plugin Suggestions", recommendUI.webviews[1].title)
        assert.matches('<html lang="en">', recommendUI.webviews[1].htmlValue, 1, true)

        local namegenHs, namegenUI = makeNamegenHs()
        rawset(_G, "hs", namegenHs)
        package.loaded["ai.namegen"] = nil
        require("ai.namegen").open()
        assert.matches("Respond in English", openai.requests[2][1].content, 1, true)
        assert.are.equal("AI is generating names...", namegenUI.choosers[1].placeholder)
    end)

    it("renders recommendation and name-generation failures in the selected UI language", function()
        rawset(_G, "uiLanguage", "en")
        local upstreamError = "通信エラーが発生しました"
        local openai = makeOpenAIHarness()
        package.preload["ai.openai"] = function() return openai.module end
        package.preload["tracking.pluginstats"] = function()
            return { getAll = function() return {} end }
        end

        local recommendHs, recommendUI = makeRecommendHs()
        rawset(_G, "hs", recommendHs)
        require("ai.recommend").open()
        openai.callbacks[1](nil, upstreamError)
        local recommendationScript = recommendUI.webviews[1].evaluations[#recommendUI.webviews[1].evaluations]
        assert.matches("Could not get a response from AI", recommendationScript, 1, true)
        assert.is_nil(recommendationScript:find(upstreamError, 1, true))

        local namegenHs, namegenUI = makeNamegenHs()
        rawset(_G, "hs", namegenHs)
        require("ai.namegen").open()
        openai.callbacks[2](nil, upstreamError)
        local errorRow = namegenUI.choosers[1].choiceUpdates[2][1]
        assert.matches("Could not get a response from AI", errorRow.subText, 1, true)
        assert.is_nil(errorRow.subText:find(upstreamError, 1, true))
    end)
end)

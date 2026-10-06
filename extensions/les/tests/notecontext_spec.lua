-- SPDX-License-Identifier: MIT

package.path = package.path .. ";extensions/les/?.lua"

local dkjson = require("dkjson")
local locale = require("util.locale")

local function createHarness(kind, options)
    options = options or {}
    local state = { views = {}, confirmations = {}, saved = {}, alerts = {} }
    local environment
    local hsMock = {
        json = {
            encode = dkjson.encode,
            decode = function(raw) return dkjson.decode(raw) end,
        },
        timer = { secondsSinceEpoch = function() return 123 end },
        drawing = { windowLevels = { floating = 1 } },
        screen = { mainScreen = function()
            return { frame = function() return { x = 0, y = 0, w = 1200, h = 800 } end }
        end },
        webview = { usercontent = { new = function()
            return { setCallback = function(self, callback)
                state.message = callback
                return self
            end }
        end } },
    }
    hsMock.webview.new = function()
        local view = { documents = {}, scripts = {} }
        local function chain() return view end
        for _, method in ipairs({
            "deleteOnClose", "windowStyle", "windowTitle", "level", "allowTextEntry", "show", "bringToFront",
        }) do view[method] = chain end
        function view:html(html) self.documents[#self.documents + 1] = html return self end
        view.hswindow = function() return { focus = function() end } end
        function view:windowCallback(callback) self.closeCallback = callback return self end
        function view:evaluateJavaScript(script, callback)
            self.scripts[#self.scripts + 1] = script
            if callback then
                if options.evaluateThrows then error("document unavailable") end
                state.confirmations[#state.confirmations + 1] = callback
            end
            return self
        end
        state.views[#state.views + 1] = view
        return view
    end
    environment = setmetatable({
        hs = hsMock,
        trackname = "Old Project",
        getLiveHsAppObj = function() return nil end,
        HSMakeAlert = function(_, message) state.alerts[#state.alerts + 1] = message end,
        programName = "LES Test",
        print = function() end,
        L = function(key) return locale.translate(key, "en") end,
        require = function(name)
            if name == "util.windowframe" then return { right = function() return {} end } end
            if name == "util.noteid" then return { create = function() return "new-note" end } end
            return require(name)
        end,
    }, { __index = _G })
    environment._G = environment
    local module = assert(loadfile("extensions/les/tracking/" .. kind .. ".lua", "t", environment))()
    if kind == "projectnotes" then
        module.load = function(project) return state.saved[project] or {} end
        module.save = function(project, notes) state.saved[project] = notes return true end
        state.open = environment.openProjectNotes
        state.add = function(text) state.message({ body = { action = "add", text = text } }) end
        state.savedBody = function(project) return state.saved[project][1].body end
    else
        module.loadAll = function(project) return state.saved[project] or {} end
        module.saveAll = function(project, notes) state.saved[project] = notes return true end
        state.open = environment.openTrackNotes
        state.add = function(text) state.message({ body = { action = "add", track = "Lead", text = text } }) end
        state.savedBody = function(project) return state.saved[project].Lead[1].body end
    end
    state.switch = function(project) environment.trackname = project state.open() end
    state.open()
    return state
end

for _, kind in ipairs({ "projectnotes", "tracknotes" }) do
    describe(kind .. " project-switch confirmation", function()
        it("keeps the old header and save destination when switching is cancelled", function()
            local harness = createHarness(kind)
            local view = harness.views[1]
            harness.switch("New Project")
            assert.are.equal(1, #view.documents)
            assert.are.equal(1, #harness.confirmations)
            harness.confirmations[1](false, nil)
            harness.add("preserved draft")
            assert.are.equal("preserved draft", harness.savedBody("Old Project"))
            assert.is_nil(harness.saved["New Project"])
            assert.are.equal(1, #view.documents)
            assert.is_truthy(view.documents[1]:find("Old Project", 1, true))
        end)

        it("changes the header and save destination only after explicit acceptance", function()
            local harness = createHarness(kind)
            harness.switch("New Project")
            harness.confirmations[1](true, nil)
            local documents = harness.views[1].documents
            assert.are.equal(2, #documents)
            assert.is_truthy(documents[2]:find("New Project", 1, true))
            harness.add("new project note")
            assert.are.equal("new project note", harness.savedBody("New Project"))
            assert.is_nil(harness.saved["Old Project"])
        end)

        it("keeps the existing document and destination when JavaScript fails", function()
            local harness = createHarness(kind)
            harness.switch("New Project")
            harness.confirmations[1](nil, { message = "document unavailable" })
            harness.add("still old")
            assert.are.equal("still old", harness.savedBody("Old Project"))
            assert.is_nil(harness.saved["New Project"])
            assert.are.equal(1, #harness.views[1].documents)
            assert.are.equal(1, #harness.alerts)
        end)

        it("does not treat a missing JavaScript result as permission to discard the draft", function()
            local harness = createHarness(kind)
            harness.switch("New Project")
            harness.confirmations[1](nil, nil)
            harness.add("no confirmation")
            assert.are.equal("no confirmation", harness.savedBody("Old Project"))
            assert.is_nil(harness.saved["New Project"])
            assert.are.equal(1, #harness.views[1].documents)
            assert.are.equal(1, #harness.alerts)
        end)

        it("does not apply a delayed confirmation after close and reopen", function()
            local harness = createHarness(kind)
            harness.switch("New Project")
            harness.views[1].closeCallback("closing")
            harness.switch("Third Project")
            harness.confirmations[1](true, nil)
            assert.are.equal(1, #harness.views[2].documents)
            harness.add("fresh window")
            assert.are.equal("fresh window", harness.savedBody("Third Project"))
            assert.is_nil(harness.saved["New Project"])
        end)

        it("ignores older confirmations and switches only to the latest requested project", function()
            local harness = createHarness(kind)
            harness.switch("New Project")
            harness.switch("Third Project")
            harness.confirmations[1](true, nil)
            assert.are.equal(1, #harness.views[1].documents)
            harness.confirmations[2](true, nil)
            harness.add("latest request")
            assert.are.equal("latest request", harness.savedBody("Third Project"))
            assert.is_nil(harness.saved["New Project"])
        end)

        it("invalidates a pending switch when the current project's command is invoked", function()
            local harness = createHarness(kind)
            harness.switch("New Project")
            harness.switch("Old Project")
            harness.confirmations[1](true, nil)
            harness.add("stayed here")
            assert.are.equal("stayed here", harness.savedBody("Old Project"))
            assert.is_nil(harness.saved["New Project"])
            assert.are.equal(1, #harness.views[1].documents)
        end)

        it("keeps the document usable when the JavaScript bridge throws", function()
            local harness = createHarness(kind, { evaluateThrows = true })
            assert.has_no.errors(function() harness.switch("New Project") end)
            harness.add("retry later")
            assert.are.equal("retry later", harness.savedBody("Old Project"))
            assert.is_nil(harness.saved["New Project"])
            assert.are.equal(1, #harness.views[1].documents)
        end)
    end)
end

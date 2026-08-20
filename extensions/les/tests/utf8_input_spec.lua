--  SPDX-License-Identifier: MIT

package.path = package.path .. ";extensions/les/?.lua"

local function findUpvalue(fn, targetName)
    for index = 1, 100 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == targetName then return value end
    end
    error("upvalue not found: " .. targetName)
end

local function setUpvalue(fn, targetName, newValue)
    for index = 1, 100 do
        local name = debug.getupvalue(fn, index)
        if not name then break end
        if name == targetName then
            debug.setupvalue(fn, index, newValue)
            return
        end
    end
    error("upvalue not found: " .. targetName)
end

local function loadSandbox(path, values, modules)
    local environment = setmetatable(values or {}, { __index = _G })
    environment._G = environment
    environment.require = function(name)
        if modules and modules[name] ~= nil then return modules[name] end
        return require(name)
    end
    local chunk = assert(loadfile(path, "t", environment))
    return environment, chunk()
end

local function readSource(path)
    local file = assert(io.open(path, "rb"))
    local source = assert(file:read("*a"))
    assert(file:close())
    return source
end

local function chatRequestCount(text)
    local requests = {}
    local _, chat = loadSandbox("extensions/les/ai/chat.lua", {
        L = function(key) return key end,
    }, {
        ["ai.openai"] = {
            chat = function(messages)
                requests[#requests + 1] = messages
            end,
        },
        ["util.windowframe"] = {},
    })
    local handleSend = findUpvalue(chat.toggle, "handleSend")
    setUpvalue(handleSend, "_webview", {
        evaluateJavaScript = function() end,
    })
    handleSend(text)
    return #requests
end

local function recommendRequestCount(extra, asInitialContext)
    local requests = {}
    local callbacks = {}
    local usercontent

    local webview = {}
    for _, method in ipairs({
        "windowStyle", "windowTitle", "allowTextEntry", "html", "deleteOnClose",
        "windowCallback", "show", "bringToFront", "evaluateJavaScript",
    }) do
        webview[method] = function(self) return self end
    end

    local hs = {
        screen = {
            mainScreen = function()
                return { frame = function() return { x = 0, y = 0, w = 1200, h = 800 } end }
            end,
        },
        webview = {
            usercontent = {
                new = function()
                    usercontent = {}
                    function usercontent:setCallback(callback)
                        self.callback = callback
                        return self
                    end
                    return usercontent
                end,
            },
            new = function() return webview end,
        },
    }

    local _, recommend = loadSandbox("extensions/les/ai/recommend.lua", {
        hs = hs,
        L = function(key) return key end,
        HSMakeAlert = function() end,
        programName = "LES Test",
    }, {
        ["ai.openai"] = {
            isConfigured = function() return true end,
            chat = function(messages, callback)
                requests[#requests + 1] = messages
                callbacks[#callbacks + 1] = callback
            end,
        },
        ["tracking.pluginstats"] = { getAll = function() return {} end },
        ["util.windowframe"] = {
            center = function() return { x = 0, y = 0, w = 480, h = 520 } end,
        },
    })

    recommend.open(asInitialContext and extra or nil)
    if asInitialContext then return #requests end
    callbacks[1]("ready", nil)
    usercontent.callback({ body = { action = "ask", extra = extra } })
    return #requests
end

local function makeProjectNotes()
    local _, projectnotes = loadSandbox("extensions/les/tracking/projectnotes.lua", {
        hs = { timer = { secondsSinceEpoch = function() return 123 end } },
    }, {
        ["util.storagekey"] = { forProject = function() return "fixture" end },
        ["util.noteid"] = { create = function() return "note-id" end },
        ["util.windowframe"] = {},
    })
    projectnotes.load = function() return {} end
    projectnotes.save = function() return true end
    return projectnotes
end

local function makeTrackNotes()
    local _, tracknotes = loadSandbox("extensions/les/tracking/tracknotes.lua", {
        hs = { timer = { secondsSinceEpoch = function() return 123 end } },
    }, {
        ["util.storagekey"] = { forProject = function() return "fixture" end },
        ["util.noteid"] = { create = function() return "note-id" end },
        ["util.windowframe"] = {},
    })
    tracknotes.loadAll = function() return {} end
    tracknotes.saveAll = function() return true end
    return tracknotes
end

describe("UTF-8 input limits", function()
    it("counts ASCII, Japanese, and emoji code points and rejects malformed UTF-8", function()
        package.loaded["util.utf8text"] = nil
        local utf8text = require("util.utf8text")

        assert.are.equal(4, utf8text.length("abcd"))
        assert.are.equal(4, utf8text.length("日本語文"))
        -- The variation selector in 🎛️ is a separate code point, matching
        -- Array.from(value).length in the WebView validation.
        assert.are.equal(2, utf8text.length("🎛️"))
        assert.are.equal(4, utf8text.length("😀🎹🎛️"))
        assert.is_nil(utf8text.length(string.char(0xff)))
    end)

    it("lets native fields hold surrogate pairs and enforces code-point limits in JavaScript", function()
        local cases = {
            {
                path = "extensions/les/ai/chat.lua",
                nativeLimit = "MAX_INPUT_LENGTH * 2",
            },
            {
                path = "extensions/les/ai/recommend.lua",
                nativeLimit = "MAX_EXTRA_LENGTH * 2",
            },
            {
                path = "extensions/les/tracking/projectnotes.lua",
                nativeLimit = "MAX_NOTE_LENGTH * 2",
            },
            {
                path = "extensions/les/tracking/tracknotes.lua",
                nativeLimit = "MAX_TRACK_NAME_LENGTH * 2",
            },
        }

        for _, case in ipairs(cases) do
            local source = readSource(case.path)
            assert.is_truthy(source:find("Array.from(value).length", 1, true), case.path)
            assert.is_truthy(source:find(case.nativeLimit, 1, true), case.path)
        end
        local track = readSource("extensions/les/tracking/tracknotes.lua")
        assert.is_truthy(track:find("MAX_NOTE_LENGTH * 2", 1, true))
    end)

    it("accepts chat input at the character limit and rejects over-limit or malformed input", function()
        assert.are.equal(1, chatRequestCount(string.rep("a", 8000)))
        assert.are.equal(1, chatRequestCount(string.rep("あ", 8000)))
        assert.are.equal(1, chatRequestCount(string.rep("😀", 8000)))
        assert.are.equal(0, chatRequestCount(string.rep("a", 8001)))
        assert.are.equal(0, chatRequestCount(string.char(0xff)))
    end)

    it("accepts recommendation context at the character limit", function()
        assert.are.equal(2, recommendRequestCount(string.rep("a", 4000)))
        assert.are.equal(2, recommendRequestCount(string.rep("あ", 4000)))
        assert.are.equal(2, recommendRequestCount(string.rep("😀", 4000)))
        assert.are.equal(1, recommendRequestCount(string.rep("a", 4001)))
        assert.are.equal(1, recommendRequestCount(string.char(0xff)))
        assert.are.equal(1, recommendRequestCount(string.rep("あ", 4000), true))
        assert.are.equal(1, recommendRequestCount(string.rep("😀", 4000), true))
        assert.are.equal(0, recommendRequestCount(string.rep("a", 4001), true))
        assert.are.equal(0, recommendRequestCount(string.char(0xff), true))
    end)

    it("validates project-note bodies by UTF-8 character count", function()
        local projectnotes = makeProjectNotes()

        assert.is_true(projectnotes.addNote("project", string.rep("a", 20000)))
        assert.is_true(projectnotes.addNote("project", string.rep("あ", 20000)))
        assert.is_true(projectnotes.addNote("project", string.rep("😀", 20000)))
        assert.is_false(projectnotes.addNote("project", string.rep("a", 20001)))
        assert.is_false(projectnotes.addNote("project", string.char(0xff)))
    end)

    it("validates track names and note bodies by UTF-8 character count", function()
        local tracknotes = makeTrackNotes()

        assert.is_true(tracknotes.addNote("project", string.rep("あ", 200), "memo"))
        assert.is_true(tracknotes.addNote("project", string.rep("😀", 200), string.rep("😀", 20000)))
        assert.is_false(tracknotes.addNote("project", string.rep("a", 201), "memo"))
        assert.is_false(tracknotes.addNote("project", "Lead", string.rep("a", 20001)))
        assert.is_false(tracknotes.addNote("project", string.char(0xff), "memo"))
        assert.is_false(tracknotes.addNote("project", "Lead", string.char(0xff)))
    end)
end)

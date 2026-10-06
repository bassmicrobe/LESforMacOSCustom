--  SPDX-License-Identifier: MIT

package.path = package.path .. ";extensions/les/?.lua"

local originalHs = rawget(_G, "hs")
local originalStats = package.loaded["tracking.pluginstats"]
local savedGlobals
local globalNames = {
    "firstRightClick", "timeRMBTime", "firstDown", "secondDown", "loadPlugin", "bookmarkfunc",
    "spawnPluginMenu", "spawnPianoMenu", "getABSTime", "nanoToSec", "titlebarheight",
    "getLiveHsAppObj", "autoadd", "loadspeed", "resettobrowserbookmark", "cancelPendingPluginLoad",
    "directshyper", "buplicate", "quickmacro", "pausebutton", "debounce", "buplicatelastshortcut",
    "double0todelete", "getValidTitles", "disableloop", "selectLiveMenuItem", "saveasnewver",
    "cancelPendingSaveAs", "absolutereplace", "ctrlabsoluteduplicate", "astBlockingQuery", "programName",
}

local function makeHarness()
    local state = { events = {}, pending = {}, now = 0, front = true, available = true, uses = {} }
    local app = {
        activate = function() return true end,
        isFrontmost = function() return state.front end,
        mainWindow = function() return { title = function() return state.title or "Session_1  [Session]" end } end,
    }
    local function timer(callback, predicate)
        local value = { callback = callback, predicate = predicate, active = true }
        function value:stop() self.active = false end
        state.pending[#state.pending + 1] = value
        return value
    end
    local function eventTap(_, callback)
        return { callback = callback, start = function(self) return self end, stop = function() end }
    end
    local hsMock = {
        timer = {
            doAfter = function(_, callback) return timer(callback) end,
            waitUntil = function(predicate, callback) return timer(callback, predicate) end,
            secondsSinceEpoch = function() return state.now end,
        },
        eventtap = {
            new = eventTap,
            doubleClickInterval = function() return 0.4 end,
            checkKeyboardModifiers = function() return state.mods or {} end,
            keyStroke = function(_, key) state.events[#state.events + 1] = key end,
            keyStrokes = function(value) state.events[#state.events + 1] = value end,
            event = {
                types = { keyDown = 1, keyUp = 2, leftMouseDown = 3, leftMouseUp = 4, rightMouseDown = 5, rightMouseUp = 6 },
                properties = { mouseEventClickState = 1 },
            },
        },
        keycodes = { map = { ["0"] = 29, ["1"] = 18, B = 11, M = 46, D = 2, V = 9, S = 1, delete = 51 } },
        hotkey = { bind = function() return {} end },
    }
    function state:tick()
        self.now = self.now + 0.05
        local queue = self.pending
        self.pending = {}
        for _, pending in ipairs(queue) do
            if pending.active then
                if not pending.predicate or pending.predicate() then
                    pending.active = false
                    pending.callback()
                else
                    self.pending[#self.pending + 1] = pending
                end
            end
        end
    end
    function state:emit(key, kind)
        local _ = self
        quickmacro.callback({
            getKeyCode = function() return hsMock.keycodes.map[key] end,
            getType = function() return hsMock.eventtap.event.types[kind] end,
        })
    end
    rawset(_G, "hs", hsMock)
    rawset(_G, "getLiveHsAppObj", function() return state.available and app or nil end)
    package.loaded["tracking.pluginstats"] = { recordUse = function(name) state.uses[#state.uses + 1] = name end }
    rawset(_G, "autoadd", 1)
    rawset(_G, "loadspeed", 0.1)
    rawset(_G, "resettobrowserbookmark", 0)
    rawset(_G, "absolutereplace", 1)
    rawset(_G, "ctrlabsoluteduplicate", 0)
    return state
end

describe("shortcut event lifecycle", function()
    before_each(function()
        savedGlobals = {}
        for _, name in ipairs(globalNames) do savedGlobals[name] = rawget(_G, name) end
    end)

    after_each(function()
        for _, name in ipairs(globalNames) do rawset(_G, name, savedGlobals[name]) end
        rawset(_G, "hs", originalHs)
        package.loaded["tracking.pluginstats"] = originalStats
    end)

    it("does not type into another application when Live is absent", function()
        local state = makeHarness()
        dofile("extensions/les/shortcuts/rightclick.lua")
        state.available = false
        loadPlugin("Operator")
        assert.same({}, state.events)
        assert.same({}, state.uses)
    end)

    it("abandons activation timeout without sending search or text", function()
        local state = makeHarness()
        dofile("extensions/les/shortcuts/rightclick.lua")
        state.front = false
        loadPlugin("Operator")
        for _ = 1, 45 do state:tick() end
        assert.same({}, state.events)
        assert.same({}, state.uses)
        assert.same({}, state.pending)
    end)

    it("cancels delayed typing when focus leaves Live", function()
        local state = makeHarness()
        dofile("extensions/les/shortcuts/rightclick.lua")
        loadPlugin("Operator")
        state:tick()
        state.front = false
        state:tick()
        assert.same({ "f" }, state.events)
        assert.same({}, state.uses)
    end)

    it("cancels confirmation after focus leaves Live", function()
        local state = makeHarness()
        dofile("extensions/les/shortcuts/rightclick.lua")
        loadPlugin("Operator")
        for _ = 1, 3 do state:tick() end
        state.front = false
        state:tick()
        assert.same({ "f", "Operator", "down" }, state.events)
    end)

    it("only inserts the latest selection when requests overlap", function()
        local state = makeHarness()
        dofile("extensions/les/shortcuts/rightclick.lua")
        loadPlugin("Operator")
        state:tick()
        loadPlugin("Wavetable")
        for _ = 1, 5 do state:tick() end
        assert.same({ "f", "f", "Wavetable", "down", "return", "escape" }, state.events)
        assert.same({ "Wavetable" }, state.uses)
    end)

    it("inserts once when Live stays focused", function()
        local state = makeHarness()
        dofile("extensions/les/shortcuts/rightclick.lua")
        loadPlugin("Operator")
        for _ = 1, 5 do state:tick() end
        assert.same({ "f", "Operator", "down", "return", "escape" }, state.events)
        assert.same({ "Operator" }, state.uses)
    end)

    it("stops all queued plugin input when macros are disabled", function()
        local state = makeHarness()
        dofile("extensions/les/shortcuts/rightclick.lua")
        loadPlugin("Operator")
        state:tick()
        cancelPendingPluginLoad()
        for _ = 1, 5 do state:tick() end
        assert.same({ "f" }, state.events)
    end)

    it("does not execute stale callbacks after a newer selection", function()
        local state = makeHarness()
        dofile("extensions/les/shortcuts/rightclick.lua")
        loadPlugin("Operator")
        state:tick()
        local oldCallback = state.pending[1].callback
        loadPlugin("Wavetable")
        oldCallback()
        for _ = 1, 5 do state:tick() end
        assert.same({ "f", "f", "Wavetable", "down", "return", "escape" }, state.events)
    end)

    it("does not submit a Save As filename after focus leaves Live", function()
        local state = makeHarness()
        rawset(_G, "saveasnewver", 1)
        rawset(_G, "selectLiveMenuItem", function(name) state.events[#state.events + 1] = name return true end)
        state.mods = { alt = true, cmd = true }
        dofile("extensions/les/shortcuts/macros.lua")
        state:emit("S", "keyDown")
        state.front = false
        state:tick()
        assert.same({ "Save Live Set As" }, state.events)
        assert.is_false(rawget(_G, "debounce"))
    end)

    it("does not continue Save As after the Untitled confirmation is cancelled", function()
        local state = makeHarness()
        rawset(_G, "saveasnewver", 1)
        rawset(_G, "programName", "LES")
        rawset(_G, "astBlockingQuery", function() return false end)
        rawset(_G, "selectLiveMenuItem", function(name) state.events[#state.events + 1] = name end)
        state.mods = { alt = true, cmd = true }
        state.title = "Untitled  [Untitled]"
        dofile("extensions/les/shortcuts/macros.lua")
        state:emit("S", "keyDown")
        state:tick()
        assert.same({}, state.events)
        assert.is_false(rawget(_G, "debounce"))
    end)

    it("does not type a filename when the Save As menu action fails", function()
        local state = makeHarness()
        rawset(_G, "saveasnewver", 1)
        rawset(_G, "selectLiveMenuItem", function() return false end)
        state.mods = { alt = true, cmd = true }
        dofile("extensions/les/shortcuts/macros.lua")
        state:emit("S", "keyDown")
        state:tick()
        assert.same({}, state.events)
        assert.is_false(rawget(_G, "debounce"))
    end)

    it("submits the new filename once after successful Save As activation", function()
        local state = makeHarness()
        rawset(_G, "saveasnewver", 1)
        rawset(_G, "selectLiveMenuItem", function() return true end)
        state.mods = { alt = true, cmd = true }
        dofile("extensions/les/shortcuts/macros.lua")
        state:emit("S", "keyDown")
        state:emit("S", "keyUp")
        state:tick()
        assert.same({ "Session_2", "return" }, state.events)
        state:tick()
        assert.is_false(rawget(_G, "debounce"))
    end)

    it("does not interpret a quick zero press and release as a double press", function()
        local state = makeHarness()
        rawset(_G, "double0todelete", 1)
        dofile("extensions/les/shortcuts/macros.lua")
        state:emit("0", "keyDown")
        state.now = 0.01
        state:emit("0", "keyUp")
        assert.same({}, state.events)
        state.now = 0.03
        state:emit("0", "keyDown")
        assert.same({ 51 }, state.events)
    end)

    it("runs a key-down macro once per press, not again on release", function()
        local state = makeHarness()
        rawset(_G, "disableloop", 1)
        state.mods = { shift = true, cmd = true }
        dofile("extensions/les/shortcuts/macros.lua")
        state:emit("M", "keyDown")
        state:emit("M", "keyUp")
        assert.same({ "J" }, state.events)
    end)

    it("retains release-triggered absolute duplicate behavior", function()
        local state = makeHarness()
        state.mods = { alt = true, cmd = true }
        rawset(_G, "selectLiveMenuItem", function(name) state.events[#state.events + 1] = name end)
        dofile("extensions/les/shortcuts/macros.lua")
        state:emit("D", "keyDown")
        assert.same({}, state.events)
        state:emit("D", "keyUp")
        assert.same({ "Copy", "Duplicate", "Delete", "Paste" }, state.events)
    end)
end)

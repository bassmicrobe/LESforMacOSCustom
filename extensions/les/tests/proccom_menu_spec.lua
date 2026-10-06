--  SPDX-License-Identifier: MIT

local function makeHarness()
    local state = { alerts = {}, selected = {}, succeeds = true }
    local app = {
        findMenuItem = function(_, name, regex)
            if name == "Save Live Set As" or (state.regexOnly and regex) then return {} end
        end,
        selectMenuItem = function(_, name, regex)
            state.selected[#state.selected + 1] = { name = name, regex = regex }
            if state.succeeds then return true end
        end,
    }
    local env = setmetatable({
        require = function() return {} end,
        hs = { alert = { show = function(message) state.alerts[#state.alerts + 1] = message end } },
        programName = "LES",
        gValidTitleTable = {},
        strSanitize = function(value) return value end,
        print = function() end,
    }, { __index = _G })
    assert(loadfile("extensions/les/proccom.lua", "t", env))()
    env.getLiveHsAppObj = function() return app end
    return env, state
end

describe("Live menu action results", function()
    it("returns success when the menu item was pressed", function()
        local env, state = makeHarness()
        assert.is_true(env.selectLiveMenuItem("Save Live Set As"))
        assert.are.equal(1, #state.selected)
        assert.are.equal(0, #state.alerts)
    end)

    it("reports failure when AX finds the menu but cannot press it", function()
        local env, state = makeHarness()
        state.succeeds = false
        assert.is_false(env.selectLiveMenuItem("Save Live Set As"))
        assert.are.equal(1, #state.alerts)
    end)

    it("passes regex mode through to the fallback selection", function()
        local env, state = makeHarness()
        state.regexOnly = true
        assert.is_true(env.selectLiveMenuItem("Localized Action"))
        assert.is_true(state.selected[1].regex)
    end)
end)

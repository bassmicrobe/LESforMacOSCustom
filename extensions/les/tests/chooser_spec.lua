-- SPDX-License-Identifier: MIT
package.path = package.path .. ";extensions/les/?.lua"

local function harness()
    local choosers = {}
    local reads, loaded = 0, 0
    local stats = {
        getAll = function() reads = reads + 1 return {} end,
        getFavorites = function() return {"Synth"} end,
    }
    local env = setmetatable({
        menu = {{title = "音源 › 鍵盤", menu = {{title = "Synth", fn = function() loaded = loaded + 1 end}}}},
        hs = {
            chooser = {new = function(callback)
                local chooser = {callback = callback}
                function chooser:choices(value) self.items = value return self end
                function chooser:delete() return self end
                function chooser:placeholderText() return self end
                function chooser:searchSubText() return self end
                function chooser:rows() return self end
                function chooser:width() return self end
                function chooser:show() return self end
                choosers[#choosers + 1] = chooser
                return chooser
            end},
        },
        require = function(name)
            if name == "tracking.pluginstats" then return stats end
            return require(name)
        end,
    }, {__index = _G})
    assert(loadfile("extensions/les/menus/chooser.lua", "t", env))()
    return {env = env, choosers = choosers, reads = function() return reads end, loaded = function() return loaded end}
end

describe("plugin chooser", function()
    it("keeps Japanese category names intact and filters the matching plugins", function()
        local state = harness()
        state.env.openPluginChooser()
        local chooser = state.choosers[1]
        chooser.callback(chooser.items[2])
        local categories = state.choosers[2]
        assert.are.equal("音源", categories.items[2].text)
        categories.callback(categories.items[2])
        local filtered = state.choosers[3]
        assert.are.equal("Synth", filtered.items[#filtered.items].text)
        filtered.callback(filtered.items[#filtered.items])
        assert.are.equal(1, state.loaded())
    end)

    it("uses one stats snapshot for sorting, favorites and subtitles per open", function()
        local state = harness()
        state.env.openPluginChooser()
        assert.are.equal(1, state.reads())
        assert.are.equal("★ Synth", state.choosers[1].items[4].text)
    end)
end)

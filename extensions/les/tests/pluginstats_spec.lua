-- SPDX-License-Identifier: MIT

local json = require("dkjson")

local function harness(initial, failure)
    local state = {disk = initial, timers = {}, renames = 0, writes = 0}
    local cacheTime = 1000
    local environment = setmetatable({
        ScriptUserResourcesPath = "/fixture",
        strJoinPaths = function(a, b) return a .. "/" .. b end,
        ShellCreateDirectory = function() end,
        print = function() end,
        hs = {
            json = {encode = function(value) return json.encode(value) end, decode = function(raw)
                local value, _, err = json.decode(raw)
                if err then error(err) end
                return value
            end},
            timer = {
                secondsSinceEpoch = function() return cacheTime end,
                doAfter = function(_, callback) state.timers[#state.timers + 1] = callback end,
            },
        },
        io = {open = function(_, mode)
            if mode == "r" then
                if state.disk == nil then return nil, "not found", 2 end
                return {read = function() return state.disk end, close = function() return true end}
            end
            return {
                write = function(_, content)
                    state.writes = state.writes + 1
                    if failure == "write" then return nil, "disk full" end
                    state.temp = content
                    return true
                end,
                close = function()
                    if failure == "close" then return nil, "disk full" end
                    return true
                end,
            }
        end},
        os = setmetatable({
            remove = function() state.temp = nil return true end,
            rename = function()
                state.renames = state.renames + 1
                if failure == "rename" then return nil, "replacement denied" end
                state.disk = state.temp
                return true
            end,
        }, {__index = os}),
    }, {__index = _G})
    local stats = assert(loadfile("extensions/les/tracking/pluginstats.lua", "t", environment))()
    return stats, state
end

describe("plugin statistics boundary and persistence", function()
    it("sanitizes malformed records, numeric fields and favorite flags", function()
        local stats = harness([[{"Broken":"bad","Lead":{"use_count":"oops","last_used_at":1e300,
            "added_at":-1,"favorited":"yes"},"Bass":{"use_count":3.9,"favorited":true}}]])
        assert.has_no.errors(function() stats.getFavorites() end)
        assert.is_nil(stats.get("Broken"))
        assert.are.equal(0, stats.get("Lead").use_count)
        assert.are.equal(0, stats.get("Lead").last_used_at)
        assert.are.equal(0, stats.get("Lead").added_at)
        assert.is_false(stats.isFavorite("Lead"))
        assert.are.equal(3, stats.get("Bass").use_count)
        assert.same({"Bass"}, stats.getFavorites())
    end)

    it("does not expose its cached objects to callers", function()
        local stats = harness([[{"Lead":{"use_count":3}}]])
        local snapshot = stats.getAll()
        snapshot.Lead.use_count = 99
        stats.get("Lead").use_count = 100
        assert.are.equal(3, stats.get("Lead").use_count)
    end)

    it("keeps disk and cache unchanged after a failed write", function()
        local initial = [[{"Lead":{"use_count":3,"favorited":false}}]]
        local stats, state = harness(initial, "write")
        assert.is_false(stats.toggleFavorite("Lead"))
        assert.is_false(stats.isFavorite("Lead"))
        assert.are.equal(initial, state.disk)
        assert.are.equal(0, state.renames)
        assert.is_nil(state.temp)
    end)

    it("does not overwrite corrupt JSON while recording usage", function()
        local stats, state = harness("{broken")
        stats.recordUse("Lead")
        state.timers[1]()
        assert.are.equal("{broken", state.disk)
        assert.are.equal(0, state.writes)
    end)

    for _, failure in ipairs({"close", "rename"}) do
        it("keeps the persisted favorite and cached state after " .. failure .. " fails", function()
            local initial = [[{"Lead":{"use_count":3,"favorited":false}}]]
            local stats, state = harness(initial, failure)
            local favorited, err = stats.toggleFavorite("Lead")
            assert.is_false(favorited)
            assert.is_string(err)
            assert.is_false(stats.isFavorite("Lead"))
            assert.are.equal(3, stats.get("Lead").use_count)
            assert.are.equal(initial, state.disk)
            assert.is_nil(state.temp)
        end)
    end

    it("coalesces a burst into one write without losing plugin counts", function()
        local stats, state = harness([[{"Lead":{"use_count":3,"favorited":true}}]])
        for _ = 1, 20 do stats.recordUse("Lead") end
        stats.recordUse("Bass")
        assert.are.equal(1, #state.timers)
        assert.are.equal(0, state.writes)
        state.timers[1]()
        local persisted = json.decode(state.disk)
        assert.are.equal(23, persisted.Lead.use_count)
        assert.is_true(persisted.Lead.favorited)
        assert.are.equal(1, persisted.Bass.use_count)
        assert.are.equal(1, state.writes)
        assert.are.equal(1, state.renames)
    end)
end)

--  SPDX-License-Identifier: MIT

package.path = package.path .. ";extensions/les/?.lua"

local projectChangeCount = 0
package.preload["tracking.notifications"] = function()
    return {
        checkExport = function() end,
        onProjectChange = function()
            projectChangeCount = projectChangeCount + 1
        end,
        checkHourly = function() end,
    }
end

local title = "Ableton Live [Client A]"
local fakeWindow = { title = function() return title end }
local fakeApp = { mainWindow = function() return fakeWindow end }

local hsGlobal = rawget(_G, "hs") or {}
hsGlobal.window = hsGlobal.window or {}
hsGlobal.window.filter = {
    windowTitleChanged = "windowTitleChanged",
    new = function()
        return { subscribe = function() end }
    end,
}
hsGlobal.timer = hsGlobal.timer or {}
hsGlobal.timer.new = function()
    return {
        start = function() end,
        stop = function() end,
        running = function() return false end,
    }
end
hsGlobal.timer.secondsSinceEpoch = function() return 1000 end
hsGlobal.hash = hsGlobal.hash or {
    SHA256 = function(value)
        local total = 0
        for index = 1, #value do total = (total + value:byte(index) * index) % 0xFFFFFFFF end
        return string.format("%064x", total)
    end,
}
rawset(_G, "hs", hsGlobal)

rawset(_G, "ScriptUserResourcesPath", "/tmp/les_timer_test")
rawset(_G, "StrictTimeModifier", "strict.txt")
rawset(_G, "vstshortcuts", 0)
rawset(_G, "getLiveHsAppObj", function() return fakeApp end)
rawset(_G, "strJoinPaths", function(left, right) return left .. "/" .. right end)
rawset(_G, "GetDataPath", function(path) return "/tmp/les_timer_test/" .. path end)
rawset(_G, "ShellCreateDirectory", function() end)

local writeCount = 0
rawset(_G, "ShellOverwriteFile", function()
    writeCount = writeCount + 1
end)

rawset(_G, "trackname", nil)
package.loaded["tracking.timer"] = nil
require("tracking.timer")

describe("project timer title updates", function()
    before_each(function()
        rawset(_G, "trackname", nil)
        rawset(_G, "timer_Client A", nil)
        writeCount = 0
        projectChangeCount = 0
        title = "Ableton Live [Client A]"
    end)

    it("does not flush and reload when only the window title event repeats", function()
        coolfunc()
        rawset(_G, "timer_Client A", 12)
        coolfunc()

        assert.are.equal(0, writeCount)
        assert.are.equal(1, projectChangeCount)
        assert.are.equal(12, rawget(_G, "timer_Client A"))
    end)

    it("flushes once when switching to a different project", function()
        coolfunc()
        rawset(_G, "timer_Client A", 12)
        title = "Ableton Live [Client B]"
        coolfunc()

        assert.are.equal(1, writeCount)
        assert.are.equal(2, projectChangeCount)
        assert.are.equal("Client B", rawget(_G, "trackname"))
    end)
end)

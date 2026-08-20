--  SPDX-License-Identifier: MIT

local SOURCE_PATH = "extensions/_coresetup/_coresetup.lua"

local function readSource()
    local file = assert(io.open(SOURCE_PATH, "rb"))
    local source = assert(file:read("*a"))
    assert(file:close())
    return source
end

describe("core setup command boundaries", function()
    it("does not construct the first-run copy command with zsh", function()
        local source = readSource()

        assert.is_nil(source:find("copyExecInstruction", 1, true))
        assert.is_nil(source:find('os.execute("zsh -c', 1, true))
    end)

    it("passes the relaunch bundle path as an argv value", function()
        local source = readSource()

        assert.is_nil(source:find("open -a \"%]%]..hs.processInfo.bundlePath", 1, true))
        assert.is_truthy(source:find('require("hs.task")', 1, true))
    end)
end)

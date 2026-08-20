--  SPDX-License-Identifier: MIT

local function readSource(path)
    local file = assert(io.open(path, "rb"))
    local source = assert(file:read("*a"))
    assert(file:close())
    return source
end

describe("narrow auxiliary windows", function()
    it("allows the track-name field to shrink before navigation controls overflow", function()
        local source = readSource("extensions/les/tracking/tracknotes.lua")
        assert.is_truthy(source:find("#trackInput{flex:1;min-width:0", 1, true))
    end)

    it("wraps menu editor rows and lets selects shrink on narrow screens", function()
        local source = readSource("extensions/les/menus/menuconfiggui.lua")
        assert.is_truthy(source:find(".pr{flex-wrap:wrap}", 1, true))
        assert.is_truthy(source:find("min-width:0;max-width:100%", 1, true))
    end)
end)

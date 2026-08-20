--  SPDX-License-Identifier: MIT

package.path = package.path .. ";extensions/les/?.lua"

local windowframe = require("util.windowframe")

describe("webview window geometry", function()
    it("centers and clamps a preferred frame inside a small screen", function()
        assert.are.same({x = 12, y = 12, w = 296, h = 456}, windowframe.center(
            {x = 0, y = 0, w = 320, h = 480}, 860, 640, 12
        ))
    end)

    it("anchors right while retaining an on-screen margin", function()
        assert.are.same({x = 528, y = 60, w = 460, h = 580}, windowframe.right(
            {x = 0, y = 0, w = 1000, h = 700}, 460, 580, 12, 60
        ))
    end)
end)

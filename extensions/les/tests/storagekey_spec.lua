--  SPDX-License-Identifier: MIT

package.path = package.path .. ";extensions/les/?.lua"

local storageKey = require("util.storagekey")

local function fakeSHA256(value)
    local total = 0
    for index = 1, #value do
        total = (total + value:byte(index) * index) % 0xFFFFFFFF
    end
    return string.format("%064x", total)
end

describe("project storage keys", function()
    it("keeps legacy-colliding project names isolated", function()
        local space = storageKey.forProject("Client A", fakeSHA256)
        local dash = storageKey.forProject("Client-A", fakeSHA256)
        local slash = storageKey.forProject("Client/A", fakeSHA256)

        assert.are_not.equal(space, dash)
        assert.are_not.equal(space, slash)
        assert.are_not.equal(dash, slash)
    end)

    it("returns a deterministic filesystem-safe bounded key", function()
        local name = ("日本語 / project ? "):rep(40)
        local first = storageKey.forProject(name, fakeSHA256)
        local second = storageKey.forProject(name, fakeSHA256)

        assert.are.equal(first, second)
        assert.matches("^[%w_-]+$", first)
        assert.is_true(#first <= 180)
    end)
end)

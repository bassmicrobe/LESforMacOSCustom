--  SPDX-License-Identifier: MIT

local function channel(value)
    local normalized = value / 255
    if normalized <= 0.04045 then return normalized / 12.92 end
    return ((normalized + 0.055) / 1.055) ^ 2.4
end

local function luminance(hex)
    local r, g, b = hex:match("^#(%x%x)(%x%x)(%x%x)$")
    assert(r and g and b, "invalid hex color: " .. tostring(hex))
    return 0.2126 * channel(tonumber(r, 16))
        + 0.7152 * channel(tonumber(g, 16))
        + 0.0722 * channel(tonumber(b, 16))
end

local function contrast(left, right)
    local a, b = luminance(left), luminance(right)
    local lighter, darker = math.max(a, b), math.min(a, b)
    return (lighter + 0.05) / (darker + 0.05)
end

local function readSource(path)
    local file = assert(io.open(path, "rb"))
    local source = assert(file:read("*a"))
    assert(file:close())
    return source
end

describe("dark UI contrast", function()
    it("keeps secondary text above the normal-text threshold", function()
        assert.is_true(contrast("#a1a1a6", "#1c1c1e") >= 4.5)
        assert.is_true(contrast("#8e8e93", "#1c1c1e") >= 4.5)
        assert.is_true(contrast("#a6adc8", "#1e1e2e") >= 4.5)
    end)

    it("uses dark text on the active green HUD", function()
        local source = readSource("extensions/les/ui/hud.lua")
        assert.is_truthy(source:find(
            "fg   = {red = 0.0,   green = 0.0,   blue = 0.0", 1, true
        ))
    end)

    it("does not restore the audited low-contrast helper colors", function()
        local chat = readSource("extensions/les/ai/chat.lua")
        local project = readSource("extensions/les/tracking/projectnotes.lua")
        local cheatsheet = readSource("extensions/les/ui/cheatsheet.lua")

        assert.is_nil(chat:find(".typing { align-self: flex-start; color: #636366", 1, true))
        assert.is_nil(project:find(".project-label { font-size: 11px; color: #636366", 1, true))
        assert.is_nil(cheatsheet:find("color: #48484a;", 1, true))
    end)
end)

--  SPDX-License-Identifier: MIT

local function readSource(path)
    local file = assert(io.open(path, "rb"))
    local source = assert(file:read("*a"))
    assert(file:close())
    return source
end

describe("window shortcut documentation", function()
    it("matches the Cmd-based handlers", function()
        local paths = {
            "README.md",
            "docs/FEATURE_COMPARISON.md",
            "extensions/les/util/locale.lua",
            "extensions/les/settings.lua",
            "extensions/les/ui/cheatsheet.lua",
        }

        for _, path in ipairs(paths) do
            local source = readSource(path)
            assert.is_truthy(source:find("Cmd+W", 1, true), path)
            assert.is_truthy(source:find("Cmd+Alt+W", 1, true), path)
            assert.is_nil(source:find("Ctrl+Shift+W", 1, true), path)
        end
    end)

    it("documents the plugin chooser binding", function()
        local source = readSource("extensions/les/ui/cheatsheet.lua")
        assert.is_truthy(source:find("Cmd+Shift+H", 1, true))
        assert.is_nil(source:find("Cmd+Shift+F", 1, true))
    end)
end)

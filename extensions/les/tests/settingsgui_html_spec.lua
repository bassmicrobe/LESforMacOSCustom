--  SPDX-License-Identifier: MIT

package.path = package.path .. ";extensions/les/?.lua"

local dkjson = require("dkjson")
local locale = require("util.locale")
local SOURCE_PATH = "extensions/les/menus/settingsgui.lua"

local function loadBuilder()
    local environment = setmetatable({
        BundleResourcePath = "extensions/les",
        settingsManager = {},
        L = function(key) return locale.translate(key, "ja") end,
        hs = {
            json = {
                encode = function(value) return dkjson.encode(value) end,
                decode = function(value) return dkjson.decode(value) end,
            },
        },
    }, {__index = _G})
    environment._G = environment
    assert(loadfile(SOURCE_PATH, "t", environment))()

    for index = 1, 100 do
        local name, value = debug.getupvalue(environment.openSettingsGUI, index)
        if not name then break end
        if name == "buildSettingsHTML" then return value end
    end
    error("buildSettingsHTML upvalue was not found")
end

describe("settings HTML", function()
    it("keeps ids and data keys free of formatting whitespace", function()
        local html = loadBuilder()()

        assert.is_truthy(html:find('id="setting-autoadd"', 1, true))
        assert.is_truthy(html:find('for="setting-autoadd"', 1, true))
        assert.is_truthy(html:find('data-key="openaikey"', 1, true))
        assert.is_truthy(html:find('aria-labelledby="label-autoadd"', 1, true))
        assert.is_nil(html:find('id="setting-\n', 1, true))
        assert.is_nil(html:find('data-key="\n', 1, true))
    end)
end)

--  SPDX-License-Identifier: MIT

local function readSource(path)
    local file = assert(io.open(path, "rb"))
    local source = assert(file:read("*a"))
    assert(file:close())
    return source
end

local WEBVIEW_SOURCES = {
    "extensions/les/ai/chat.lua",
    "extensions/les/ai/recommend.lua",
    "extensions/les/menus/menuconfiggui.lua",
    "extensions/les/menus/settingsgui.lua",
    "extensions/les/tracking/projectnotes.lua",
    "extensions/les/tracking/tracknotes.lua",
    "extensions/les/ui/cheatsheet.lua",
    "extensions/les/vst/scanner.lua",
}

describe("embedded webview UX", function()
    it("releases every closable webview's native resources", function()
        for _, path in ipairs(WEBVIEW_SOURCES) do
            local source = readSource(path)
            assert.is_truthy(source:find(":deleteOnClose(true)", 1, true), path)
        end
    end)

    it("exposes document language, visible keyboard focus, and live status", function()
        for _, path in ipairs(WEBVIEW_SOURCES) do
            local source = readSource(path)
            assert.is_truthy(source:find("lang=", 1, true), path)
        end

        for _, path in ipairs({
            "extensions/les/ai/chat.lua",
            "extensions/les/menus/menuconfiggui.lua",
            "extensions/les/menus/settingsgui.lua",
            "extensions/les/tracking/projectnotes.lua",
            "extensions/les/tracking/tracknotes.lua",
        }) do
            local source = readSource(path)
            assert.is_truthy(source:find(":focus-visible", 1, true), path)
        end

        local chat = readSource("extensions/les/ai/chat.lua")
        assert.is_truthy(chat:find("aria-live=", 1, true))
        local settings = readSource("extensions/les/menus/settingsgui.lua")
        assert.is_truthy(settings:find("role='status'", 1, true))
    end)

    it("labels icon-only controls and supports keyboard menu editing", function()
        local tracknotes = readSource("extensions/les/tracking/tracknotes.lua")
        assert.is_truthy(tracknotes:find('L("tracknotes_prev_label")', 1, true))
        assert.is_truthy(tracknotes:find('L("tracknotes_next_label")', 1, true))

        local menuconfig = readSource("extensions/les/menus/menuconfiggui.lua")
        assert.is_truthy(menuconfig:find('role="button"', 1, true))
        assert.is_truthy(menuconfig:find("onkeydown=", 1, true))
        assert.is_truthy(menuconfig:find("function pup(", 1, true))
        assert.is_truthy(menuconfig:find("function pdn(", 1, true))
    end)

    it("announces plugin-scan progress without replacing the whole document", function()
        local scanner = readSource("extensions/les/vst/scanner.lua")
        assert.is_truthy(scanner:find('role="progressbar"', 1, true))
        assert.is_truthy(scanner:find('aria-live="polite"', 1, true))
        assert.is_truthy(scanner:find("function setProgress", 1, true))
        assert.is_truthy(scanner:find(":evaluateJavaScript", 1, true))
        assert.is_truthy(scanner:find("local scanInProgress = false", 1, true))
        assert.is_truthy(scanner:find("if scanInProgress then", 1, true))
        assert.is_truthy(scanner:find("showScanProgress()", 1, true))
    end)

    it("ships every settings utility used by the responsive API row", function()
        local css = readSource("extensions/les/assets/settings-tw.css")
        assert.is_truthy(css:find(".gap-2", 1, true))
        assert.is_truthy(css:find(".w-\\[200px\\]", 1, true))
    end)
end)

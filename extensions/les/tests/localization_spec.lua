--  SPDX-License-Identifier: MIT

package.path = package.path .. ";extensions/les/?.lua"

local dkjson = require("dkjson")
local originalL = rawget(_G, "L")
local originalUiLanguage = rawget(_G, "uiLanguage")
local originalLocaleModule = package.loaded["util.locale"]

local locale

local function findUpvalue(fn, targetName)
    for index = 1, 100 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == targetName then return value end
    end
    error("upvalue not found: " .. targetName)
end

local function setUpvalue(fn, targetName, newValue)
    for index = 1, 100 do
        local name = debug.getupvalue(fn, index)
        if not name then break end
        if name == targetName then
            debug.setupvalue(fn, index, newValue)
            return
        end
    end
    error("upvalue not found: " .. targetName)
end

local function loadSandbox(path, modules)
    local environment
    environment = setmetatable({
        L = function(key) return _G.L(key) end,
        hs = {},
        require = function(name) return modules[name] or {} end,
    }, { __index = _G })
    environment._G = _G
    local chunk = assert(loadfile(path, "t", environment))
    return environment, chunk()
end

local function renderChat()
    local _, chat = loadSandbox("extensions/les/ai/chat.lua", {
        ["ai.openai"] = {},
        ["util.windowframe"] = {},
        ["util.utf8text"] = require("util.utf8text"),
    })
    return findUpvalue(chat.toggle, "buildHTML")(),
        findUpvalue(findUpvalue(chat.toggle, "handleSend"), "buildSystemMessages")()[1].content
end

local function renderChatError(upstreamError)
    local callback
    local scripts = {}
    local _, chat = loadSandbox("extensions/les/ai/chat.lua", {
        ["ai.openai"] = {
            chat = function(_, completion) callback = completion end,
        },
        ["util.windowframe"] = {},
        ["util.utf8text"] = require("util.utf8text"),
    })
    local handleSend = findUpvalue(chat.toggle, "handleSend")
    setUpvalue(handleSend, "_webview", {
        evaluateJavaScript = function(_, script) scripts[#scripts + 1] = script end,
    })

    handleSend("Test question")
    callback(nil, upstreamError)
    return scripts[#scripts]
end

local function renderProjectNotes(projectName)
    local environment = loadSandbox("extensions/les/tracking/projectnotes.lua", {
        ["util.storagekey"] = {},
        ["util.noteid"] = {},
        ["util.windowframe"] = {},
        ["util.utf8text"] = require("util.utf8text"),
    })
    local builder = findUpvalue(environment.openProjectNotes, "buildNotesHTML")
    return builder(projectName or "Client_mix_v2", {
        { id = "note-stable-id", timestamp = 1700000000, body = "Draft" },
    })
end

local function renderCheatsheet()
    local _, cheatsheet = loadSandbox("extensions/les/ui/cheatsheet.lua", {
        ["util.windowframe"] = {},
    })
    return findUpvalue(cheatsheet.toggle, "buildHTML")()
end

local function renderTrackNotes(projectName)
    local environment = loadSandbox("extensions/les/tracking/tracknotes.lua", {
        ["util.storagekey"] = {},
        ["util.noteid"] = {},
        ["util.windowframe"] = {},
        ["util.utf8text"] = require("util.utf8text"),
    })
    local builder = findUpvalue(environment.openTrackNotes, "buildHTML")
    return builder(projectName or "Client_mix_v2", "Bass", {
        Bass = { { id = "track-note-stable-id", ts = 1700000000, body = "Draft" } },
    })
end

local function renderSettings()
    local environment = setmetatable({
        L = function(key) return _G.L(key) end,
        BundleResourcePath = "extensions/les",
        ConfigFile = "settings.ini",
        GetDataPath = function(path) return "/tmp/" .. tostring(path) end,
        fileToTable = function() end,
        settingsManager = {
            autoadd = { value = "1" },
            openaikey = { value = "sk-secret-must-not-appear" },
            openaimodel = { value = "gpt-4o-mini" },
        },
        hs = {
            json = {
                encode = function(value) return dkjson.encode(value) end,
            },
        },
        require = function(name)
            if name == "util.windowframe" then return {} end
            return require(name)
        end,
    }, { __index = _G })
    environment._G = _G
    assert(loadfile("extensions/les/menus/settingsgui.lua", "t", environment))()
    return findUpvalue(environment.openSettingsGUI, "buildSettingsHTML")()
end

local function renderMenuConfig()
    local environment = setmetatable({
        L = function(key) return _G.L(key) end,
        hs = {
            json = {
                encode = function(value) return dkjson.encode(value) end,
            },
        },
        require = function(name)
            if name == "util.windowframe" then return {} end
            return require(name)
        end,
    }, { __index = _G })
    environment._G = _G
    assert(loadfile("extensions/les/menus/menuconfiggui.lua", "t", environment))()
    local builder = findUpvalue(environment.openMenuConfigGUI, "buildMenuConfigHTML")
    return builder({
        comments = {},
        categories = {{ name = "Effects", plugins = {} }},
        nocategory = {},
    }, {{ name = "Delay", category = "Audio Effect", format = "VST3" }})
end

local function placeholders(value)
    local result = {}
    for placeholder in value:gmatch("%%[%d%.%-]*[sd]") do result[#result + 1] = placeholder end
    table.sort(result)
    return result
end

local function containsJapanese(value)
    for _, codepoint in utf8.codes(value) do
        if (codepoint >= 0x3040 and codepoint <= 0x30ff)
            or (codepoint >= 0x3400 and codepoint <= 0x9fff)
        then
            return true
        end
    end
    return false
end

describe("LES localization", function()
    before_each(function()
        package.loaded["util.locale"] = nil
        locale = require("util.locale")
    end)

    after_each(function()
        package.loaded["util.locale"] = originalLocaleModule
        rawset(_G, "L", originalL)
        rawset(_G, "uiLanguage", originalUiLanguage)
    end)

    it("keeps the English and Japanese locale key sets identical", function()
        assert.is_table(locale)
        local english = locale.stringsFor("en")
        local japanese = locale.stringsFor("ja")

        for key, value in pairs(english) do
            assert.is_string(value)
            assert.is_not.equal("", value)
            assert.is_not_nil(japanese[key], "missing Japanese locale key: " .. key)
            assert.same(placeholders(value), placeholders(japanese[key]),
                "format placeholders differ for locale key: " .. key)
        end
        for key in pairs(japanese) do
            assert.is_not_nil(english[key], "missing English locale key: " .. key)
        end
    end)

    it("renders chat HTML, window copy, and system prompts in both languages", function()
        rawset(_G, "uiLanguage", "ja")
        local japaneseHTML, japanesePrompt = renderChat()
        assert.matches('<html lang="ja">', japaneseHTML, 1, true)
        assert.matches("AI アシスタント", japaneseHTML, 1, true)
        assert.matches("日本語で簡潔に回答", japanesePrompt, 1, true)

        rawset(_G, "uiLanguage", "en")
        local englishHTML, englishPrompt = renderChat()
        assert.matches('<html lang="en">', englishHTML, 1, true)
        assert.matches("AI Assistant", englishHTML, 1, true)
        assert.matches("Enter a question", englishHTML, 1, true)
        assert.matches("Respond concisely in English", englishPrompt, 1, true)
    end)

    it("renders upstream chat failures in the selected UI language", function()
        rawset(_G, "uiLanguage", "en")
        local upstreamError = "通信エラーが発生しました"
        local script = renderChatError(upstreamError)

        assert.matches("Could not get a response from AI", script, 1, true)
        assert.is_nil(script:find(upstreamError, 1, true))
    end)

    it("renders project notes without changing stable note identifiers", function()
        rawset(_G, "uiLanguage", "ja")
        local japaneseHTML = renderProjectNotes()
        assert.matches('<html lang="ja">', japaneseHTML, 1, true)
        assert.matches("プロジェクトメモ", japaneseHTML, 1, true)
        assert.matches('data%-id="note%-stable%-id"', japaneseHTML)

        rawset(_G, "uiLanguage", "en")
        local englishHTML = renderProjectNotes()
        assert.matches('<html lang="en">', englishHTML, 1, true)
        assert.matches("Project Notes", englishHTML, 1, true)
        assert.matches("Enter a note", englishHTML, 1, true)
        assert.matches('data%-id="note%-stable%-id"', englishHTML)
        assert.matches('aria%-label="[^"]+ — Delete this note"', englishHTML)
        assert.matches("confirm%(when%+' — Delete this note%?'%)", englishHTML)
    end)

    it("renders the shortcut reference in both languages", function()
        rawset(_G, "uiLanguage", "ja")
        local japaneseHTML = renderCheatsheet()
        assert.matches('<html lang="ja">', japaneseHTML, 1, true)
        assert.matches("ショートカット", japaneseHTML, 1, true)

        rawset(_G, "uiLanguage", "en")
        local englishHTML = renderCheatsheet()
        assert.matches('<html lang="en">', englishHTML, 1, true)
        assert.matches("Shortcuts", englishHTML, 1, true)
        assert.matches("Close the frontmost plugin window", englishHTML, 1, true)
    end)

    it("renders track notes and the menu-bar entry in both languages", function()
        rawset(_G, "uiLanguage", "ja")
        local japaneseHTML = renderTrackNotes()
        assert.matches('<html lang="ja">', japaneseHTML, 1, true)
        assert.matches("トラックメモ", japaneseHTML, 1, true)
        assert.matches('"id":"track%-note%-stable%-id"', japaneseHTML)

        rawset(_G, "uiLanguage", "en")
        local englishHTML = renderTrackNotes()
        assert.matches('<html lang="en">', englishHTML, 1, true)
        assert.matches("Track Notes", englishHTML, 1, true)
        assert.matches("Enter a track name", englishHTML, 1, true)
        assert.matches('"id":"track%-note%-stable%-id"', englishHTML)
        assert.matches("fmt%(n%.ts%)[^\n]+ — Delete this note", englishHTML)
        assert.matches("confirm%(when%+' — Delete this note%?'%)", englishHTML)

        local environment = loadSandbox("extensions/les/menus/bar.lua", {})
        local menu = environment.getMenuBar(false, false)
        local foundTrackNotes = false
        for _, item in ipairs(menu) do
            if item.title == "Track Notes..." then foundTrackNotes = true end
        end
        assert.is_true(foundTrackNotes)
    end)

    it("preserves long project names and exposes wrapping constraints in both notes views", function()
        local projectName = string.rep("Very_Long_Project_Name_", 12)
        local spacedName = projectName:gsub("_", " ")
        local projectHTML = renderProjectNotes(projectName)
        local trackHTML = renderTrackNotes(projectName)

        assert.is_truthy(projectHTML:find(projectName, 1, true))
        assert.is_nil(projectHTML:find(spacedName, 1, true))
        assert.matches("%.project%-heading%s*{[^}]*min%-width:%s*0", projectHTML)
        assert.matches("%.project%-name%s*{[^}]*overflow%-wrap:%s*anywhere", projectHTML)

        assert.is_truthy(trackHTML:find(projectName, 1, true))
        assert.is_nil(trackHTML:find(spacedName, 1, true))
        assert.matches("%.hdr%-top>div%s*{[^}]*min%-width:%s*0", trackHTML)
        assert.matches("%.hdr%-proj%s*{[^}]*overflow%-wrap:%s*anywhere", trackHTML)
    end)

    it("renders the settings editor in Japanese and English without exposing the API key", function()
        rawset(_G, "uiLanguage", "ja")
        local japaneseHTML = renderSettings()
        assert.matches("<html lang='ja'>", japaneseHTML, 1, true)
        assert.matches("LES 設定", japaneseHTML, 1, true)
        assert.matches("プラグイン自動追加", japaneseHTML, 1, true)
        assert.matches("保存して反映", japaneseHTML, 1, true)
        assert.is_nil(japaneseHTML:find("Feature Toggles", 1, true))
        assert.is_nil(japaneseHTML:find("sk-secret-must-not-appear", 1, true))

        rawset(_G, "uiLanguage", "en")
        local englishHTML = renderSettings()
        assert.matches("<html lang='en'>", englishHTML, 1, true)
        assert.matches("LES Settings", englishHTML, 1, true)
        assert.matches("Automatically add the selected plugin", englishHTML, 1, true)
        assert.matches("Save and Apply", englishHTML, 1, true)
        assert.matches("Saved %(enter a new value only to replace it%)", englishHTML)
        assert.is_false(containsJapanese(englishHTML))
        assert.is_nil(englishHTML:find("sk-secret-must-not-appear", 1, true))
    end)

    it("renders the menu editor and picker in Japanese and English without opposite-language copy", function()
        rawset(_G, "uiLanguage", "ja")
        local japaneseHTML = renderMenuConfig()
        assert.matches("<html lang='ja'>", japaneseHTML, 1, true)
        assert.matches("プラグインメニュー設定", japaneseHTML, 1, true)
        assert.matches("カテゴリ追加", japaneseHTML, 1, true)
        assert.matches("未保存の変更があります", japaneseHTML, 1, true)
        assert.matches("プラグイン名で検索", japaneseHTML, 1, true)
        assert.is_nil(japaneseHTML:find("Plugin Menu Settings", 1, true))

        rawset(_G, "uiLanguage", "en")
        local englishHTML = renderMenuConfig()
        assert.matches("<html lang='en'>", englishHTML, 1, true)
        assert.matches("Plugin Menu Settings", englishHTML, 1, true)
        assert.matches("Add Category", englishHTML, 1, true)
        assert.matches("Discard unsaved changes and close", englishHTML, 1, true)
        assert.matches("Search by plugin name", englishHTML, 1, true)
        assert.is_false(containsJapanese(englishHTML))
    end)

    it("stores locale keys rather than rendered labels in settings definitions", function()
        local file = assert(io.open("extensions/les/menus/settingsgui.lua", "r"))
        local source = assert(file:read("*a"))
        assert(file:close())

        assert.is_truthy(source:find('labelKey = "settings_toggle_autoadd_label"', 1, true))
        assert.is_truthy(source:find('descKey = "settings_toggle_autoadd_desc"', 1, true))
        assert.is_truthy(source:find('placeholderKey = "settings_ai_key_placeholder"', 1, true))
        assert.is_nil(source:find('label = "プラグイン自動追加"', 1, true))
    end)

    it("defines and uses the selected response language for every AI system prompt", function()
        for _, key in ipairs({
            "chat_system_prompt",
            "recommend_system_prompt",
            "namegen_system_prompt",
            "projectnotes_summary_system_prompt",
        }) do
            assert.matches("English", locale.translate(key, "en"), 1, true)
            assert.matches("日本語", locale.translate(key, "ja"), 1, true)
        end

        local projectSource = assert(io.open("extensions/les/tracking/projectnotes.lua", "r"))
        local source = assert(projectSource:read("*a"))
        assert(projectSource:close())
        assert.is_truthy(source:find('L("projectnotes_summary_system_prompt")', 1, true))
        assert.is_truthy(source:find('L("projectnotes_summary_user_prompt")', 1, true))
    end)

    it("uses localized window titles for every webview", function()
        local expected = {
            ["extensions/les/ai/chat.lua"] = "chat_title",
            ["extensions/les/ai/recommend.lua"] = "recommend_title",
            ["extensions/les/tracking/projectnotes.lua"] = "projectnotes_title",
            ["extensions/les/tracking/tracknotes.lua"] = "tracknotes_title",
            ["extensions/les/ui/cheatsheet.lua"] = "cheatsheet_window_title",
            ["extensions/les/menus/settingsgui.lua"] = "settings_title",
            ["extensions/les/menus/menuconfiggui.lua"] = "menuconfig_window_title",
        }
        for path, key in pairs(expected) do
            local file = assert(io.open(path, "r"))
            local source = assert(file:read("*a"))
            assert(file:close())
            assert.is_truthy(source:find('windowTitle(L("' .. key .. '"))', 1, true), path)
        end
    end)

    it("updates the menubar tooltip for every localized HUD state", function()
        local state = {}
        local menubar = {}
        function menubar.setIcon() end
        function menubar.setTitle() end
        function menubar.setTooltip(_, value) state.tooltip = value end

        local environment = setmetatable({
            _G = false,
            L = function(key) return _G.L(key) end,
            hs = {},
            LESmenubar = menubar,
            applyLesMainMenubarAppearance = function(item) item:setTooltip("Default app tooltip") end,
        }, { __index = _G })
        environment._G = environment
        assert(loadfile("extensions/les/ui/hud.lua", "t", environment))()

        rawset(_G, "uiLanguage", "en")
        environment.updateMenuBarState("active")
        assert.are.equal("LES Active", state.tooltip)
        environment.updateMenuBarState("paused")
        assert.are.equal("LES Paused", state.tooltip)
        environment.updateMenuBarState("inactive")
        assert.are.equal("LES Inactive", state.tooltip)
    end)
end)

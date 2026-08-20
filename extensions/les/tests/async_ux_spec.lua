--  SPDX-License-Identifier: MIT

local function readSource(path)
    local file = assert(io.open(path, "rb"))
    local source = assert(file:read("*a"))
    assert(file:close())
    return source
end

describe("asynchronous UI state", function()
    it("does not deliver an old AI reply into a reopened chat", function()
        local source = readSource("extensions/les/ai/chat.lua")

        assert.is_truthy(source:find("requestWebview", 1, true))
        assert.is_truthy(source:find("requestGeneration", 1, true))
        assert.is_truthy(source:find("_webview ~= requestWebview", 1, true))
        assert.is_truthy(source:find("cancelPending", 1, true))
    end)

    it("keeps an AI summary attached to the project that requested it", function()
        local source = readSource("extensions/les/tracking/projectnotes.lua")

        assert.is_truthy(source:find("projectAtRequest", 1, true))
        assert.is_truthy(source:find("projectnotes.addNote(projectAtRequest", 1, true))
        assert.is_truthy(source:find("summaryResult", 1, true))
    end)

    it("keeps typed notes until persistence succeeds", function()
        local project = readSource("extensions/les/tracking/projectnotes.lua")
        local track = readSource("extensions/les/tracking/tracknotes.lua")

        assert.is_truthy(project:find("noteOperationResult", 1, true))
        assert.is_truthy(track:find("noteOperationResult", 1, true))
        assert.is_truthy(track:find("if saved then", 1, true))
    end)

    it("clears pending deletion state when persistence fails", function()
        local project = readSource("extensions/les/tracking/projectnotes.lua")
        local track = readSource("extensions/les/tracking/tracknotes.lua")

        for _, source in ipairs({project, track}) do
            assert.is_truthy(source:find("function deleteOperationResult", 1, true))
            assert.is_truthy(source:find("deleteOperationResult(false", 1, true))
        end
    end)

    it("fully rebuilds track notes when the active project changes", function()
        local source = readSource("extensions/les/tracking/tracknotes.lua")

        assert.is_truthy(source:find("refreshView", 1, true))
        assert.is_nil(source:find('(projectName or ""):gsub("_", " ")', 1, true))
    end)

    it("announces the selected track after keyboard navigation", function()
        local source = readSource("extensions/les/tracking/tracknotes.lua")

        assert.is_truthy(source:find("tracknotes_switched_status", 1, true))
        assert.is_truthy(source:find("announceTrack(message)", 1, true))
    end)

    it("wraps previous and next navigation from an unsaved detected track", function()
        local source = readSource("extensions/les/tracking/tracknotes.lua")

        assert.is_truthy(source:find("if(idx<0){idx=dir<0?0:-1;}", 1, true))
    end)
end)

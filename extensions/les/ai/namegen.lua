--  SPDX-License-Identifier: MIT
--  AI Name Generator — suggests project/track names

local openai = require("ai.openai")

local namegen = {}

---@type hs.chooser|nil
local _chooser = nil
local _requestGeneration = 0
local _requestPending = false

--- Gather context for name generation.
---@return string
local function gatherContext()
    local parts = {}

    -- Current project name
    if _G.trackname and _G.trackname ~= "" then
        parts[#parts + 1] = string.format(L("namegen_context_project"), _G.trackname)
    end

    -- Project notes (last 5)
    local ok, pn = pcall(require, "tracking.projectnotes")
    if ok and pn and _G.trackname then
        local notes = pn.load(_G.trackname)
        if #notes > 0 then
            local recent = {}
            local start = math.max(1, #notes - 4)
            for i = start, #notes do
                recent[#recent + 1] = "- " .. notes[i].body
            end
            parts[#parts + 1] = string.format(L("namegen_context_notes"), table.concat(recent, "\n"))
        end
    end

    -- Frequently used plugins (top 5)
    local ok2, ps = pcall(require, "tracking.pluginstats")
    if ok2 and ps then
        local stats = ps.getAll()
        local sorted = {}
        for name, s in pairs(stats) do
            sorted[#sorted + 1] = { name = name, count = s.use_count or 0 }
        end
        table.sort(sorted, function(a, b) return a.count > b.count end)
        if #sorted > 0 then
            local top = {}
            for i = 1, math.min(5, #sorted) do
                top[#top + 1] = sorted[i].name
            end
            parts[#parts + 1] = string.format(L("namegen_context_plugins"), table.concat(top, ", "))
        end
    end

    if #parts == 0 then
        return L("namegen_context_empty")
    end
    return table.concat(parts, "\n\n")
end

--- Open the name generator.
--- Shows a chooser with AI-generated names.
---@param userHint string|nil  Optional description/genre hint
function namegen.open(userHint)
    if not openai.isConfigured() then
        HSMakeAlert(programName,
            L("namegen_config_required"),
            true, "warning")
        return
    end

    if _chooser and _requestPending then
        _chooser:show()
        return
    end

    -- Show a temporary chooser with loading state. Clear the module reference
    -- before deleting the previous chooser because delete() can synchronously
    -- invoke its cancellation callback.
    local previousChooser = _chooser
    _chooser = nil
    _requestGeneration = _requestGeneration + 1
    local requestGeneration = _requestGeneration
    if previousChooser then previousChooser:delete() end

    local requestChooser
    requestChooser = hs.chooser.new(function(choice)
        if _chooser ~= requestChooser then return end
        if not choice then
            _chooser = nil
            _requestPending = false
            _requestGeneration = _requestGeneration + 1
            return
        end
        if choice.state == true then return end
        _chooser = nil
        _requestPending = false
        _requestGeneration = _requestGeneration + 1
        -- Copy selected name to clipboard
        hs.pasteboard.setContents(choice.text)
        HSMakeAlert(programName,
            string.format(L("namegen_copied"), choice.text),
            false, "informational")
    end)
    _chooser = requestChooser
    _requestPending = true
    requestChooser:placeholderText(L("namegen_loading_placeholder"))
    requestChooser:choices({{ text = L("namegen_loading"), subText = L("namegen_wait"), state = true }})
    requestChooser:show()

    local ctx = gatherContext()
    local prompt = ctx .. "\n\n" .. L("namegen_user_prompt")

    if userHint and userHint ~= "" then
        prompt = prompt .. "\n" .. string.format(L("namegen_user_hint"), userHint)
    end

    local messages = {
        { role = "system", content = L("namegen_system_prompt") },
        { role = "user",   content = prompt },
    }

    openai.chat(messages, function(reply, err)
        if _chooser ~= requestChooser or _requestGeneration ~= requestGeneration then
            print("[LES][ai.namegen] reply dropped: request is no longer current")
            return
        end
        _requestPending = false
        -- Always replace the loading row so a nil/empty reply can never
        -- strand the chooser on the loading state.
        if err or type(reply) ~= "string" or reply == "" then
            local errMsg = err and L("ai_request_failed") or L("ai_empty_response")
            print("[LES][ai.namegen] reply error: " .. tostring(err or "empty response"))
            requestChooser:choices({{ text = L("namegen_error"), subText = errMsg, state = true }})
            requestChooser:refreshChoicesCallback()
            return
        end

        local choices = {}
        for line in reply:gmatch("[^\r\n]+") do
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed and trimmed ~= "" then
                -- Split "Name (description)" pattern
                local name, desc = trimmed:match("^(.-)%s*[（%(](.+)[）%)]%s*$")
                if name and name ~= "" then
                    choices[#choices + 1] = { text = name, subText = desc }
                else
                    choices[#choices + 1] = { text = trimmed, subText = "" }
                end
            end
        end

        if #choices == 0 then
            choices = {{ text = L("namegen_empty_result"), subText = L("namegen_retry"), state = true }}
        end

        requestChooser:placeholderText(L("namegen_choose"))
        requestChooser:choices(choices)
        requestChooser:refreshChoicesCallback()
    end)
end

return namegen

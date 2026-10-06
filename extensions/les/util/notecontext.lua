-- SPDX-License-Identifier: MIT
-- Confirm document replacement without applying stale asynchronous decisions.

local notecontext = {}
local requests = setmetatable({}, { __mode = "k" })

function notecontext.cancel(webview)
    local updated = setmetatable({}, { __mode = "k" })
    for view, token in pairs(requests) do updated[view] = token end
    updated[webview] = {}
    requests = updated
    return requests[webview]
end

---@param webview hs.webview
---@param isCurrent function
---@param accepted function
---@param failed function
function notecontext.confirm(webview, isCurrent, accepted, failed)
    local token = notecontext.cancel(webview)
    local function current() return requests[webview] == token and isCurrent() end
    local function reportFailure(reason)
        if not current() then return end
        local detail = type(reason) == "table" and (reason.localizedDescription or reason.message or reason.code) or reason
        print("[LES][notecontext] project switch retained current document: " .. tostring(detail))
        failed()
    end
    local ok, bridgeError = pcall(function()
        webview:evaluateJavaScript("confirmContextChange()", function(result, scriptError)
            if not current() then return end
            if scriptError then reportFailure(scriptError) return end
            if result == false then return end -- cancelled or busy
            if result ~= true then reportFailure("missing or invalid confirmation result") return end
            local applied, applyError = pcall(accepted)
            if not applied then reportFailure(applyError) end
        end)
    end)
    if not ok then reportFailure(bridgeError) end
end

return notecontext

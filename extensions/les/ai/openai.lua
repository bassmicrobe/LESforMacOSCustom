--  SPDX-License-Identifier: MIT
--  AI integration: shared OpenAI API client

local openai = {}

local API_URL = "https://api.openai.com/v1/chat/completions"
local ERROR_DETAILS = {
    [400] = "リクエストが受け付けられませんでした。モデルと設定を確認してください。",
    [401] = "認証に失敗しました。設定の API キーを確認してください。",
    [403] = "アクセスが許可されていません。API キーの権限を確認してください。",
    [404] = "指定されたモデルを利用できません。モデルと API キーの権限を確認してください。",
    [429] = "リクエストが集中しています。少し待ってからお試しください。",
}
local QUOTA_CODES = {
    insufficient_quota = true,
    credit_balance_exhausted = true,
    organization_spend_limit_exceeded = true,
    project_spend_limit_exceeded = true,
    organization_usage_limit_exceeded = true,
}

--- Get the configured API key.
---@return string
function openai.getKey()
    if settingsManager and settingsManager["openaikey"]
       and settingsManager["openaikey"]["value"] then
        return tostring(settingsManager["openaikey"]["value"])
    end
    return ""
end

--- Get the configured model name.
---@return string
function openai.getModel()
    if settingsManager and settingsManager["openaimodel"]
       and settingsManager["openaimodel"]["value"]
       and settingsManager["openaimodel"]["value"] ~= "" then
        return tostring(settingsManager["openaimodel"]["value"])
    end
    return "gpt-4o-mini"
end

--- Check whether an API key has been configured.
---@return boolean
function openai.isConfigured()
    local key = (openai.getKey() or ""):gsub("^%s*(.-)%s*$", "%1")
    return key ~= "" and not key:find("未設定", 1, true)
end

--- Return only local, allowlisted diagnostics. Upstream messages can echo API
--- keys or request content; callers log these errors, so never forward them.
---@param status any
---@param body string|nil
---@return string
local function requestError(status, body)
    if type(status) ~= "number" or status <= 0 then
        return "ネットワークエラー: OpenAI に接続できませんでした。インターネット接続を確認してください。"
    end

    local detail = ERROR_DETAILS[status]
    if status == 429 then
        local ok, decoded = pcall(hs.json.decode, body or "")
        local apiError = ok and type(decoded) == "table" and decoded.error
        if type(apiError) == "table"
            and (QUOTA_CODES[apiError.code] or apiError.type == "insufficient_quota") then
            detail = "API の利用上限に達しました。OpenAI の利用上限と請求設定を確認してください。"
        end
    elseif status >= 500 then
        detail = "OpenAI で一時的なエラーが発生しました。少し待ってからお試しください。"
    end
    local summary = "API エラー (HTTP " .. tostring(status) .. ")"
    return detail and (summary .. ": " .. detail) or summary
end

--- Send a chat completion request (async).
---@param messages table  Array of {role, content} message objects
---@param callback fun(reply: string|nil, err: string|nil)
function openai.chat(messages, callback)
    if not openai.isConfigured() then
        callback(nil, "APIキーが設定されていません。\n設定 → AI設定 で OpenAI API キーを入力してください。")
        return
    end

    local encoded, payload = pcall(hs.json.encode, {
        model       = openai.getModel(),
        messages    = messages,
        temperature = 0.7,
    })
    if not encoded or type(payload) ~= "string" then
        callback(nil, "AI へのリクエストを作成できませんでした。もう一度お試しください。")
        return
    end

    local headers = {
        ["Content-Type"]  = "application/json",
        ["Authorization"] = "Bearer " .. openai.getKey(),
    }

    local started = pcall(hs.http.asyncPost, API_URL, payload, headers, function(status, body, _)
        if status ~= 200 then
            callback(nil, requestError(status, body))
            return
        end

        local ok, decoded = pcall(hs.json.decode, body)
        local choices = ok and type(decoded) == "table" and decoded.choices
        local choice = type(choices) == "table" and choices[1]
        local msg = type(choice) == "table" and choice.message
        local content = type(msg) == "table" and msg.content
        if type(content) == "string" and content ~= "" then
            callback(content, nil)
        else
            callback(nil, "空の応答が返されました")
        end
    end)
    if not started then
        callback(nil, "AI への接続を開始できませんでした。接続と設定を確認してください。")
    end
end

return openai

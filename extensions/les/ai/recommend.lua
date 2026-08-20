--  SPDX-License-Identifier: MIT
--  AI Plugin Recommendations — suggests plugins based on usage stats

local openai = require("ai.openai")
local pluginStats = require("tracking.pluginstats")
local windowframe = require("util.windowframe")
local utf8text = require("util.utf8text")

local recommend = {}

---@type hs.webview|nil
local _webview = nil
---@type hs.webview.usercontent|nil
local _uc = nil
local _requestGeneration = 0
local _requestPending = false
local MAX_EXTRA_LENGTH = 4000

--- Escape for safe JS string embedding.
---@param s string
---@return string
local function jsEscape(s)
    return s:gsub("\\", "\\\\")
            :gsub("'", "\\'")
            :gsub("\n", "\\n")
            :gsub("\r", "\\r")
            :gsub("<", "\\x3c")
            :gsub(">", "\\x3e")
            :gsub("\u{2028}", "\\u2028")
            :gsub("\u{2029}", "\\u2029")
end

local function htmlEscape(s)
    return tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
end

local function replaceTokens(template, values)
    return (template:gsub("__([A-Z0-9_]+)__", function(key)
        return values[key] or ""
    end))
end

--- Build usage summary text for the AI prompt.
---@return string
local function buildUsageSummary()
    local stats = pluginStats.getAll()
    local entries = {}
    for name, s in pairs(stats) do
        entries[#entries + 1] = {
            name  = name,
            count = s.use_count or 0,
            fav   = s.favorited == true,
        }
    end
    table.sort(entries, function(a, b) return a.count > b.count end)

    local lines = {}
    local limit = math.min(#entries, 30)
    for i = 1, limit do
        local e = entries[i]
        local fav = e.fav and " ★" or ""
        lines[#lines + 1] = "- " .. e.name .. " (" .. string.format(L("recommend_usage_count"), e.count, fav) .. ")"
    end

    if #lines == 0 then
        return L("recommend_no_history")
    end
    return L("recommend_usage_header") .. "\n" .. table.concat(lines, "\n")
end

--- Build HTML for the recommendation panel.
---@return string
local function buildHTML()
    local template = [[<!DOCTYPE html><html lang="__LANG__"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { color-scheme: dark; height: 100%; overflow: hidden; }
body {
    background: #1c1c1e; color: #e5e5ea;
    font-family: -apple-system, "Helvetica Neue", sans-serif;
    font-size: 13px; display: flex; flex-direction: column;
}
.header {
    padding: 14px 16px 12px; border-bottom: 1px solid #2c2c2e; flex-shrink: 0;
}
.header h1 { font-size: 15px; font-weight: 600; color: #fff; }
.header p { font-size: 11px; color: #a1a1a6; margin-top: 3px; }
.content { flex: 1; overflow-y: auto; padding: 16px; }
.loading { color: #a1a1a6; text-align: center; margin-top: 60px; line-height: 1.8; }
.result { line-height: 1.7; word-break: break-word; }
.result h2,.result h3 { font-weight: 600; margin: 10px 0 4px; color: #d0d0d5; }
.result h2 { font-size: 14px; } .result h3 { font-size: 13px; }
.result ul,.result ol { padding-left: 20px; margin: 6px 0; }
.result li { margin: 3px 0; }
.result p { margin: 6px 0; } .result p:first-child { margin-top: 0; }
.result hr { border: none; border-top: 1px solid #3a3a3c; margin: 12px 0; }
.error { color: #ff6b6b; text-align: center; margin-top: 60px; }
.input-area {
    padding: 10px 16px 14px; border-top: 1px solid #2c2c2e;
    flex-shrink: 0; display: flex; gap: 8px; align-items: center;
}
textarea {
    flex: 1; background: #2c2c2e; color: #e5e5ea;
    border: 1px solid #3a3a3c; border-radius: 8px;
    padding: 8px 10px; font-family: inherit; font-size: 13px;
    resize: none; height: 36px; outline: none;
}
textarea:focus { border-color: #0a84ff; }
textarea:focus-visible, button:focus-visible { outline: 2px solid #64d2ff; outline-offset: 2px; }
textarea::placeholder { color: #a1a1a6; }
button.send {
    background: #0a84ff; color: #fff; border: none; border-radius: 8px;
    padding: 0 14px; height: 36px; font-size: 13px; font-weight: 600;
    cursor: pointer; flex-shrink: 0;
}
button.send:hover { background: #409cff; }
button.send:disabled { background: #3a3a3c; color: #a1a1a6; cursor: wait; }
</style></head><body>
<div class="header">
  <h1>🔌 __TITLE__</h1>
  <p>__SUBTITLE__</p>
</div>
<div class="content" id="content" role="status" aria-live="polite" aria-busy="true">
  <div class="loading">__LOADING_STATS__</div>
</div>
<div class="input-area">
  <textarea id="inp" placeholder="__EXTRA_PLACEHOLDER__" rows="1"
    maxlength="__MAX_EXTRA_CODE_UNITS__" aria-label="__EXTRA_LABEL__"
    onkeydown="if(event.key==='Enter'&&event.metaKey){event.preventDefault();ask();}"></textarea>
  <button id="send" type="button" class="send" onclick="ask()">__AGAIN_HTML__</button>
</div>
<script>
var requestPending = false;
var pendingExtra = null;
var maxExtraLength = __MAX_EXTRA_LENGTH__;
function charLength(value) { return Array.from(value).length; }
function escHtml(s){return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
function mdToHtml(md){
    var stash=[];
    function hide(h){var k='\x01'+stash.length+'\x01';stash.push(h);return k;}
    md=md.replace(/```[\w]*\n?([\s\S]*?)```/g,function(_,c){
        return hide('<pre><code>'+escHtml(c.replace(/\n$/,''))+'</code></pre>');
    });
    md=md.replace(/`([^`\n]+)`/g,function(_,c){return hide('<code>'+escHtml(c)+'</code>');});
    md=escHtml(md);
    md=md.replace(/^### (.+)$/gm,'<h3>$1</h3>');
    md=md.replace(/^## (.+)$/gm,'<h2>$1</h2>');
    md=md.replace(/^# (.+)$/gm,'<h1>$1</h1>');
    md=md.replace(/\*\*\*(.+?)\*\*\*/g,'<strong><em>$1</em></strong>');
    md=md.replace(/\*\*(.+?)\*\*/g,'<strong>$1</strong>');
    md=md.replace(/\*(.+?)\*/g,'<em>$1</em>');
    md=md.replace(/^---+$/gm,'<hr>');
    md=md.replace(/((?:^[-*] .+(?:\n|$))+)/gm,function(b){
        return '<ul>'+b.replace(/^[-*] (.+)$/gm,'<li>$1</li>')+'</ul>';
    });
    md=md.replace(/((?:^\d+\. .+(?:\n|$))+)/gm,function(b){
        return '<ol>'+b.replace(/^\d+\. (.+)$/gm,'<li>$1</li>')+'</ol>';
    });
    var out=md.split(/\n\n+/).map(function(p){
        p=p.trim();if(!p)return '';
        if(/^<(?:h[1-6]|ul|ol|hr|pre)/.test(p)||/^\x01/.test(p))return p;
        return '<p>'+p.replace(/\n/g,'<br>')+'</p>';
    }).join('');
    return out.replace(/\x01(\d+)\x01/g,function(_,i){return stash[+i];});
}
function setContent(html) {
    document.getElementById('content').innerHTML = html;
}
function setMarkdown(text) {
    setContent('<div class="result">' + mdToHtml(text) + '</div>');
}
function setError(msg) {
    // Render error text via textContent so an API/proxy-supplied message can
    // never inject markup into innerHTML (the error string is externally controlled).
    var c = document.getElementById('content');
    c.innerHTML = '';
    var d = document.createElement('div');
    d.className = 'error';
    d.textContent = msg;
    c.appendChild(d);
}
function setRequestControls(pending) {
    requestPending = pending;
    var input = document.getElementById('inp');
    var button = document.getElementById('send');
    input.disabled = pending;
    button.disabled = pending;
    button.textContent = pending ? '__PENDING_JS__' : '__AGAIN_JS__';
    document.getElementById('content').setAttribute('aria-busy', pending ? 'true' : 'false');
}
function recommendRequestStarted() {
    setRequestControls(true);
    setContent('<div class="loading">__LOADING_AI_JS__</div>');
}
function recommendRequestResult(ok) {
    var input = document.getElementById('inp');
    if (ok) {
        if (pendingExtra !== null && input.value.trim() === pendingExtra) input.value = '';
    }
    pendingExtra = null;
    setRequestControls(false);
    input.focus();
}
function ask() {
    if (requestPending) return;
    var extra = document.getElementById('inp').value.trim();
    if (charLength(extra) > maxExtraLength) {
        setError('__INPUT_TOO_LONG_JS__');
        recommendRequestResult(false);
        return;
    }
    pendingExtra = extra;
    recommendRequestStarted();
    window.webkit.messageHandlers.airecommend.postMessage({action:'ask', extra: extra});
}
</script>
</body></html>]]
    return replaceTokens(template, {
        LANG = htmlEscape(L("locale_code")),
        TITLE = htmlEscape(L("recommend_title")),
        SUBTITLE = htmlEscape(L("recommend_subtitle")),
        LOADING_STATS = htmlEscape(L("recommend_loading_stats")),
        EXTRA_PLACEHOLDER = htmlEscape(L("recommend_extra_placeholder")),
        EXTRA_LABEL = htmlEscape(L("recommend_extra_label")),
        AGAIN_HTML = htmlEscape(L("recommend_again")),
        AGAIN_JS = jsEscape(L("recommend_again")),
        PENDING_JS = jsEscape(L("recommend_pending")),
        LOADING_AI_JS = jsEscape(L("recommend_loading_ai")),
        INPUT_TOO_LONG_JS = jsEscape(string.format(L("recommend_input_too_long"), MAX_EXTRA_LENGTH)),
        MAX_EXTRA_LENGTH = tostring(MAX_EXTRA_LENGTH),
        MAX_EXTRA_CODE_UNITS = tostring(MAX_EXTRA_LENGTH * 2),
    })
end

--- Request recommendations from OpenAI.
---@param extra string|nil  Additional user context
local function fetchRecommendations(extra)
    if _requestPending or not _webview then return false end

    local requestWebview = _webview
    _requestGeneration = _requestGeneration + 1
    local requestGeneration = _requestGeneration
    _requestPending = true
    requestWebview:evaluateJavaScript("recommendRequestStarted();")

    local usage = buildUsageSummary()
    local prompt = usage .. "\n\n" .. L("recommend_user_prompt")

    if extra and extra ~= "" then
        prompt = prompt .. "\n\n" .. string.format(L("recommend_extra_context"), extra)
    end

    local messages = {
        { role = "system", content = L("recommend_system_prompt") },
        { role = "user",   content = prompt },
    }

    openai.chat(messages, function(reply, err)
        if _webview ~= requestWebview or _requestGeneration ~= requestGeneration then
            print("[LES][ai.recommend] reply dropped: request is no longer current")
            return
        end
        _requestPending = false
        -- Always replace the loading spinner with either result or error so the
        -- panel can never be stranded on a nil/empty reply.
        if err or type(reply) ~= "string" or reply == "" then
            local errMsg = err and L("ai_request_failed") or L("ai_empty_response")
            print("[LES][ai.recommend] reply error: " .. tostring(err or "empty response"))
            requestWebview:evaluateJavaScript(
                string.format("setError('%s');recommendRequestResult(false);", jsEscape(errMsg)))
        else
            requestWebview:evaluateJavaScript(
                string.format("setMarkdown('%s');recommendRequestResult(true);", jsEscape(reply)))
        end
    end)
    return true
end

--- Open the plugin recommendation panel.
---@param extra string|nil
function recommend.open(extra)
    if _webview ~= nil then
        _webview:show()
        _webview:bringToFront()
        return
    end

    if not openai.isConfigured() then
        HSMakeAlert(programName,
            L("recommend_config_required"),
            true, "warning")
        return
    end

    _uc = hs.webview.usercontent.new("airecommend")
    _uc:setCallback(function(msg)
        if type(msg) ~= "table" or type(msg.body) ~= "table" then return end
        if msg.body.action == "ask" then
            local extraText = type(msg.body.extra) == "string" and msg.body.extra or ""
            if not utf8text.isWithinLimit(extraText, MAX_EXTRA_LENGTH) then
                local errorMessage = string.format(L("recommend_input_too_long"), MAX_EXTRA_LENGTH)
                if _webview then
                    _webview:evaluateJavaScript(string.format(
                        "setError('%s');recommendRequestResult(false);",
                        jsEscape(errorMessage)))
                end
                return
            end
            fetchRecommendations(extraText)
        end
    end)

    local screen = hs.screen.mainScreen():frame()
    local frame = windowframe.center(screen, 480, 520, 12)

    _webview = hs.webview.new(
        frame,
        { developerExtrasEnabled = false },
        _uc
    )
    if _webview == nil then
        _uc = nil
        return
    end
    _webview:windowStyle({ "titled", "closable", "resizable" })
    _webview:windowTitle(L("recommend_title"))
    _webview:allowTextEntry(true)
    _webview:html(buildHTML())
    _webview:deleteOnClose(true)
    local requestWebview = _webview
    _webview:windowCallback(function(action)
        if action == "closing" and _webview == requestWebview then
            _requestGeneration = _requestGeneration + 1
            _requestPending = false
            _webview = nil
            _uc = nil
        end
    end)
    _webview:show()
    _webview:bringToFront()

    -- Auto-fetch on open
    local initialExtra = type(extra) == "string" and extra or ""
    if not utf8text.isWithinLimit(initialExtra, MAX_EXTRA_LENGTH) then
        local errorMessage = string.format(L("recommend_input_too_long"), MAX_EXTRA_LENGTH)
        _webview:evaluateJavaScript(string.format(
            "setError('%s');recommendRequestResult(false);",
            jsEscape(errorMessage)))
        return
    end
    fetchRecommendations(initialExtra)
end

return recommend

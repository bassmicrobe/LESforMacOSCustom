--  SPDX-License-Identifier: MIT
--  AI Plugin Recommendations — suggests plugins based on usage stats

local openai = require("ai.openai")
local pluginStats = require("tracking.pluginstats")

local recommend = {}

---@type hs.webview|nil
local _webview = nil
---@type hs.webview.usercontent|nil
local _uc = nil

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
        lines[#lines + 1] = string.format("- %s (使用回数: %d%s)", e.name, e.count, fav)
    end

    if #lines == 0 then
        return "プラグインの使用履歴がまだありません。一般的なおすすめを提案してください。"
    end
    return "以下はユーザーのプラグイン使用統計です（使用頻度順、★=お気に入り）:\n" .. table.concat(lines, "\n")
end

--- Build HTML for the recommendation panel.
---@return string
local function buildHTML()
    return [[<!DOCTYPE html><html><head><meta charset="utf-8">
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { height: 100%; overflow: hidden; }
body {
    background: #1c1c1e; color: #e5e5ea;
    font-family: -apple-system, "Helvetica Neue", sans-serif;
    font-size: 13px; display: flex; flex-direction: column;
}
.header {
    padding: 14px 16px 12px; border-bottom: 1px solid #2c2c2e; flex-shrink: 0;
}
.header h1 { font-size: 15px; font-weight: 600; color: #fff; }
.header p { font-size: 11px; color: #636366; margin-top: 3px; }
.content { flex: 1; overflow-y: auto; padding: 16px; }
.loading { color: #636366; text-align: center; margin-top: 60px; line-height: 1.8; }
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
textarea::placeholder { color: #48484a; }
button.send {
    background: #0a84ff; color: #fff; border: none; border-radius: 8px;
    padding: 0 14px; height: 36px; font-size: 13px; font-weight: 600;
    cursor: pointer; flex-shrink: 0;
}
button.send:hover { background: #409cff; }
</style></head><body>
<div class="header">
  <h1>🔌 AI プラグイン提案</h1>
  <p>使用統計をもとに AI がプラグインを提案します</p>
</div>
<div class="content" id="content">
  <div class="loading">プラグイン統計を分析中...</div>
</div>
<div class="input-area">
  <textarea id="inp" placeholder="追加の条件（例: ベースを太くしたい、Lo-Fi系）" rows="1"
    onkeydown="if(event.key==='Enter'&&event.metaKey){event.preventDefault();ask();}"></textarea>
  <button class="send" onclick="ask()">再提案</button>
</div>
<script>
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
function ask() {
    var extra = document.getElementById('inp').value.trim();
    document.getElementById('inp').value = '';
    setContent('<div class="loading">AI が考え中...</div>');
    window.webkit.messageHandlers.airecommend.postMessage({action:'ask', extra: extra});
}
</script>
</body></html>]]
end

--- Request recommendations from OpenAI.
---@param extra string|nil  Additional user context
local function fetchRecommendations(extra)
    local usage = buildUsageSummary()
    local prompt = usage .. "\n\n"
    prompt = prompt .. "上記の使用傾向に基づいて、ユーザーが気に入りそうなプラグイン（VST/AU）を5〜8個提案してください。\n"
    prompt = prompt .. "各プラグインについて: 名前、種類（EQ/コンプ/シンセ等）、おすすめ理由を1行で。\n"
    prompt = prompt .. "無料プラグインも含めてください。"

    if extra and extra ~= "" then
        prompt = prompt .. "\n\nユーザーからの追加リクエスト: " .. extra
    end

    local messages = {
        { role = "system", content = "あなたは音楽制作プラグインの専門家です。Ableton Live ユーザー向けにプラグインを提案します。日本語で回答してください。" },
        { role = "user",   content = prompt },
    }

    openai.chat(messages, function(reply, err)
        if not _webview then
            print("[LES][ai.recommend] reply dropped: webview already closed")
            return
        end
        -- Always replace the loading spinner with either result or error so the
        -- panel can never be stranded on a nil/empty reply.
        if err or type(reply) ~= "string" or reply == "" then
            local errMsg = err or "空の応答が返されました"
            print("[LES][ai.recommend] reply error: " .. tostring(errMsg))
            _webview:evaluateJavaScript(
                string.format("setContent('<div class=\"error\">%s</div>');", jsEscape(errMsg)))
        else
            _webview:evaluateJavaScript(
                string.format("setMarkdown('%s');", jsEscape(reply)))
        end
    end)
end

--- Open the plugin recommendation panel.
---@param extra string|nil
function recommend.open(extra)
    if _webview ~= nil then
        _webview:delete()
        _webview = nil
        _uc = nil
    end

    if not openai.isConfigured() then
        HSMakeAlert(programName,
            "AI プラグイン提案を使うには、設定画面で OpenAI API キーを入力してください。",
            true, "warning")
        return
    end

    _uc = hs.webview.usercontent.new("airecommend")
    _uc:setCallback(function(msg)
        if type(msg) ~= "table" or type(msg.body) ~= "table" then return end
        if msg.body.action == "ask" then
            fetchRecommendations(msg.body.extra)
        end
    end)

    local screen = hs.screen.mainScreen():frame()
    local W, H = 480, 520
    local x = math.floor(screen.x + (screen.w - W) / 2)
    local y = math.floor(screen.y + (screen.h - H) / 2)

    _webview = hs.webview.new(
        { x = x, y = y, w = W, h = H },
        { developerExtrasEnabled = false },
        _uc
    )
    _webview:windowStyle({ "titled", "closable", "resizable" })
    _webview:windowTitle("AI プラグイン提案")
    _webview:allowTextEntry(true)
    _webview:html(buildHTML())
    _webview:windowCallback(function(action)
        if action == "closing" then
            _webview = nil
            _uc = nil
        end
    end)
    _webview:show()
    _webview:bringToFront()

    -- Auto-fetch on open
    fetchRecommendations(extra)
end

return recommend

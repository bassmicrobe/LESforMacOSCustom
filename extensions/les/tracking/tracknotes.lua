--  SPDX-License-Identifier: MIT
--  Track Notes — per-track memos within an Ableton project
--  Data: ~/.les/resources/tracknotes/[project].json
--  {"BASS":[{"ts":1234567890,"body":"..."}], ...}

local tracknotes = {}

---@type hs.webview|nil
local _webview = nil
---@type hs.webview.usercontent|nil
local _uc = nil
---@type string|nil
local _project = nil
---@type string|nil
local _track = nil

local NOTES_DIR = "tracknotes"

-- ── Storage ───────────────────────────────────────────────────────────

local function notesDir()
    return strJoinPaths(ScriptUserResourcesPath, NOTES_DIR)
end

local function notesFilePath(projectName)
    local s = (projectName or "unsaved"):gsub("[%p%c]", "_")
    return strJoinPaths(notesDir(), s .. ".json")
end

--- Load all track notes for a project.
---@param projectName string
---@return table  {trackName = [{ts, body}]}
function tracknotes.loadAll(projectName)
    local path = notesFilePath(projectName)
    local f = io.open(path, "r")
    if not f then return {} end
    local raw = f:read("*a")
    f:close()
    if not raw or raw == "" then return {} end
    local ok, data = pcall(hs.json.decode, raw)
    if ok and type(data) == "table" then return data end
    return {}
end

--- Save all track notes for a project.
---@param projectName string
---@param data table
function tracknotes.saveAll(projectName, data)
    ShellCreateDirectory(notesDir())
    local path = notesFilePath(projectName)
    local ok, json = pcall(hs.json.encode, data, true)
    if not ok or type(json) ~= "string" then return end
    local f = io.open(path, "w")
    if f then f:write(json); f:close() end
end

--- Append a note to a specific track.
---@param projectName string
---@param trackName string
---@param text string
function tracknotes.addNote(projectName, trackName, text)
    if not text or text:match("^%s*$") then return end
    local all = tracknotes.loadAll(projectName)
    if not all[trackName] then all[trackName] = {} end
    all[trackName][#all[trackName] + 1] = {
        ts   = math.floor(hs.timer.secondsSinceEpoch()),
        body = text,
    }
    tracknotes.saveAll(projectName, all)
end

--- Delete a note by timestamp from a specific track.
---@param projectName string
---@param trackName string
---@param ts number
function tracknotes.deleteNote(projectName, trackName, ts)
    if type(ts) ~= "number" then return end
    local all = tracknotes.loadAll(projectName)
    if not all[trackName] then return end
    local kept = {}
    for _, n in ipairs(all[trackName]) do
        if n.ts ~= ts then kept[#kept + 1] = n end
    end
    all[trackName] = kept
    tracknotes.saveAll(projectName, all)
end

-- ── Track name detection ──────────────────────────────────────────────

--- Attempt to read the focused track name from Ableton via AX.
---@return string|nil
local function detectTrackName()
    local liveApp = getLiveHsAppObj()
    if not liveApp then return nil end
    local ok, sysEl = pcall(hs.axuielement.systemWideElement)
    if not ok or not sysEl then return nil end
    local fok, focused = pcall(function()
        return sysEl:attributeValue("AXFocusedUIElement")
    end)
    if not fok or not focused then return nil end
    local el = focused
    for _ = 1, 8 do
        if not el then break end
        local val   = ""
        local title = ""
        pcall(function() val   = el:attributeValue("AXValue") or "" end)
        pcall(function() title = el:attributeValue("AXTitle") or "" end)
        local name = (val ~= "" and val) or (title ~= "" and title) or nil
        if name and #name > 0 and #name < 60
            and not name:match("^/") and not name:match("%.als$")
            and not name:match("^%d+$") then
            return name
        end
        local pok, parent = pcall(function() return el:attributeValue("AXParent") end)
        if not pok or not parent then break end
        el = parent
    end
    return nil
end

-- ── Pure-Lua JSON helpers (avoid hs.json.encode for embedding) ────────

local function jsonStr(s)
    s = tostring(s)
    s = s:gsub("\\","\\\\"):gsub('"','\\"'):gsub("\n","\\n"):gsub("\r","\\r"):gsub("\t","\\t")
    s = s:gsub("[\x00-\x1f]", function(c) return string.format("\\u%04x", c:byte()) end)
    return '"' .. s .. '"'
end

local function notesJson(list)
    local parts = {}
    for _, n in ipairs(list or {}) do
        -- ts comes from an on-disk JSON file (untrusted boundary); coerce to an
        -- integer so a fractional/string/nil value can never throw from %d and
        -- brick the whole panel. Entries without a usable ts are skipped.
        local ts = math.floor(tonumber(n.ts) or 0)
        if ts > 0 then
            parts[#parts + 1] = string.format('{"ts":%d,"body":%s}', ts, jsonStr(n.body or ""))
        end
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

local function trackListJson(all)
    local parts = {}
    for k, _ in pairs(all) do
        parts[#parts + 1] = jsonStr(k)
    end
    table.sort(parts)
    return "[" .. table.concat(parts, ",") .. "]"
end

local function escSQ(s)
    -- Escapes a value for embedding inside a single-quoted JS string literal.
    -- In addition to \ and ', neutralize "<"/">" as \x3c/\x3e: these decode back
    -- to "<"/">" when the JS string is parsed, but never present a literal
    -- "</script>" to the HTML tokenizer (which would otherwise end an inline
    -- <script> regardless of JS string context — a stored-XSS sink).
    return (s or ""):gsub("\\","\\\\"):gsub("'","\\'"):gsub("<","\\x3c"):gsub(">","\\x3e")
end

-- Escape a value for safe use inside a double-quoted HTML attribute or HTML text.
local function escAttr(s)
    return (s or ""):gsub("&","&amp;"):gsub('"',"&quot;"):gsub("<","&lt;"):gsub(">","&gt;")
end

-- ── HTML ──────────────────────────────────────────────────────────────

local function buildHTML(projectName, trackName, all)
    local displayProject = (projectName == "unsaved_project")
        and "未保存のプロジェクト" or (projectName or ""):gsub("_", " ")
    displayProject = escAttr(displayProject)
    -- value="%s" is a double-quoted HTML attribute, so use HTML-attribute
    -- escaping (not JS single-quote escaping) to prevent attribute breakout.
    local detectedVal = escAttr(trackName or "")
    local notes = (trackName and all[trackName]) or {}
    local notesJ  = escSQ(notesJson(notes))
    local tracksJ = escSQ(trackListJson(all))

    return string.format([[<!DOCTYPE html><html><head><meta charset="utf-8">
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%%;overflow:hidden}
body{background:#1c1c1e;color:#e5e5ea;font-family:-apple-system,"Helvetica Neue",sans-serif;font-size:13px;display:flex;flex-direction:column}
.hdr{padding:12px 14px 10px;border-bottom:1px solid #2c2c2e;flex-shrink:0}
.hdr-top{display:flex;justify-content:space-between;align-items:center;margin-bottom:7px}
.hdr-label{font-size:11px;color:#636366}
.hdr-proj{font-size:13px;font-weight:600;color:#fff;margin-top:2px}
.track-row{display:flex;gap:5px;align-items:center}
#trackInput{flex:1;background:#2c2c2e;color:#e5e5ea;border:1px solid #3a3a3c;border-radius:7px;padding:5px 9px;font-size:13px;font-weight:600;outline:none}
#trackInput:focus{border-color:#0a84ff}
.detect-btn{background:#3a3a3c;border:none;color:#e5e5ea;border-radius:7px;padding:5px 10px;font-size:12px;cursor:pointer;flex-shrink:0}
.detect-btn:hover{background:#48484a}
.nav-btn{background:#3a3a3c;border:none;color:#a1a1a6;border-radius:5px;padding:4px 8px;font-size:12px;cursor:pointer;flex-shrink:0}
.nav-btn:hover{background:#48484a;color:#fff}
.timeline{flex:1;overflow-y:auto;padding:10px 14px}
.note-item{background:#2c2c2e;border-radius:10px;padding:9px 11px;margin-bottom:8px}
.note-meta{display:flex;justify-content:space-between;align-items:center;margin-bottom:5px}
.note-time{font-size:11px;color:#636366;font-variant-numeric:tabular-nums}
.del-btn{background:none;border:none;color:#48484a;font-size:12px;cursor:pointer;padding:0 2px}
.del-btn:hover{color:#ff453a}
.note-body{color:#e5e5ea;line-height:1.55;white-space:pre-wrap;word-break:break-word}
.empty{color:#48484a;text-align:center;margin-top:48px;line-height:1.8}
.inp-area{padding:9px 14px 13px;border-top:1px solid #2c2c2e;flex-shrink:0;display:flex;gap:7px;align-items:flex-end}
textarea{flex:1;background:#2c2c2e;color:#e5e5ea;border:1px solid #3a3a3c;border-radius:8px;padding:7px 9px;font-family:inherit;font-size:13px;resize:none;min-height:34px;max-height:100px;outline:none;line-height:1.45}
textarea:focus{border-color:#0a84ff}
textarea::placeholder{color:#48484a}
button.add{background:#0a84ff;color:#fff;border:none;border-radius:8px;padding:0 13px;height:34px;font-size:13px;font-weight:600;cursor:pointer;flex-shrink:0}
button.add:hover{background:#409cff}
</style></head><body>
<div class="hdr">
  <div class="hdr-top">
    <div><div class="hdr-label">トラックメモ</div><div class="hdr-proj">%s</div></div>
  </div>
  <div class="track-row">
    <button class="nav-btn" onclick="nav(-1)">&#9664;</button>
    <input id="trackInput" placeholder="トラック名を入力..." value="%s" onchange="switchTrack(this.value.trim())" onkeydown="if(event.key==='Enter'){this.blur();switchTrack(this.value.trim());}">
    <button class="detect-btn" onclick="detect()">検出</button>
    <button class="nav-btn" onclick="nav(1)">&#9654;</button>
  </div>
</div>
<div class="timeline" id="timeline"></div>
<div class="inp-area">
  <textarea id="inp" placeholder="メモを入力... (Cmd+Enter で追加)" rows="1"
    oninput="resz(this)" onkeydown="if(event.key==='Enter'&&event.metaKey){event.preventDefault();addNote();}"></textarea>
  <button class="add" onclick="addNote()">追加</button>
</div>
<script>
var currentTrack = '%s';
var notes = JSON.parse('%s');
var tracks = JSON.parse('%s');
function post(p){window.webkit.messageHandlers.lesTrackNotes.postMessage(JSON.stringify(p));}
function escH(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
function resz(el){el.style.height='auto';el.style.height=Math.min(el.scrollHeight,100)+'px';}
function fmt(ts){var d=new Date(ts*1000);return d.getFullYear()+'/'+(d.getMonth()+1).toString().padStart(2,'0')+'/'+d.getDate().toString().padStart(2,'0')+' '+d.getHours().toString().padStart(2,'0')+':'+d.getMinutes().toString().padStart(2,'0');}
function renderNotes(){
  var h='';
  if(!notes.length){h='<div class="empty">メモはまだありません。<br>下の入力欄から追加できます。</div>';}
  else{for(var i=notes.length-1;i>=0;i--){var n=notes[i];h+='<div class="note-item"><div class="note-meta"><span class="note-time">'+fmt(n.ts)+'</span><button class="del-btn" onclick="delNote('+n.ts+')" title="削除">&#x2715;</button></div><div class="note-body">'+escH(n.body)+'</div></div>';}}
  document.getElementById('timeline').innerHTML=h;
}
function switchTrack(name){
  if(!name)return;
  currentTrack=name;
  document.getElementById('trackInput').value=name;
  post({action:'switch',track:name});
}
function detect(){post({action:'detect'});}
function addNote(){
  var text=document.getElementById('inp').value.trim();
  if(!text||!currentTrack)return;
  document.getElementById('inp').value='';
  document.getElementById('inp').style.height='auto';
  post({action:'add',track:currentTrack,text:text});
}
function delNote(ts){if(!confirm('このメモを削除しますか？'))return;post({action:'delete',track:currentTrack,ts:ts});}
function nav(dir){
  if(!tracks.length)return;
  var idx=tracks.indexOf(currentTrack);
  var next=tracks[(idx+dir+tracks.length)%%tracks.length];
  switchTrack(next);
}
function setTrack(name,newNotes,newTracks){
  currentTrack=name;
  notes=newNotes;
  tracks=newTracks;
  document.getElementById('trackInput').value=name;
  renderNotes();
}
function setDetected(name){
  if(name){document.getElementById('trackInput').value=name;switchTrack(name);}
}
renderNotes();
document.getElementById('inp').focus();
</script>
</body></html>]], displayProject, detectedVal, escSQ(trackName or ""), notesJ, tracksJ)
end

-- ── Webview ───────────────────────────────────────────────────────────

local function jsEval(js)
    if _webview then pcall(function() _webview:evaluateJavaScript(js) end) end
end

local function refreshTrack(trackName)
    if not _webview or not _project then return end
    local all = tracknotes.loadAll(_project)
    local notes = all[trackName] or {}
    local nj  = escSQ(notesJson(notes))
    local tj  = escSQ(trackListJson(all))
    jsEval(string.format("setTrack('%s',%s,%s);", escSQ(trackName), "JSON.parse('"..nj.."')", "JSON.parse('"..tj.."')"))
end

--- Open (or focus) the track notes panel.
function openTrackNotes()
    local project = _G.trackname or "unsaved_project"

    if _webview ~= nil then
        _project = project
        local detected = detectTrackName()
        if detected then
            _track = detected
            refreshTrack(detected)
        end
        local w = _webview:hswindow()
        if w then w:focus() end
        return
    end

    _project = project
    _track   = detectTrackName()

    local all = tracknotes.loadAll(project)

    _uc = hs.webview.usercontent.new("lesTrackNotes")
    _uc:setCallback(function(msg)
        if type(msg) ~= "table" then return end
        local body = msg.body
        if type(body) == "string" then
            local ok, decoded = pcall(hs.json.decode, body)
            if not ok or type(decoded) ~= "table" then return end
            body = decoded
        end
        if type(body) ~= "table" or not _project then return end

        local action = body.action
        if action == "add" then
            local track = body.track
            local text  = body.text
            if type(track) == "string" and type(text) == "string" then
                _track = track
                tracknotes.addNote(_project, track, text)
                hs.timer.doAfter(0.05, function() refreshTrack(track) end)
            end
        elseif action == "delete" then
            local track = body.track
            local ts    = tonumber(body.ts)
            if type(track) == "string" and type(ts) == "number" then
                tracknotes.deleteNote(_project, track, ts)
                hs.timer.doAfter(0.05, function() refreshTrack(track) end)
            end
        elseif action == "detect" then
            local name = detectTrackName()
            if name then
                _track = name
                jsEval(string.format("setDetected('%s');", escSQ(name)))
                hs.timer.doAfter(0.05, function() refreshTrack(name) end)
            else
                jsEval("setDetected(null);")
            end
        elseif action == "switch" then
            local track = body.track
            if type(track) == "string" and track ~= "" then
                _track = track
                hs.timer.doAfter(0.05, function() refreshTrack(track) end)
            end
        end
    end)

    local screen = hs.screen.mainScreen():frame()
    local W, H = 420, 580
    local x = math.floor(screen.x + screen.w - W - 40)
    local y = math.floor(screen.y + 60)

    _webview = hs.webview.new({x = x, y = y, w = W, h = H}, {developerExtrasEnabled = false}, _uc)
    _webview:windowStyle({"titled", "closable", "resizable", "nonactivating"})
    _webview:windowTitle("トラックメモ")
    _webview:level(hs.drawing.windowLevels.floating)
    _webview:allowTextEntry(true)
    _webview:html(buildHTML(project, _track, all))
    -- hs.webview:windowCallback passes the action string as the FIRST argument
    -- (fn("closing", webview)). Binding it to the second slot made the guard
    -- always-false, so cleanup never ran and the panel could not be reopened.
    _webview:windowCallback(function(action)
        if action == "closing" then
            _webview  = nil
            _uc       = nil
            _project  = nil
            _track    = nil
        end
    end)
    _webview:show()
    _webview:bringToFront()
end

return tracknotes

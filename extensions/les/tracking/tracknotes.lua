--  SPDX-License-Identifier: MIT
--  Track Notes — per-track memos within an Ableton project
--  Data: ~/.les/resources/tracknotes/[project].json
--  {"BASS":[{"ts":1234567890,"body":"..."}], ...}

local tracknotes = {}
local storageKey = require("util.storagekey")
local noteId = require("util.noteid")
local windowframe = require("util.windowframe")
local utf8text = require("util.utf8text")

---@type hs.webview|nil
local _webview = nil
---@type hs.webview.usercontent|nil
local _uc = nil
---@type string|nil
local _project = nil
---@type string|nil
local _track = nil

local NOTES_DIR = "tracknotes"
local MAX_TRACK_NAME_LENGTH = 200
local MAX_NOTE_LENGTH = 20000

-- ── Storage ───────────────────────────────────────────────────────────

local function notesDir()
    return strJoinPaths(ScriptUserResourcesPath, NOTES_DIR)
end

local function notesFilePath(projectName)
    return strJoinPaths(notesDir(), storageKey.forProject(projectName) .. ".json")
end

local function legacyNotesFilePath(projectName)
    -- `trackname` was historically sanitized before this module saw it, so
    -- spaces and punctuation both became underscores.
    local legacyName = (projectName or "unsaved_project"):gsub("[%p%c%s]", "_")
    return strJoinPaths(notesDir(), legacyName .. ".json")
end

local function openNotesFile(projectName)
    local file = io.open(notesFilePath(projectName), "r")
    if file then return file end
    return io.open(legacyNotesFilePath(projectName), "r")
end

--- Load all track notes for a project.
---@param projectName string
---@return table  {trackName = [{ts, body}]}
function tracknotes.loadAll(projectName)
    local f = openNotesFile(projectName)
    if not f then return {} end
    local raw = f:read("*a")
    f:close()
    if not raw or raw == "" then return {} end
    local ok, data = pcall(hs.json.decode, raw)
    if not ok or type(data) ~= "table" then return {} end

    local cleaned = {}
    for trackName, notes in pairs(data) do
        if type(trackName) == "string" and trackName ~= "" and type(notes) == "table" then
            local cleanNotes = {}
            for index, note in ipairs(notes) do
                if type(note) == "table" then
                    local timestamp = math.floor(tonumber(note.ts) or 0)
                    if timestamp > 0 then
                        cleanNotes[#cleanNotes + 1] = {
                            id = noteId.normalize(note.id, timestamp, index),
                            ts = timestamp,
                            body = tostring(note.body or ""),
                        }
                    end
                end
            end
            cleaned[trackName] = cleanNotes
        end
    end
    return cleaned
end

--- Save all track notes for a project.
---@param projectName string
---@param data table
---@return boolean ok
---@return string|nil err
function tracknotes.saveAll(projectName, data)
    if type(data) ~= "table" then return false, "track notes data must be a table" end
    ShellCreateDirectory(notesDir())
    local path = notesFilePath(projectName)
    local ok, json = pcall(hs.json.encode, data, true)
    if not ok or type(json) ~= "string" then return false, "track notes JSON encoding failed" end

    local tempPath = path .. ".tmp"
    local f, openError = io.open(tempPath, "w")
    if not f then return false, tostring(openError) end
    local written, writeError = f:write(json)
    if not written then
        f:close()
        os.remove(tempPath)
        return false, tostring(writeError)
    end
    local closed, closeError = f:close()
    if not closed then
        os.remove(tempPath)
        return false, tostring(closeError)
    end
    local renamed, renameError = os.rename(tempPath, path)
    if not renamed then
        os.remove(tempPath)
        return false, tostring(renameError)
    end
    return true
end

--- Append a note to a specific track.
---@param projectName string
---@param trackName string
---@param text string
function tracknotes.addNote(projectName, trackName, text)
    if type(trackName) ~= "string" or trackName == ""
        or not utf8text.isWithinLimit(trackName, MAX_TRACK_NAME_LENGTH) then
        return false
    end
    if type(text) ~= "string" or text:match("^%s*$")
        or not utf8text.isWithinLimit(text, MAX_NOTE_LENGTH) then
        return false
    end
    local all = tracknotes.loadAll(projectName)
    local currentNotes = type(all[trackName]) == "table" and all[trackName] or {}
    local updatedNotes = {}
    for index, note in ipairs(currentNotes) do updatedNotes[index] = note end
    updatedNotes[#updatedNotes + 1] = {
        id   = noteId.create(),
        ts   = math.floor(hs.timer.secondsSinceEpoch()),
        body = text,
    }
    local updatedAll = {}
    for name, notes in pairs(all) do updatedAll[name] = notes end
    updatedAll[trackName] = updatedNotes
    return tracknotes.saveAll(projectName, updatedAll)
end

--- Delete a note by persistent id from a specific track. Numeric timestamps
--- remain accepted for old callers, but remove only the first match.
---@param projectName string
---@param trackName string
---@param identifier string|number
function tracknotes.deleteNote(projectName, trackName, identifier)
    if type(trackName) ~= "string" then return false end
    if type(identifier) ~= "string" and type(identifier) ~= "number" then return false end
    local all = tracknotes.loadAll(projectName)
    if type(all[trackName]) ~= "table" then return false end
    local kept = {}
    local removed = false
    for _, n in ipairs(all[trackName]) do
        local matches = type(identifier) == "string" and n.id == identifier
            or type(identifier) == "number" and n.ts == identifier
        if matches and not removed then
            removed = true
        else
            kept[#kept + 1] = n
        end
    end
    if not removed then return false end
    local updatedAll = {}
    for name, notes in pairs(all) do updatedAll[name] = notes end
    updatedAll[trackName] = kept
    return tracknotes.saveAll(projectName, updatedAll)
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
        local nameLength = utf8text.length(name)
        if nameLength and nameLength > 0 and nameLength < 60
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
            parts[#parts + 1] = string.format('{"id":%s,"ts":%d,"body":%s}',
                jsonStr(n.id or ""), ts, jsonStr(n.body or ""))
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

local function replaceTokens(template, values)
    return (template:gsub("__([A-Z0-9_]+)__", function(key)
        return values[key] or ""
    end))
end

-- ── HTML ──────────────────────────────────────────────────────────────

local function buildHTML(projectName, trackName, all)
    local displayProject = (projectName == "unsaved_project")
        and L("notes_unsaved_project") or (projectName or "")
    displayProject = escAttr(displayProject)
    -- value="%s" is a double-quoted HTML attribute, so use HTML-attribute
    -- escaping (not JS single-quote escaping) to prevent attribute breakout.
    local detectedVal = escAttr(trackName or "")
    local notes = (trackName and all[trackName]) or {}
    local notesJ  = escSQ(notesJson(notes))
    local tracksJ = escSQ(trackListJson(all))

    local template = [[<!DOCTYPE html><html lang="__LANG__"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%%;overflow:hidden}
body{color-scheme:dark;background:#1c1c1e;color:#e5e5ea;font-family:-apple-system,"Helvetica Neue",sans-serif;font-size:13px;display:flex;flex-direction:column}
.hdr{padding:12px 14px 10px;border-bottom:1px solid #2c2c2e;flex-shrink:0}
.hdr-top{display:flex;justify-content:space-between;align-items:center;margin-bottom:7px}
.hdr-top>div{min-width:0}
.hdr-label{font-size:11px;color:#a1a1a6}
.hdr-proj{font-size:13px;font-weight:600;color:#fff;margin-top:2px;overflow-wrap:anywhere}
.track-row{display:flex;gap:5px;align-items:center}
#trackInput{flex:1;min-width:0;background:#2c2c2e;color:#e5e5ea;border:1px solid #3a3a3c;border-radius:7px;padding:5px 9px;font-size:13px;font-weight:600;outline:none}
#trackInput:focus{border-color:#0a84ff}
.detect-btn{background:#3a3a3c;border:none;color:#e5e5ea;border-radius:7px;padding:5px 10px;font-size:12px;cursor:pointer;flex-shrink:0}
.detect-btn:hover{background:#48484a}
.nav-btn{background:#3a3a3c;border:none;color:#a1a1a6;border-radius:5px;padding:4px 8px;font-size:12px;cursor:pointer;flex-shrink:0}
.nav-btn:hover{background:#48484a;color:#fff}
.timeline{flex:1;overflow-y:auto;padding:10px 14px}
.note-item{background:#2c2c2e;border-radius:10px;padding:9px 11px;margin-bottom:8px}
.note-meta{display:flex;justify-content:space-between;align-items:center;margin-bottom:5px}
.note-time{font-size:11px;color:#a1a1a6;font-variant-numeric:tabular-nums}
.del-btn{background:none;border:none;color:#a1a1a6;font-size:12px;cursor:pointer;min-width:30px;min-height:30px;padding:4px 8px}
.del-btn:hover{color:#ff453a}
.note-body{color:#e5e5ea;line-height:1.55;white-space:pre-wrap;word-break:break-word}
.empty{color:#a1a1a6;text-align:center;margin-top:48px;line-height:1.8}
.inp-area{padding:9px 14px 13px;border-top:1px solid #2c2c2e;flex-shrink:0;display:flex;gap:7px;align-items:flex-end}
textarea{flex:1;background:#2c2c2e;color:#e5e5ea;border:1px solid #3a3a3c;border-radius:8px;padding:7px 9px;font-family:inherit;font-size:13px;resize:none;min-height:34px;max-height:100px;outline:none;line-height:1.45}
textarea:focus{border-color:#0a84ff}
textarea::placeholder{color:#8e8e93}
button.add{background:#0a84ff;color:#fff;border:none;border-radius:8px;padding:0 13px;height:34px;font-size:13px;font-weight:600;cursor:pointer;flex-shrink:0}
button.add:hover{background:#409cff}
button:disabled,textarea:disabled{opacity:.5;cursor:default}
button:focus-visible,input:focus-visible,textarea:focus-visible{outline:2px solid #64b5ff;outline-offset:2px}
.status{min-height:18px;color:#a1a1a6;font-size:11px;padding:0 14px}
.status.error{color:#ff6961}
</style></head><body>
<div class="hdr">
  <div class="hdr-top">
    <div><div class="hdr-label">__TRACKNOTES_TITLE__</div><div class="hdr-proj">%s</div></div>
  </div>
  <div class="track-row">
    <button type="button" class="nav-btn" aria-label="__PREV_LABEL__" onclick="nav(-1)">&#9664;</button>
    <input id="trackInput" aria-label="__TRACK_LABEL__" maxlength="__MAX_TRACK_CODE_UNITS__" placeholder="__TRACK_PLACEHOLDER__" value="%s" onchange="switchTrack(this.value.trim())" onkeydown="if(event.key==='Enter'){this.blur();switchTrack(this.value.trim());}">
    <button type="button" class="detect-btn" onclick="detect()">__DETECT__</button>
    <button type="button" class="nav-btn" aria-label="__NEXT_LABEL__" onclick="nav(1)">&#9654;</button>
  </div>
</div>
<div class="timeline" id="timeline" role="list"></div>
<div class="status" id="status" role="status" aria-live="polite"></div>
<div class="inp-area">
  <textarea id="inp" aria-label="__INPUT_LABEL__" maxlength="__MAX_NOTE_CODE_UNITS__" placeholder="__INPUT_PLACEHOLDER__" rows="1"
    oninput="resz(this)" onkeydown="if(event.key==='Enter'&&event.metaKey){event.preventDefault();addNote();}"></textarea>
  <button type="button" class="add" id="addBtn" onclick="addNote()">__ADD__</button>
</div>
<script>
var currentTrack = '%s';
var notes = JSON.parse('%s');
var tracks = JSON.parse('%s');
var notePending = false;
var deletionPending = false;
var maxTrackNameLength = __MAX_TRACK_LENGTH__;
var maxNoteLength = __MAX_NOTE_LENGTH__;
function charLength(value){return Array.from(value).length;}
function post(p){window.webkit.messageHandlers.lesTrackNotes.postMessage(JSON.stringify(p));}
function escH(s){return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');}
function resz(el){el.style.height='auto';el.style.height=Math.min(el.scrollHeight,100)+'px';}
function fmt(ts){var d=new Date(ts*1000);return d.getFullYear()+'/'+(d.getMonth()+1).toString().padStart(2,'0')+'/'+d.getDate().toString().padStart(2,'0')+' '+d.getHours().toString().padStart(2,'0')+':'+d.getMinutes().toString().padStart(2,'0');}
function renderNotes(){
  var h='';
  if(!notes.length){h='<div class="empty">__EMPTY_JS__</div>';}
  else{for(var i=notes.length-1;i>=0;i--){var n=notes[i],when=fmt(n.ts);h+='<div class="note-item" role="listitem"><div class="note-meta"><span class="note-time">'+when+'</span><button type="button" class="del-btn" data-id="'+escH(n.id)+'" data-note-time="'+escH(when)+'" onclick="delNote(this.dataset.id,this.dataset.noteTime)" aria-label="'+escH(when+' — __DELETE_LABEL_JS__')+'">&#x2715;</button></div><div class="note-body">'+escH(n.body)+'</div></div>';}}
  document.getElementById('timeline').innerHTML=h;
}
function switchTrack(name){
  if(!name)return;
  if(charLength(name)>maxTrackNameLength){setStatus('__INPUT_TOO_LONG_JS__',true);return;}
  currentTrack=name;
  document.getElementById('trackInput').value=name;
  setStatus('',false);
  post({action:'switch',track:name});
}
function detect(){post({action:'detect'});}
function addNote(){
  if(notePending)return;
  var text=document.getElementById('inp').value.trim();
  if(!currentTrack){setStatus('__TRACK_REQUIRED_JS__',true);return;}
  if(!text)return;
  if(charLength(currentTrack)>maxTrackNameLength||charLength(text)>maxNoteLength){setStatus('__INPUT_TOO_LONG_JS__',true);return;}
  notePending=true;
  document.getElementById('inp').disabled=true;
  document.getElementById('addBtn').disabled=true;
  setStatus('__SAVING_JS__',false);
  post({action:'add',track:currentTrack,text:text});
}
function setStatus(message,isError){var s=document.getElementById('status');s.textContent=message||'';s.className=isError?'status error':'status';}
function noteOperationResult(ok,message){
  notePending=false;
  var inp=document.getElementById('inp');inp.disabled=false;
  document.getElementById('addBtn').disabled=false;
  if(ok){inp.value='';resz(inp);}
  setStatus(message||(ok?'__SAVED_JS__':'__SAVE_FAILED_JS__'),!ok);
  inp.focus();
}
function deleteOperationResult(ok,message){if(!ok)deletionPending=false;setStatus(message||'',!ok);}
function delNote(id,when){if(!confirm(when+' — __DELETE_CONFIRM_JS__'))return;deletionPending=true;post({action:'delete',track:currentTrack,id:id});}
function nav(dir){
  if(!tracks.length)return;
  var idx=tracks.indexOf(currentTrack);
  if(idx<0){idx=dir<0?0:-1;}
  var next=tracks[(idx+dir+tracks.length)%%tracks.length];
  switchTrack(next);
}
function setTrack(name,newNotes,newTracks){
  currentTrack=name;
  notes=newNotes;
  tracks=newTracks;
  document.getElementById('trackInput').value=name;
  renderNotes();
  if(deletionPending){deletionPending=false;var nextDelete=document.querySelector('#timeline .del-btn');(nextDelete||document.getElementById('inp')).focus();}
}
function setDetected(name){
  if(name){document.getElementById('trackInput').value=name;switchTrack(name);}
  else{setStatus('__DETECT_FAILED_JS__',true);}
}
function announceTrack(message){setStatus(message,false);}
renderNotes();
document.getElementById('inp').focus();
</script>
</body></html>]]
    template = replaceTokens(template, {
        LANG = escAttr(L("locale_code")),
        TRACKNOTES_TITLE = escAttr(L("tracknotes_title")),
        PREV_LABEL = escAttr(L("tracknotes_prev_label")),
        NEXT_LABEL = escAttr(L("tracknotes_next_label")),
        TRACK_LABEL = escAttr(L("tracknotes_track_label")),
        TRACK_PLACEHOLDER = escAttr(L("tracknotes_track_placeholder")),
        DETECT = escAttr(L("tracknotes_detect")),
        INPUT_LABEL = escAttr(L("tracknotes_input_label")),
        INPUT_PLACEHOLDER = escAttr(L("notes_input_placeholder")),
        INPUT_TOO_LONG_JS = escSQ(L("tracknotes_input_too_long")),
        MAX_TRACK_LENGTH = tostring(MAX_TRACK_NAME_LENGTH),
        MAX_TRACK_CODE_UNITS = tostring(MAX_TRACK_NAME_LENGTH * 2),
        MAX_NOTE_LENGTH = tostring(MAX_NOTE_LENGTH),
        MAX_NOTE_CODE_UNITS = tostring(MAX_NOTE_LENGTH * 2),
        ADD = escAttr(L("notes_add")),
        EMPTY_JS = escSQ(L("notes_empty")),
        DELETE_LABEL_JS = escSQ(L("notes_delete_label")),
        TRACK_REQUIRED_JS = escSQ(L("tracknotes_track_required")),
        SAVING_JS = escSQ(L("notes_saving")),
        SAVED_JS = escSQ(L("notes_saved")),
        SAVE_FAILED_JS = escSQ(L("notes_save_failed")),
        DELETE_CONFIRM_JS = escSQ(L("notes_delete_confirm")),
        DETECT_FAILED_JS = escSQ(L("tracknotes_detect_failed")),
    })
    return string.format(template, displayProject, detectedVal, escSQ(trackName or ""), notesJ, tracksJ)
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

local function chooseInitialTrack(all, detected)
    if type(detected) == "string" and detected ~= "" then return detected end
    local names = {}
    for name in pairs(all or {}) do names[#names + 1] = name end
    table.sort(names)
    return names[1]
end

local function refreshView(projectName, preferredTrack)
    if not _webview then return end
    local all = tracknotes.loadAll(projectName)
    local selectedTrack = chooseInitialTrack(all, preferredTrack)
    _project = projectName
    _track = selectedTrack
    _webview:html(buildHTML(projectName, selectedTrack, all))
end

--- Open (or focus) the track notes panel.
function openTrackNotes()
    local project = _G.trackname or "unsaved_project"

    if _webview ~= nil then
        if _project ~= project then
            local detected = detectTrackName()
            refreshView(project, detected)
        end
        local w = _webview:hswindow()
        if w then w:focus() end
        return
    end

    local all = tracknotes.loadAll(project)
    _project = project
    _track = chooseInitialTrack(all, detectTrackName())

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
            if utf8text.isWithinLimit(track, MAX_TRACK_NAME_LENGTH)
                and utf8text.isWithinLimit(text, MAX_NOTE_LENGTH) then
                _track = track
                local saved = tracknotes.addNote(_project, track, text)
                if saved then
                    refreshTrack(track)
                    jsEval(string.format("noteOperationResult(true,'%s')", escSQ(L("notes_saved"))))
                else
                    jsEval(string.format("noteOperationResult(false,'%s')",
                        escSQ(L("notes_save_failed_preserved"))))
                end
            else
                jsEval(string.format("noteOperationResult(false,'%s')",
                    escSQ(L("tracknotes_input_too_long"))))
            end
        elseif action == "delete" then
            local track = body.track
            local identifier = type(body.id) == "string" and body.id or tonumber(body.ts)
            if utf8text.isWithinLimit(track, MAX_TRACK_NAME_LENGTH)
                and (type(identifier) == "string" or type(identifier) == "number") then
                local deleted = tracknotes.deleteNote(_project, track, identifier)
                if deleted then
                    refreshTrack(track)
                    jsEval(string.format("deleteOperationResult(true,'%s')", escSQ(L("notes_deleted"))))
                else
                    jsEval(string.format("deleteOperationResult(false,'%s')", escSQ(L("notes_delete_failed"))))
                end
            else
                jsEval(string.format("deleteOperationResult(false,'%s')", escSQ(L("notes_delete_failed"))))
            end
        elseif action == "detect" then
            local name = detectTrackName()
            if name then
                _track = name
                jsEval(string.format("setDetected('%s');", escSQ(name)))
                refreshTrack(name)
            else
                jsEval("setDetected(null);")
            end
        elseif action == "switch" then
            local track = body.track
            if type(track) == "string" and track ~= ""
                and utf8text.isWithinLimit(track, MAX_TRACK_NAME_LENGTH) then
                _track = track
                refreshTrack(track)
                jsEval(string.format("announceTrack('%s');",
                    escSQ(string.format(L("tracknotes_switched_status"), track))))
            end
        end
    end)

    local screen = hs.screen.mainScreen():frame()
    local frame = windowframe.right(screen, 420, 580, 12, 60)

    _webview = hs.webview.new(frame, {developerExtrasEnabled = false}, _uc)
    if _webview == nil then return end
    local currentWebview = _webview
    _webview:deleteOnClose(true)
    _webview:windowStyle({"titled", "closable", "resizable", "nonactivating"})
    _webview:windowTitle(L("tracknotes_title"))
    _webview:level(hs.drawing.windowLevels.floating)
    _webview:allowTextEntry(true)
    _webview:html(buildHTML(project, _track, all))
    -- hs.webview:windowCallback passes the action string as the FIRST argument
    -- (fn("closing", webview)). Binding it to the second slot made the guard
    -- always-false, so cleanup never ran and the panel could not be reopened.
    _webview:windowCallback(function(action)
        if action == "closing" and _webview == currentWebview then
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

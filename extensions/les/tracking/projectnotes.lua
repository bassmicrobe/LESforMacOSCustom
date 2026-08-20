--  SPDX-License-Identifier: MIT
--
--  Copyright (c) 2019-2023 LESforMacOS authors, see AUTHORS.txt
--  for a list
--
--  Distributed under the MIT software license, see the accompanying
--  file COPYING.txt or visit https://opensource.org/license/mit/

-------------------------------------------------
--  Project Notes (Timeline)                   --
--  Per-project notes stored as JSON           --
--  ~/.les/resources/notes/[project].json      --
-------------------------------------------------

local projectnotes = {}
local storageKey = require("util.storagekey")
local noteId = require("util.noteid")
local windowframe = require("util.windowframe")
local utf8text = require("util.utf8text")

---@type hs.webview|nil
local _webview = nil
---@type hs.webview.usercontent|nil
local _notesUC = nil
-- Track which project is currently open for the webview message handler
local _currentProject = nil
-- AI summary integration (lazy-loaded)
local _openai = nil
local _summaryGeneration = 0
local _summaryPendingProject = nil

local NOTES_DIR = "notes"
local MAX_NOTE_LENGTH = 20000

--- Full path to the notes directory.
---@return string
local function notesDir()
    return strJoinPaths(ScriptUserResourcesPath, NOTES_DIR)
end

--- Full path to the notes file for a given project.
---@param projectName string
---@return string
local function notesFilePath(projectName)
    return strJoinPaths(notesDir(), storageKey.forProject(projectName) .. ".json")
end

local function legacyNotesFilePath(projectName)
    local legacyName = (projectName or "unsaved_project"):gsub("[%p%c%s]", "_")
    return strJoinPaths(notesDir(), legacyName .. ".json")
end

local function openNotesFile(projectName)
    local file = io.open(notesFilePath(projectName), "r")
    if file then return file end
    return io.open(legacyNotesFilePath(projectName), "r")
end

--- Load notes for a project. Returns an array sorted by timestamp ascending.
---@param projectName string
---@return table
function projectnotes.load(projectName)
    local f = openNotesFile(projectName)
    if not f then return {} end
    local raw = f:read("*a")
    f:close()
    if not raw or raw == "" then return {} end
    local ok, data = pcall(hs.json.decode, raw)
    if not (ok and type(data) == "table") then return {} end
    -- The notes file is an untrusted boundary (may be hand-edited or written by
    -- another tool). Keep only well-formed records with a numeric timestamp and
    -- coerce body to a string, so downstream os.date/string.format/gsub can
    -- never throw on a malformed entry and brick the whole panel.
    local cleaned = {}
    for index, n in ipairs(data) do
        if type(n) == "table" then
            local ts = math.floor(tonumber(n.timestamp) or 0)
            if ts > 0 then
                cleaned[#cleaned + 1] = {
                    id = noteId.normalize(n.id, ts, index),
                    timestamp = ts,
                    body = tostring(n.body or ""),
                }
            end
        end
    end
    return cleaned
end

--- Save notes for a project.
---@param projectName string
---@param notes table
function projectnotes.save(projectName, notes)
    ShellCreateDirectory(notesDir())
    local path = notesFilePath(projectName)
    -- Guard the encode: hs.json.encode can return nil on a bad table, which the
    -- old code would happily write (truncating the file). Bail instead.
    local ok, json = pcall(hs.json.encode, notes, true)
    if not ok or type(json) ~= "string" then return false end
    -- Atomic write: encode to a temp file then rename over the target so an
    -- interrupted/failed write never leaves truncated/corrupt notes behind.
    local tmp = path .. ".tmp"
    local f = io.open(tmp, "w")
    if not f then return false end
    local written = f:write(json)
    if not written then
        f:close()
        os.remove(tmp)
        return false
    end
    if not f:close() then
        os.remove(tmp)
        return false
    end
    if not os.rename(tmp, path) then
        os.remove(tmp)
        return false
    end
    return true
end

--- Append a new note entry.
---@param projectName string
---@param text string
function projectnotes.addNote(projectName, text)
    if type(text) ~= "string" or text:match("^%s*$")
        or not utf8text.isWithinLimit(text, MAX_NOTE_LENGTH) then
        return false
    end
    local notes = projectnotes.load(projectName)
    local updated = {}
    for index, note in ipairs(notes) do updated[index] = note end
    updated[#updated + 1] = {
        id        = noteId.create(),
        timestamp = math.floor(hs.timer.secondsSinceEpoch()),
        body      = text,
    }
    return projectnotes.save(projectName, updated)
end

--- Delete a note identified by its persistent id. Numeric timestamps remain
--- accepted for old callers, but remove only the first match.
---@param projectName string
---@param identifier string|number
function projectnotes.deleteNote(projectName, identifier)
    if type(identifier) ~= "string" and type(identifier) ~= "number" then return false end
    local notes = projectnotes.load(projectName)
    local newNotes = {}
    local removed = false
    for _, n in ipairs(notes) do
        local matches = type(identifier) == "string" and n.id == identifier
            or type(identifier) == "number" and n.timestamp == identifier
        if matches and not removed then
            removed = true
        else
            newNotes[#newNotes + 1] = n
        end
    end
    if not removed then return false end
    return projectnotes.save(projectName, newNotes)
end

-- ── HTML builder ──────────────────────────────────────────────────────

--- Escape text for safe HTML embedding.
---@param s string
---@return string
local function escapeHTML(s)
    return s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
end

local function jsEscape(s)
    return tostring(s or ""):gsub("\\", "\\\\"):gsub("'", "\\'")
        :gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("<", "\\x3c"):gsub(">", "\\x3e")
end

local function replaceTokens(template, values)
    return (template:gsub("__([A-Z0-9_]+)__", function(key)
        return values[key] or ""
    end))
end

local function buildTimelineHTML(notes)
    local items = {}
    for i = #notes, 1, -1 do
        local n = notes[i]
        local dt = os.date("%Y/%m/%d %H:%M", n.timestamp)
        local body = escapeHTML(n.body):gsub("\n", "<br>")
        items[#items + 1] = string.format([[
<div class="note-item" role="article" aria-label="%s">
  <div class="note-meta">
    <span class="note-time">%s</span>
    <button type="button" class="delete-btn" data-id="%s" data-note-time="%s" onclick="deleteNote(this.dataset.id,this.dataset.noteTime)" aria-label="%s">✕</button>
  </div>
  <div class="note-body">%s</div>
</div>]], escapeHTML(string.format(L("notes_item_label"), dt)), dt, escapeHTML(tostring(n.id)),
            escapeHTML(dt), escapeHTML(dt .. " — " .. L("notes_delete_label")), body)
    end

    return (#items > 0)
        and table.concat(items, "")
        or '<p class="empty">' .. L("notes_empty") .. '</p>'
end

--- Build full HTML for the notes panel.
---@param projectName string
---@param notes table
---@return string
local function buildNotesHTML(projectName, notes)
    local displayName = (projectName == "unsaved_project")
        and L("notes_unsaved_project")
        or escapeHTML(projectName)
    local timelineHTML = buildTimelineHTML(notes)

    local template = [[<!DOCTYPE html><html lang="__LANG__"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { height: 100%%; overflow: hidden; }
body {
    color-scheme: dark;
    background: #1c1c1e;
    color: #e5e5ea;
    font-family: -apple-system, "Helvetica Neue", sans-serif;
    font-size: 13px;
    display: flex;
    flex-direction: column;
}
.header {
    padding: 14px 16px 12px;
    border-bottom: 1px solid #2c2c2e;
    flex-shrink: 0;
}
.project-label { font-size: 11px; color: #a1a1a6; margin-bottom: 3px; }
.project-heading { min-width: 0; }
.project-name  { font-size: 15px; font-weight: 600; color: #fff; overflow-wrap: anywhere; }
.timeline {
    flex: 1;
    overflow-y: auto;
    padding: 12px 16px;
}
.note-item {
    background: #2c2c2e;
    border-radius: 10px;
    padding: 10px 12px;
    margin-bottom: 10px;
}
.note-meta {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 6px;
}
.note-time {
    font-size: 11px;
    color: #a1a1a6;
    font-variant-numeric: tabular-nums;
}
.delete-btn {
    background: none;
    border: none;
    color: #8e8e93;
    font-size: 12px;
    cursor: pointer;
    line-height: 1;
    min-width: 30px;
    min-height: 30px;
    padding: 4px 8px;
}
.delete-btn:hover { color: #ff453a; }
.note-body { color: #e5e5ea; line-height: 1.55; white-space: pre-wrap; word-break: break-word; }
.empty { color: #8e8e93; text-align: center; margin-top: 48px; line-height: 1.8; }
.input-area {
    padding: 10px 16px 14px;
    border-top: 1px solid #2c2c2e;
    flex-shrink: 0;
    display: flex;
    gap: 8px;
    align-items: flex-end;
}
textarea {
    flex: 1;
    background: #2c2c2e;
    color: #e5e5ea;
    border: 1px solid #3a3a3c;
    border-radius: 8px;
    padding: 8px 10px;
    font-family: inherit;
    font-size: 13px;
    resize: none;
    min-height: 36px;
    max-height: 110px;
    outline: none;
    line-height: 1.45;
}
textarea:focus { border-color: #0a84ff; }
textarea::placeholder { color: #8e8e93; }
button.submit {
    background: #0a84ff;
    color: #fff;
    border: none;
    border-radius: 8px;
    padding: 0 14px;
    height: 36px;
    font-size: 13px;
    font-weight: 600;
    cursor: pointer;
    flex-shrink: 0;
}
button.submit:hover { background: #409cff; }
button:disabled, textarea:disabled { opacity: 0.5; cursor: default; }
button:focus-visible, textarea:focus-visible {
    outline: 2px solid #64b5ff;
    outline-offset: 2px;
}
.status { min-height: 18px; color: #a1a1a6; font-size: 11px; padding: 0 16px; }
.status.error { color: #ff6961; }
</style>
</head><body>
<div class="header">
  <div style="display:flex;justify-content:space-between;align-items:center;">
    <div class="project-heading">
      <div class="project-label">__PROJECT_TITLE__</div>
      <div class="project-name">%s</div>
    </div>
    <button type="button" onclick="aiSummary()" id="aiBtn" aria-describedby="status"
      style="background:#30d158;color:#000;border:none;border-radius:8px;padding:5px 12px;font-size:12px;font-weight:600;cursor:pointer;flex-shrink:0;">
      __AI_SUMMARY__</button>
  </div>
</div>
<div class="timeline" id="timeline" role="feed">%s</div>
<div class="status" id="status" role="status" aria-live="polite"></div>
<div class="input-area">
  <textarea id="inp" aria-label="__INPUT_LABEL__" maxlength="__MAX_NOTE_CODE_UNITS__" placeholder="__INPUT_PLACEHOLDER__" rows="1"
    oninput="resize(this)" onkeydown="onKey(event)"></textarea>
  <button type="button" class="submit" id="addBtn" onclick="submit()">__ADD__</button>
</div>
<script>
var notePending = false;
var deletionPending = false;
var maxNoteLength = __MAX_NOTE_LENGTH__;
function charLength(value) { return Array.from(value).length; }
function resize(el) {
    el.style.height = 'auto';
    el.style.height = Math.min(el.scrollHeight, 110) + 'px';
}
function onKey(e) {
    if (e.key === 'Enter' && e.metaKey) { e.preventDefault(); submit(); }
}
// Always stringify: WKWebView → Lua is most reliable as JSON text
// (bridged NSDictionary tables can fail key lookups on the Lua side).
function post(payload) {
    window.webkit.messageHandlers.lesProjectNotes.postMessage(JSON.stringify(payload));
}
function submit() {
    if (notePending) return;
    var text = document.getElementById('inp').value.trim();
    if (!text) return;
    if (charLength(text) > maxNoteLength) {
        setStatus('__TOO_LONG_JS__', true);
        document.getElementById('inp').focus();
        return;
    }
    notePending = true;
    document.getElementById('inp').disabled = true;
    document.getElementById('addBtn').disabled = true;
    setStatus('__SAVING_JS__', false);
    post({ action: 'add', text: text });
}
function setStatus(message, isError) {
    var status = document.getElementById('status');
    status.textContent = message || '';
    status.className = isError ? 'status error' : 'status';
}
function noteOperationResult(ok, message) {
    notePending = false;
    var inp = document.getElementById('inp');
    inp.disabled = false;
    document.getElementById('addBtn').disabled = false;
    if (ok) { inp.value = ''; resize(inp); }
    setStatus(message || (ok ? '__SAVED_JS__' : '__SAVE_FAILED_JS__'), !ok);
    inp.focus();
}
function replaceTimeline(html) {
    document.getElementById('timeline').innerHTML = html;
    if (deletionPending) {
        deletionPending = false;
        var nextDelete = document.querySelector('#timeline .delete-btn');
        (nextDelete || document.getElementById('inp')).focus();
    }
}
function deleteOperationResult(ok, message) {
    if (!ok) deletionPending = false;
    setStatus(message || '', !ok);
}
function deleteNote(id, when) {
    if (!confirm(when+' — __DELETE_CONFIRM_JS__')) return;
    deletionPending = true;
    post({ action: 'delete', id: id });
}
function aiSummary() {
    var btn = document.getElementById('aiBtn');
    btn.textContent = '__AI_SUMMARIZING_JS__';
    btn.disabled = true;
    btn.style.opacity = '0.5';
    setStatus('__AI_STATUS_JS__', false);
    post({ action: 'ai-summary' });
}
function summaryResult(ok, message) {
    var btn = document.getElementById('aiBtn');
    btn.textContent = '__AI_SUMMARY_JS__';
    btn.disabled = false;
    btn.style.opacity = '1';
    setStatus(message || (ok ? '__AI_ADDED_JS__' : '__AI_FAILED_JS__'), !ok);
}
document.getElementById('inp').focus();
</script>
</body></html>]]
    template = replaceTokens(template, {
        LANG = escapeHTML(L("locale_code")),
        PROJECT_TITLE = escapeHTML(L("projectnotes_title")),
        AI_SUMMARY = escapeHTML(L("projectnotes_ai_summary")),
        INPUT_LABEL = escapeHTML(L("projectnotes_input_label")),
        INPUT_PLACEHOLDER = escapeHTML(L("notes_input_placeholder")),
        TOO_LONG_JS = jsEscape(L("notes_too_long")),
        MAX_NOTE_LENGTH = tostring(MAX_NOTE_LENGTH),
        MAX_NOTE_CODE_UNITS = tostring(MAX_NOTE_LENGTH * 2),
        ADD = escapeHTML(L("notes_add")),
        SAVING_JS = jsEscape(L("notes_saving")),
        SAVED_JS = jsEscape(L("notes_saved")),
        SAVE_FAILED_JS = jsEscape(L("notes_save_failed")),
        DELETE_CONFIRM_JS = jsEscape(L("notes_delete_confirm")),
        AI_SUMMARIZING_JS = jsEscape(L("projectnotes_ai_summarizing")),
        AI_STATUS_JS = jsEscape(L("projectnotes_ai_status")),
        AI_SUMMARY_JS = jsEscape(L("projectnotes_ai_summary")),
        AI_ADDED_JS = jsEscape(L("projectnotes_ai_added")),
        AI_FAILED_JS = jsEscape(L("projectnotes_ai_failed")),
    })
    return string.format(template, displayName, timelineHTML)
end

-- ── Webview lifecycle ─────────────────────────────────────────────────

--- Refresh only the timeline so draft text, focus and live regions survive.
local function refreshTimeline(webview, projectName)
    if not webview or not projectName then return end
    local timelineHTML = buildTimelineHTML(projectnotes.load(projectName))
    local ok, encoded = pcall(hs.json.encode, timelineHTML)
    if not ok or type(encoded) ~= "string" then return end
    pcall(function() webview:evaluateJavaScript("replaceTimeline(" .. encoded .. ")") end)
end

--- Open (or focus) the project notes panel for the current project.
function openProjectNotes()
    local projectName = _G.trackname or "unsaved_project"

    -- Reopening the same project must preserve the user's draft. A real project
    -- change gets a new document because the header and data context differ.
    if _webview ~= nil then
        local projectChanged = _currentProject ~= projectName
        _currentProject = projectName
        if projectChanged then
            _summaryGeneration = _summaryGeneration + 1
            _summaryPendingProject = nil
            _webview:html(buildNotesHTML(projectName, projectnotes.load(projectName)))
        else
            refreshTimeline(_webview, projectName)
        end
        local w = _webview:hswindow()
        if w then w:focus() end
        return
    end

    _currentProject = projectName

    local screen = hs.screen.mainScreen():frame()
    local frame = windowframe.right(screen, 420, 540, 12, 60)

    -- WKWebView は les:// など非 http(s) のナビゲーションで NSURLErrorUnsupportedURL (-1002) になることがある。
    -- 長いメモでは les://note-add?text=... が URL 長制限を超える。postMessage で Lua に渡す。
    _notesUC = hs.webview.usercontent.new("lesProjectNotes")
    _notesUC:setCallback(function(msg)
        if type(msg) ~= "table" then return end
        local body = msg.body
        -- JS sends JSON.stringify(...); also accept a bridged table for safety
        if type(body) == "string" then
            local ok, decoded = pcall(hs.json.decode, body)
            if ok and type(decoded) == "table" then
                body = decoded
            else
                print("[projectnotes] message decode failed:", tostring(body):sub(1, 120))
                return
            end
        end
        if type(body) ~= "table" then return end
        local action = body.action
        if not _currentProject then return end

        if action == "add" then
            local text = body.text
            if utf8text.isWithinLimit(text, MAX_NOTE_LENGTH) then
                local saved = projectnotes.addNote(_currentProject, text)
                if saved then
                    if _webview then
                        _webview:evaluateJavaScript(string.format(
                            "noteOperationResult(true,'%s')", jsEscape(L("notes_saved"))))
                        refreshTimeline(_webview, _currentProject)
                    end
                elseif _webview then
                    _webview:evaluateJavaScript(string.format(
                        "noteOperationResult(false,'%s')", jsEscape(L("notes_save_failed_preserved"))))
                end
            elseif _webview then
                _webview:evaluateJavaScript(string.format(
                    "noteOperationResult(false,'%s')", jsEscape(L("notes_too_long"))))
            end
        elseif action == "delete" then
            local identifier = type(body.id) == "string" and body.id or tonumber(body.ts)
            if type(identifier) == "string" or type(identifier) == "number" then
                local deleted = projectnotes.deleteNote(_currentProject, identifier)
                if deleted then
                    refreshTimeline(_webview, _currentProject)
                    _webview:evaluateJavaScript(string.format(
                        "deleteOperationResult(true,'%s')", jsEscape(L("notes_deleted"))))
                elseif _webview then
                    _webview:evaluateJavaScript(string.format(
                        "deleteOperationResult(false,'%s')", jsEscape(L("notes_delete_failed"))))
                end
            else
                print("[projectnotes] delete ignored: invalid ts:", tostring(body.ts))
                if _webview then
                    _webview:evaluateJavaScript(string.format(
                        "deleteOperationResult(false,'%s')", jsEscape(L("notes_delete_failed"))))
                end
            end
        elseif action == "ai-summary" then
            local projectAtRequest = _currentProject
            local requestWebview = _webview
            if _summaryPendingProject == projectAtRequest then
                requestWebview:evaluateJavaScript(string.format(
                    "summaryResult(false,'%s')", jsEscape(L("projectnotes_summary_already_pending"))))
                return
            end
            _summaryGeneration = _summaryGeneration + 1
            local requestGeneration = _summaryGeneration
            _summaryPendingProject = projectAtRequest
            if not _openai then _openai = require("ai.openai") end
            if not _openai.isConfigured() then
                _summaryPendingProject = nil
                HSMakeAlert(programName,
                    L("projectnotes_summary_config_required"),
                    true, "warning")
                if requestWebview == _webview then
                    requestWebview:evaluateJavaScript(string.format(
                        "summaryResult(false,'%s')", jsEscape(L("projectnotes_summary_config_short"))))
                end
                return
            end
            local notes = projectnotes.load(projectAtRequest)
            if #notes == 0 then
                _summaryPendingProject = nil
                if requestWebview == _webview then
                    requestWebview:evaluateJavaScript(string.format(
                        "summaryResult(false,'%s')", jsEscape(L("projectnotes_summary_no_notes"))))
                end
                return
            end
            local lines = {}
            for _, n in ipairs(notes) do
                lines[#lines + 1] = os.date("%Y/%m/%d %H:%M", n.timestamp) .. " - " .. n.body
            end
            local prompt = string.format(L("projectnotes_summary_user_prompt"),
                projectAtRequest or "", table.concat(lines, "\n"))
            _openai.chat(
                {
                    { role = "system", content = L("projectnotes_summary_system_prompt") },
                    { role = "user",   content = prompt },
                },
                function(reply, err)
                    if requestGeneration ~= _summaryGeneration then return end
                    _summaryPendingProject = nil
                    if err then
                        print("[projectnotes] AI summary failed: " .. tostring(err))
                        if requestWebview == _webview and _currentProject == projectAtRequest then
                            requestWebview:evaluateJavaScript(string.format(
                                "summaryResult(false,'%s')", jsEscape(L("projectnotes_summary_request_failed"))))
                        end
                        return
                    end
                    if type(reply) ~= "string" or reply == "" then
                        if requestWebview == _webview and _currentProject == projectAtRequest then
                            requestWebview:evaluateJavaScript(string.format(
                                "summaryResult(false,'%s')", jsEscape(L("projectnotes_summary_empty_response"))))
                        end
                        return
                    end
                    local saved = projectnotes.addNote(projectAtRequest, L("projectnotes_ai_prefix") .. reply)
                    if requestWebview == _webview and _currentProject == projectAtRequest then
                        if saved then
                            requestWebview:evaluateJavaScript(string.format(
                                "summaryResult(true,'%s')", jsEscape(L("projectnotes_ai_added"))))
                            refreshTimeline(requestWebview, projectAtRequest)
                        else
                            requestWebview:evaluateJavaScript(string.format(
                                "summaryResult(false,'%s')", jsEscape(L("projectnotes_summary_save_failed"))))
                        end
                    end
                end
            )
        end
    end)

    _webview = hs.webview.new(frame, { developerExtrasEnabled = false }, _notesUC)
    if _webview == nil then return end
    local currentWebview = _webview
    _webview:deleteOnClose(true)
    _webview:windowStyle({ "titled", "closable", "resizable", "nonactivating" })
    _webview:windowTitle(L("projectnotes_title"))
    _webview:level(hs.drawing.windowLevels.floating)
    _webview:allowTextEntry(true)
    _webview:html(buildNotesHTML(projectName, projectnotes.load(projectName)))

    _webview:windowCallback(function(action)
        if action == "closing" and _webview == currentWebview then
            _summaryGeneration = _summaryGeneration + 1
            _summaryPendingProject = nil
            _webview = nil
            _notesUC = nil
            _currentProject = nil
        end
    end)

    _webview:show()
end

return projectnotes

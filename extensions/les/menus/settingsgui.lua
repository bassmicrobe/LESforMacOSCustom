--  SPDX-License-Identifier: MIT
--
--  Copyright (c) 2019-2023 LESforMacOS authors, see AUTHORS.txt
--  for a list
--
--  Distributed under the MIT software license, see the accompanying
--  file COPYING.txt or visit https://opensource.org/license/mit/

-- HTML/CSS settings panel replacing direct settings.ini editing.
local settingsWebview = nil
local settingsUC = nil
local pendingReloadTimer = nil
local windowframe = require("util.windowframe")

local function sLog(msg)
    -- Only log in debug mode (avoids unbounded debug.log growth). Secure the
    -- file to 600 on creation: it lives in ~/.les alongside the API key and the
    -- default umask would otherwise leave it group/other-readable.
    if _G.enabledebug ~= 1 then return end
    local path = ScriptUserPath .. "/debug.log"
    local pre = io.open(path, "r")
    local existed = pre ~= nil
    if pre then pre:close() end
    local f = io.open(path, "a")
    if not f then return end
    f:write(os.date("[%H:%M:%S][settingsgui] ") .. tostring(msg) .. "\n")
    f:close()
    if not existed and type(SetSecureFileMode) == "function" then SetSecureFileMode(path) end
end

-- Distinct marker the GUI puts in the openaikey input when the user clicks '削除'.
-- It can never collide with a real OpenAI key (those start with 'sk-' and never
-- contain '__'). collectGuiPatchFromData() maps it to the '未設定' default sentinel.
local CLEAR_OPENAIKEY_MARKER = "__CLEAR_OPENAIKEY__"

-- Binary settings definition: keep locale keys so every HTML build reflects
-- the current _G.uiLanguage value.
local TOGGLE_DEFS = {
    { key = "autoadd", labelKey = "settings_toggle_autoadd_label", descKey = "settings_toggle_autoadd_desc" },
    { key = "resettobrowserbookmark", labelKey = "settings_toggle_resettobrowserbookmark_label", descKey = "settings_toggle_resettobrowserbookmark_desc" },
    { key = "disableloop", labelKey = "settings_toggle_disableloop_label", descKey = "settings_toggle_disableloop_desc" },
    { key = "saveasnewver", labelKey = "settings_toggle_saveasnewver_label", descKey = "settings_toggle_saveasnewver_desc" },
    { key = "altgrmarker", labelKey = "settings_toggle_altgrmarker_label", descKey = "settings_toggle_altgrmarker_desc" },
    { key = "double0todelete", labelKey = "settings_toggle_double0todelete_label", descKey = "settings_toggle_double0todelete_desc" },
    { key = "absolutereplace", labelKey = "settings_toggle_absolutereplace_label", descKey = "settings_toggle_absolutereplace_desc" },
    { key = "ctrlabsoluteduplicate", labelKey = "settings_toggle_ctrlabsoluteduplicate_label", descKey = "settings_toggle_ctrlabsoluteduplicate_desc" },
    { key = "enableclosewindow", labelKey = "settings_toggle_enableclosewindow_label", descKey = "settings_toggle_enableclosewindow_desc" },
    { key = "vstshortcuts", labelKey = "settings_toggle_vstshortcuts_label", descKey = "settings_toggle_vstshortcuts_desc" },
    { key = "dynamicreload", labelKey = "settings_toggle_dynamicreload_label", descKey = "settings_toggle_dynamicreload_desc" },
    { key = "texticon", labelKey = "settings_toggle_texticon_label", descKey = "settings_toggle_texticon_desc" },
    { key = "addtostartup", labelKey = "settings_toggle_addtostartup_label", descKey = "settings_toggle_addtostartup_desc" },
    { key = "launchwithlive", labelKey = "settings_toggle_launchwithlive_label", descKey = "settings_toggle_launchwithlive_desc" },
    { key = "notifyexport", labelKey = "settings_toggle_notifyexport_label", descKey = "settings_toggle_notifyexport_desc" },
    { key = "notifyhourly", labelKey = "settings_toggle_notifyhourly_label", descKey = "settings_toggle_notifyhourly_desc" },
    { key = "enabledebug", labelKey = "settings_toggle_enabledebug_label", descKey = "settings_toggle_enabledebug_desc" },
    { key = "checksanity", labelKey = "settings_toggle_checksanity_label", descKey = "settings_toggle_checksanity_desc" },
}

-- AI text settings: {key, labelKey, descKey, placeholderKey}
local AI_DEFS = {
    { key = "openaikey", labelKey = "settings_ai_key_label", descKey = "settings_ai_key_desc", placeholderKey = "settings_ai_key_placeholder" },
    { key = "openaimodel", labelKey = "settings_ai_model_label", descKey = "settings_ai_model_desc", placeholderKey = "settings_ai_model_placeholder" },
}

-- Numeric settings definition: {key, labelKey, descKey, step, min, max}
local NUMERIC_DEFS = {
    { key = "loadspeed", labelKey = "settings_numeric_loadspeed_label", descKey = "settings_numeric_loadspeed_desc", step = "0.1", min = "0.1", max = "10.0" },
    { key = "bookmarkx", labelKey = "settings_numeric_bookmarkx_label", descKey = "settings_numeric_bookmarkx_desc", step = "1", min = "0", max = "9999" },
    { key = "bookmarky", labelKey = "settings_numeric_bookmarky_label", descKey = "settings_numeric_bookmarky_desc", step = "1", min = "0", max = "9999" },
}

-- Read the raw (pre-parse) pianorollmacro character from settings.ini
local function getRawPianorollMacro()
    local lines = {}
    local ok = pcall(function() fileToTable(GetDataPath(ConfigFile), lines) end)
    if not ok then return "`" end
    for _, line in ipairs(lines) do
        if type(line) == "string"
           and line:find("pianorollmacro")
           and line:find("=")
           and not line:find("^%s*;")
        then
            local val = line:match("=%s*(.*)")
            if val then
                return val:match("^%s*(.-)%s*$") or "`"
            end
        end
    end
    return "`"
end

--- Escape for use inside double-quoted HTML attributes (settings values, macro key).
---@param str string|number|nil
---@return string
local function escapeHtmlAttr(str)
    return (tostring(str or ""):gsub("&", "&amp;"):gsub('"', "&quot;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function jsLiteral(value)
    local text = tostring(value or "")
    local ok, encoded = pcall(hs.json.encode, text)
    if ok and type(encoded) == "string" then return encoded end
    text = text:gsub("\\", "\\\\"):gsub("'", "\\'")
        :gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("<", "\\x3c"):gsub(">", "\\x3e")
    return "'" .. text .. "'"
end

-- Build the complete offline HTML document for the settings panel.
local function buildSettingsHTML()
    local cssPath = BundleResourcePath .. "/assets/settings-tw.css"
    local css = ""
    local f = io.open(cssPath, "r")
    if f then
        css = f:read("*a")
        f:close()
    end

    local toggleRows = {}
    for _, s in ipairs(TOGGLE_DEFS) do
        local val = 0
        if settingsManager and settingsManager[s.key] then
            val = settingsManager[s.key]["value"] or 0
        end
        local checked = (tonumber(val) == 1) and " checked" or ""
        table.insert(toggleRows, table.concat({
            '<div class="settings-row flex items-center justify-between py-2.5 border-b border-surface-border gap-4 last:border-b-0">',
            '  <div class="flex-1 min-w-0">',
            '    <label id="label-', s.key, '" for="setting-', s.key, '" class="block font-medium text-label">', escapeHtmlAttr(L(s.labelKey)), '</label>',
            '    <span id="desc-', s.key, '" class="block text-[11px] text-label-dim mt-px">', escapeHtmlAttr(L(s.descKey)), '</span>',
            '  </div>',
            '  <label class="relative inline-block w-[42px] h-6 shrink-0">',
            '    <input id="setting-', s.key, '" type="checkbox" data-key="', s.key, '"', checked,
            ' aria-labelledby="label-', s.key, '" aria-describedby="desc-', s.key,
            '" onchange="markDirty()" style="position:absolute;inset:0;opacity:0;cursor:pointer;margin:0;width:100%;height:100%;">',
            '    <span class="toggle-knob absolute inset-0 bg-surface-hover rounded-full pointer-events-none transition-colors duration-200"></span>',
            '  </label>',
            '</div>',
        }, ""))
    end

    local numericRows = {}
    for _, s in ipairs(NUMERIC_DEFS) do
        local val = 0
        if settingsManager and settingsManager[s.key] then
            val = settingsManager[s.key]["value"] or 0
        end
        table.insert(numericRows, table.concat({
            '<div class="settings-row flex items-center justify-between py-2.5 border-b border-surface-border gap-4 last:border-b-0">',
            '  <div class="flex-1 min-w-0">',
            '    <label id="label-', s.key, '" for="setting-', s.key, '" class="block font-medium text-label">', escapeHtmlAttr(L(s.labelKey)), '</label>',
            '    <span id="desc-', s.key, '" class="block text-[11px] text-label-dim mt-px">', escapeHtmlAttr(L(s.descKey)), '</span>',
            '  </div>',
            '  <input id="setting-', s.key, '" type="number" aria-describedby="desc-', s.key, '"',
            '    class="w-[88px] shrink-0 bg-input-bg border border-input-border rounded-lg text-[#e5e5ea] px-2.5 py-1.5 text-[13px] text-right appearance-textfield outline-none focus:border-accent"',
            '    data-key="', s.key, '" value="', tostring(val), '"',
            '    step="', s.step, '" min="', s.min, '" max="', s.max, '"',
            '    oninput="markDirty()">',
            '</div>',
        }, ""))
    end

    local macroRaw = getRawPianorollMacro()
    local macroRow = table.concat({
        '<div class="settings-row flex items-center justify-between py-2.5 border-b border-surface-border gap-4 last:border-b-0">',
        '  <div class="flex-1 min-w-0">',
        '    <label for="setting-pianorollmacro" class="block font-medium text-label">', escapeHtmlAttr(L("settings_macro_label")), '</label>',
        '    <span id="desc-pianorollmacro" class="block text-[11px] text-label-dim mt-px">', escapeHtmlAttr(L("settings_macro_desc")), '</span>',
        '  </div>',
        '  <input id="setting-pianorollmacro" type="text" maxlength="1" aria-describedby="desc-pianorollmacro"',
        '    class="w-[88px] shrink-0 bg-input-bg border border-input-border rounded-lg text-[#e5e5ea] px-2.5 py-1.5 text-[13px] text-left outline-none focus:border-accent"',
        '    data-key="pianorollmacro" value="', escapeHtmlAttr(macroRaw), '"',
        '    oninput="markDirty()">',
        '</div>',
    }, "")

    local aiRows = {}
    for _, s in ipairs(AI_DEFS) do
        local val = ""
        if settingsManager and settingsManager[s.key] then
            val = settingsManager[s.key]["value"] or ""
        end
        -- '未設定' sentinel must never reach the DOM; display it (and an unconfigured key) as empty.
        if tostring(val) == "未設定" then
            val = ""
        end
        local inputClass =
            "w-[200px] shrink-0 bg-input-bg border border-input-border rounded-lg text-[#e5e5ea] px-2.5 py-1.5 text-[13px] outline-none focus:border-accent"
        local renderVal = val
        local placeholder = L(s.placeholderKey)
        if s.key == "openaikey" then
            -- SECURITY: never emit the real API key into the DOM. Blank field == "keep existing".
            renderVal = ""
            local hasKey = (val ~= nil and val ~= "" and tostring(val) ~= "未設定")
            placeholder = hasKey and L("settings_ai_key_saved_placeholder") or L("settings_ai_key_placeholder")
        end
        -- For the API key, offer a '削除' affordance: a blank field means
        -- "keep existing", so removing the key needs an explicit clear marker.
        local clearBtn = ""
        local inputType = "text"
        local inputHandler = "markDirty()"
        if s.key == "openaikey" then
            inputType = "password"
            inputHandler = "apiKeyChanged(this)"
            clearBtn = table.concat({
                '    <button type="button"',
                '      class="shrink-0 bg-transparent text-accent-red border border-input-border rounded-lg px-2 py-1.5 text-[12px] cursor-pointer hover:border-accent-red"',
                '      aria-describedby="desc-openaikey" onclick="clearApiKey(this)">', escapeHtmlAttr(L("settings_ai_key_clear")), '</button>',
            }, "\n")
        end
        table.insert(aiRows, table.concat({
            '<div class="settings-row flex items-center justify-between py-2.5 border-b border-surface-border gap-4 last:border-b-0">',
            '  <div class="flex-1 min-w-0">',
            '    <label id="label-', s.key, '" for="setting-', s.key, '" class="block font-medium text-label">', escapeHtmlAttr(L(s.labelKey)), '</label>',
            '    <span id="desc-', s.key, '" class="block text-[11px] text-label-dim mt-px">', escapeHtmlAttr(L(s.descKey)), '</span>',
            '  </div>',
            '  <div class="settings-control flex items-center gap-2 shrink-0">',
            '  <input id="setting-', s.key, '" type="', inputType,
            '" aria-describedby="desc-', s.key,
            '" spellcheck="false" autocomplete="off" autocorrect="off" autocapitalize="off"',
            '    class="', inputClass, '"',
            '    data-key="', s.key, '" value="', escapeHtmlAttr(renderVal), '"',
            '    placeholder="', escapeHtmlAttr(placeholder), '"',
            '    oninput="', inputHandler, '">',
            clearBtn,
            '  </div>',
            '</div>',
        }, ""))
    end

    -- JSON-encode the clear marker so it is a safe, properly-quoted JS string literal.
    local CLEAR_MARKER_JS = "'__CLEAR_OPENAIKEY__'"
    local okEnc, encMarker = pcall(hs.json.encode, CLEAR_OPENAIKEY_MARKER)
    if okEnc and type(encMarker) == "string" then
        CLEAR_MARKER_JS = encMarker
    end
    local js = table.concat({
        "var dirty = false;",
        "var saving = false;",
        "function markDirty() {",
        "  setDirty(true);",
        "}",
        "// API-key clear affordance: a blank field means 'keep existing',",
        "// so clearing the key needs an explicit marker Lua maps to the default sentinel.",
        "function clearApiKey(btn) {",
        "  var el = document.querySelector('[data-key=\"openaikey\"]');",
        "  if (!el) return;",
        "  el.value = '';",
        "  el.dataset.clearRequested = 'true';",
        "  el.placeholder = " .. jsLiteral(L("settings_ai_key_clear_on_save")) .. ";",
        "  btn.textContent = " .. jsLiteral(L("settings_ai_key_clear_pending")) .. ";",
        "  btn.disabled = true;",
        "  markDirty();",
        "}",
        "function apiKeyChanged(el) {",
        "  delete el.dataset.clearRequested;",
        "  var btn = el.parentElement.querySelector('button');",
        "  if (btn) { btn.disabled = false; btn.textContent = " .. jsLiteral(L("settings_ai_key_clear")) .. "; }",
        "  markDirty();",
        "}",
        "function showToast(text, ok) {",
        "  var t = document.getElementById('toast');",
        "  if (!t) return;",
        "  t.textContent = text;",
        "  t.classList.remove('bg-accent-green', 'bg-accent-red', 'text-black', 'text-white');",
        "  if (ok) { t.classList.add('bg-accent-green', 'text-black'); }",
        "  else { t.classList.add('bg-accent-red', 'text-white'); }",
        "  t.classList.remove('opacity-0');",
        "  t.classList.add('opacity-100');",
        "}",
        "function hideToast() {",
        "  var t = document.getElementById('toast');",
        "  if (!t) return;",
        "  t.classList.remove('opacity-100');",
        "  t.classList.add('opacity-0');",
        "}",
        "function setDirty(d) {",
        "  dirty = d;",
        "  var btn = document.getElementById('saveBtn');",
        "  if (!btn) return;",
        "  btn.disabled = !d || saving;",
        "  if (d && !saving) {",
        "    btn.classList.remove('opacity-40', 'pointer-events-none');",
        "    btn.classList.add('opacity-100', 'cursor-pointer');",
        "  } else {",
        "    btn.classList.add('opacity-40', 'pointer-events-none');",
        "    btn.classList.remove('opacity-100', 'cursor-pointer');",
        "  }",
        "}",
        "// Called from Lua via evaluateJavaScript once the write outcome is known.",
        "function saveResult(ok, message) {",
        "  // Bump the save token so a real Lua reply cancels any pending watchdog timer.",
        "  window._saveTok = (window._saveTok||0)+1;",
        "  saving = false;",
        "  if (ok) {",
        "    showToast(message || " .. jsLiteral(L("settings_save_success")) .. ", true);",
        "    setDirty(false);",
        "  } else {",
        "    showToast(message || " .. jsLiteral(L("settings_save_failed")) .. ", false);",
        "    setDirty(true);",
        "    setTimeout(hideToast, 3000);",
        "  }",
        "}",
        "function saveSettings() {",
        "  if (!dirty || saving) return;",
        "  var invalid = Array.prototype.find.call(document.querySelectorAll('input'), function(el) { return !el.checkValidity(); });",
        "  if (invalid) { invalid.focus(); showToast(" .. jsLiteral(L("settings_validation_failed")) .. ", false); return; }",
        "  var settings = {};",
        "  document.querySelectorAll('[data-key]').forEach(function(el) {",
        "    var k = (el.getAttribute('data-key') || '').trim();",
        "    if (!k) return;",
        "    if (el.type === 'checkbox') {",
        "      settings[k] = el.checked ? '1' : '0';",
        "    } else {",
        "      settings[k] = (k === 'openaikey' && el.dataset.clearRequested === 'true') ? " .. CLEAR_MARKER_JS .. " : el.value;",
        "    }",
        "  });",
        "  // Always stringify: WKWebView → Lua is most reliable as JSON text (nested dicts can break pairs()/keys).",
        "  window.webkit.messageHandlers.lesmessages.postMessage(JSON.stringify({ action: 'save', data: settings }));",
        "  saving = true;",
        "  // Neutral 'saving' state; the Lua callback reports success/failure via saveResult().",
        "  var btn = document.getElementById('saveBtn');",
        "  if (btn) { btn.classList.add('opacity-40', 'pointer-events-none'); btn.classList.remove('opacity-100', 'cursor-pointer'); }",
        "  showToast(" .. jsLiteral(L("settings_saving")) .. ", true);",
        "  // Watchdog: a dropped/garbled WK bridge message must not hang the UI forever.",
        "  // A real Lua reply bumps window._saveTok via saveResult(), which cancels this.",
        "  window._saveTok = (window._saveTok||0)+1; var t = window._saveTok;",
        "  setTimeout(function(){ if (window._saveTok === t) saveResult(false, " .. jsLiteral(L("settings_no_response")) .. "); }, 5000);",
        "}",
        "window.addEventListener('beforeunload', function(e) { if (dirty && !saving) { e.preventDefault(); e.returnValue = ''; } });",
    }, "\n")

    return table.concat({
        "<!DOCTYPE html><html lang='" .. escapeHtmlAttr(L("locale_code")) .. "'><head>",
        "<meta charset='UTF-8'>",
        "<meta name='viewport' content='width=device-width,initial-scale=1'>",
        "<style>", css,
        "\n.bg-accent-red { background-color: #ff453a; }",
        "\n.text-accent-red { color: #ff453a; }",
        "\n.hover\\:border-accent-red:hover { border-color: #ff453a; }",
        "\nhtml { color-scheme: dark; }",
        "\nbutton:focus-visible, input:focus-visible { outline: 2px solid #64b5ff; outline-offset: 2px; }",
        "\ninput[type='checkbox']:focus-visible + .toggle-knob { outline: 2px solid #64b5ff; outline-offset: 3px; }",
        "\n@media (max-width: 460px) { .settings-row { align-items: stretch; flex-direction: column; gap: .5rem; } .settings-control { width: 100%; } .settings-control input { flex: 1; min-width: 0; } }\n</style>",
        "</head>",
        "<body class='bg-surface text-[#e5e5ea] text-[13px] leading-snug font-[-apple-system,BlinkMacSystemFont,sans-serif]'>",

        "<div class='sticky top-0 z-50 bg-surface-header border-b border-surface-border flex items-center justify-between px-5 py-3.5'>",
        "  <div>",
        "    <h1 class='text-[15px] font-semibold text-white'>", escapeHtmlAttr(L("settings_title")), "</h1>",
        "    <p class='text-[11px] text-label-muted mt-0.5'>Live Enhancement Suite Custom</p>",
        "  </div>",
        "  <button type='button' id='saveBtn' disabled onclick='saveSettings()'",
        "    class='bg-accent text-white border-none rounded-lg px-4 py-1.5 text-[13px] font-medium transition-all duration-150 opacity-40 pointer-events-none hover:bg-accent-hover'>",
        "    ", escapeHtmlAttr(L("settings_save_apply")),
        "  </button>",
        "</div>",

        "<div class='px-5 pt-2 pb-16'>",
        "  <section aria-labelledby='settings-section-toggles'>",
        "  <h2 id='settings-section-toggles' class='text-[11px] font-semibold text-label-muted tracking-wider uppercase pt-4 pb-1.5 border-b border-surface-border mb-0.5'>", escapeHtmlAttr(L("settings_section_toggles")), "</h2>",
        table.concat(toggleRows, "\n"),
        "  </section>",

        "  <section aria-labelledby='settings-section-timing'>",
        "  <h2 id='settings-section-timing' class='text-[11px] font-semibold text-label-muted tracking-wider uppercase pt-4 pb-1.5 border-b border-surface-border mb-0.5'>", escapeHtmlAttr(L("settings_section_timing")), "</h2>",
        table.concat(numericRows, "\n"),
        "  </section>",

        "  <section aria-labelledby='settings-section-mapping'>",
        "  <h2 id='settings-section-mapping' class='text-[11px] font-semibold text-label-muted tracking-wider uppercase pt-4 pb-1.5 border-b border-surface-border mb-0.5'>", escapeHtmlAttr(L("settings_section_mapping")), "</h2>",
        macroRow,
        "  </section>",

        "  <section aria-labelledby='settings-section-ai'>",
        "  <h2 id='settings-section-ai' class='text-[11px] font-semibold text-label-muted tracking-wider uppercase pt-4 pb-1.5 border-b border-surface-border mb-0.5'>", escapeHtmlAttr(L("settings_section_ai")), "</h2>",
        table.concat(aiRows, "\n"),
        "  </section>",
        "</div>",

        "<div class='fixed bottom-5 left-0 right-0 text-center pointer-events-none'>",
        "  <span id='toast' role='status' aria-live='polite' class='inline-block bg-accent-green text-black px-5 py-1.5 rounded-full font-semibold text-[13px] opacity-0 transition-opacity duration-300'>", escapeHtmlAttr(L("settings_save_success")), "</span>",
        "</div>",

        "<script>", js, "</script>",
        "</body></html>",
    }, "\n")
end

--- WKWebView may deliver msg.body as a JSON string or bridged NSDictionary.
local function decodeWebviewMessageBody(body)
    if type(body) == "table" then
        return body
    end
    if type(body) == "string" then
        local ok, t = pcall(hs.json.decode, body)
        if ok and type(t) == "table" then
            return t
        end
        -- Do NOT log the payload contents: the settings save body carries the
        -- OpenAI API key. Log only the length for diagnostics.
        print("[settingsgui] save: json decode failed (payload withheld, length="
            .. tostring(#tostring(body or "")) .. ")")
        return nil
    end
    print("[settingsgui] save: unexpected message body type:", type(body))
    return nil
end

--- JSON round-trip forces plain Lua tables with string keys (NSDictionary bridges can confuse pairs()).
---@param t table|nil
---@return table|nil
local function canonicalizeWebviewTable(t)
    if type(t) ~= "table" then
        return nil
    end
    local ok, j = pcall(hs.json.encode, t)
    if not ok or type(j) ~= "string" then
        return t
    end
    local ok2, dec = pcall(hs.json.decode, j)
    if ok2 and type(dec) == "table" then
        return dec
    end
    return t
end

--- If `data` arrived as a JSON string (double-encoding), decode to a table.
---@param data any
---@return table|nil
local function normalizeSettingsDataTable(data)
    if type(data) == "table" then
        return data
    end
    if type(data) == "string" then
        local ok, t = pcall(hs.json.decode, data)
        if ok and type(t) == "table" then
            return t
        end
    end
    return nil
end

--- Build the patch map using known GUI keys first (avoids lost keys when WK bridge tables do not iterate).
---@param data table
---@return table<string, string|number|boolean>
local function collectGuiPatchFromData(data)
    if type(data) ~= "table" or not settingsManager then
        return {}
    end
    local canon = canonicalizeWebviewTable(data) or data
    local dbgKeys = {}
    for k in pairs(data) do dbgKeys[#dbgKeys+1] = tostring(k) end
    table.sort(dbgKeys)
    sLog("data actual keys: " .. table.concat(dbgKeys, ","))
    local patch = {}
    local function pullKey(k)
        if k == "autoadd" or k == "pianorollmacro" then
            local smv = settingsManager and settingsManager[k]
            sLog("pullKey(" .. k .. "): sm=" .. type(smv) .. " canon=" .. tostring(canon[k]) .. " data=" .. tostring(data[k]))
        end
        if type(k) ~= "string" or type(settingsManager[k]) ~= "table" then
            sLog("pullKey EARLY1 k=" .. tostring(k))
            return
        end
        local v = canon[k]
        if v == nil then
            v = data[k]
        end
        if v == nil then
            sLog("pullKey EARLY2 k=" .. tostring(k) .. " v=nil")
            return
        end
        if k == "openaikey" then
            local trimmed = tostring(v):gsub("^%s*(.-)%s*$", "%1")
            if trimmed == CLEAR_OPENAIKEY_MARKER then
                -- Explicit '削除' click: clear the key by writing the default sentinel.
                patch[k] = "未設定"
                return
            end
            -- Blank/whitespace-only means "keep existing"; '未設定' sentinel must never enter the patch.
            if trimmed == "" or trimmed == "未設定" then
                return
            end
        end
        patch[k] = v
    end
    for _, row in ipairs(TOGGLE_DEFS) do
        pullKey(row.key)
    end
    for _, row in ipairs(NUMERIC_DEFS) do
        pullKey(row.key)
    end
    for _, row in ipairs(AI_DEFS) do
        pullKey(row.key)
    end
    pullKey("pianorollmacro")
    for k in pairs(canon) do
        if type(k) == "string" and type(settingsManager[k]) == "table" and patch[k] == nil then
            -- Route through pullKey so openaikey blank/sentinel handling applies here too.
            pullKey(k)
        end
    end
    return patch
end

--- Report a save outcome to the webview's JS saveResult() handler.
local function reportSaveResult(ok, message)
    if settingsWebview == nil then
        return
    end
    local okFlag = ok and "true" or "false"
    -- JSON-encode the message so quotes/newlines cannot break out of the JS string literal.
    local msgJson = "''"
    if message ~= nil then
        local encOk, enc = pcall(hs.json.encode, tostring(message))
        if encOk and type(enc) == "string" then
            msgJson = enc
        end
    end
    local jsCode = "if (typeof saveResult === 'function') { saveResult(" .. okFlag .. ", " .. msgJson .. "); }"
    pcall(function()
        settingsWebview:evaluateJavaScript(jsCode)
    end)
end

--- Report an intermediate persistence milestone without changing dirty/saving
--- state. `showToast` writes into the existing aria-live status region.
---@param message string
local function reportSaveProgress(message)
    if settingsWebview == nil then return end
    local encoded = "''"
    local okEncode, value = pcall(hs.json.encode, tostring(message))
    if okEncode and type(value) == "string" then encoded = value end
    local jsCode = "if (typeof showToast === 'function') { showToast(" .. encoded .. ", true); }"
    pcall(function()
        settingsWebview:evaluateJavaScript(jsCode)
    end)
end

--- Best-effort recovery after reloadLES() fails. Each step is evaluated
--- independently so a partial recovery can never be mistaken for success.
---@return boolean ok
---@return string|nil failedStep
---@return any errorValue
local function recoverSettingsState()
    if type(settingsManager) ~= "table" then
        return false, "settingsManager", "unavailable"
    end
    for _, methodName in ipairs({"init", "parse", "map"}) do
        local method = settingsManager[methodName]
        if type(method) ~= "function" then
            return false, methodName, "method unavailable"
        end
        local ok, result = pcall(method, settingsManager)
        if not ok then
            return false, methodName, result
        end
        if result == false then
            return false, methodName, "returned false"
        end
    end
    return true, nil, nil
end

--- Report that persistence succeeded but the running application was not fully
--- updated. The panel intentionally remains open so the saved draft and retry
--- affordance stay visible.
---@param reloadError any
local function reportRuntimeApplyFailure(reloadError)
    print("[settingsgui] reloadLES() failed after settings file save: " .. tostring(reloadError))
    local recovered, failedStep, recoveryError = recoverSettingsState()
    local liveMessage = L("settings_live_apply_failed")
    local alertMessage = L("settings_alert_apply_failed_intro") .. "\n"

    if recovered then
        alertMessage = alertMessage
            .. L("settings_alert_recovery_succeeded") .. "\n"
    else
        liveMessage = liveMessage .. L("settings_live_recovery_failed_suffix")
        alertMessage = alertMessage
            .. string.format(L("settings_alert_recovery_failed"), tostring(failedStep or L("settings_unknown")))
            .. "\n"
        print(
            "[settingsgui] recovery failed at "
                .. tostring(failedStep)
                .. ": "
                .. tostring(recoveryError)
        )
    end

    reportSaveResult(false, liveMessage)
    HSMakeAlert(
        programName,
        alertMessage .. L("settings_alert_retry_instruction"),
        true,
        "critical"
    )
end


--- Open the settings GUI webview panel.
--- Saves via settingsManager:writeFromGui() then calls reloadLES().
function openSettingsGUI()
    -- Cancel any pending teardown so reopening within the reload window is never destroyed.
    if pendingReloadTimer ~= nil then
        pcall(function() pendingReloadTimer:stop() end)
        pendingReloadTimer = nil
    end
    -- Preserve unsaved form values when the settings command is invoked again.
    -- If the native object is stale, fall through and recreate it safely.
    if settingsWebview ~= nil then
        local existingWebview = settingsWebview
        local shown, showError = pcall(function()
            existingWebview:show()
            existingWebview:bringToFront()
        end)
        if shown then
            pcall(function()
                local window = existingWebview:hswindow()
                if window then window:focus() end
            end)
            return
        end
        print("[settingsgui] existing webview could not be shown; recreating: " .. tostring(showError))
        pcall(function() existingWebview:delete() end)
        if settingsWebview == existingWebview then
            settingsWebview = nil
            settingsUC = nil
        end
    end
    if settingsUC ~= nil then
        settingsUC = nil
    end

    -- Set up JS→Lua message bridge
    settingsUC = hs.webview.usercontent.new("lesmessages")
    settingsUC:setCallback(function(msg)
        sLog("callback fired: msg type=" .. type(msg))
        if msg == nil then
            sLog("msg is nil, returning")
            return
        end
        local bodyRaw = msg
        if type(msg) == "table" and msg.body ~= nil then
            bodyRaw = msg.body
        end
        sLog("bodyRaw type=" .. type(bodyRaw) .. " len=" .. tostring(type(bodyRaw)=="string" and #bodyRaw or "n/a"))
        local body = decodeWebviewMessageBody(bodyRaw)
        if not body then
            sLog("decodeWebviewMessageBody returned nil")
            return
        end
        body = canonicalizeWebviewTable(body) or body
        local action = body.action or body.Action
        sLog("action=" .. tostring(action))
        if tostring(action or "") ~= "save" then
            return
        end
        local rawData = body.data or body.Data
        local data = normalizeSettingsDataTable(rawData)
        if data == nil and type(rawData) == "table" then
            data = rawData
        end
        sLog("rawData type=" .. type(rawData) .. " data type=" .. type(data))
        if type(data) ~= "table" then
            sLog("ERROR: data is not a table")
            print(
                "[settingsgui] save: body.data missing or not a table (got "
                    .. tostring(type(rawData))
                    .. " / normalized "
                    .. tostring(type(data))
                    .. ")"
            )
            reportSaveResult(false, L("settings_form_unrecognized"))
            HSMakeAlert(
                programName,
                L("settings_form_unrecognized_alert"),
                true,
                "warning"
            )
            return
        end
        local patch = collectGuiPatchFromData(data)
        local dataKeyCount = 0
        for _ in pairs(data) do
            dataKeyCount = dataKeyCount + 1
        end
        local patchKeys = {}
        for k in pairs(patch) do
            patchKeys[#patchKeys + 1] = k
        end
        table.sort(patchKeys)
        local patchCount = #patchKeys
        sLog(string.format("data keys=%d patch keys=%d patch=%s", dataKeyCount, patchCount, table.concat(patchKeys, ",")))
        print(
            string.format(
                "[settingsgui] save: data keys=%d patch keys=%d patch=%s",
                dataKeyCount,
                patchCount,
                table.concat(patchKeys, ",")
            )
        )
        if settingsManager and next(patch) ~= nil then
            print("[settingsgui] save: calling writeFromGui with", patchCount, "keys")
            local okWrite = settingsManager:writeFromGui(patch)
            sLog("writeFromGui result=" .. tostring(okWrite))
            if not okWrite then
                -- Report failure to the GUI: red toast, keep dirty=true and the button enabled.
                reportSaveResult(false, L("settings_write_failed"))
                HSMakeAlert(
                    programName,
                    L("settings_write_failed_alert"),
                    true,
                    "critical"
                )
                return
            end
            reportSaveProgress(L("settings_live_saved_applying"))
            -- Apply settings IMMEDIATELY. reloadLES() runs in-VM (it rebuilds config
            -- in-process and does NOT call hs.reload()), so the apply must not depend
            -- on whether the panel is reopened within the cosmetic teardown window.
            local okReload, reloadResult = pcall(reloadLES)
            sLog("reloadLES result=" .. tostring(okReload) .. " value=" .. tostring(reloadResult))
            -- Verify values made it to memory after reload
            if settingsManager then
                local spot = settingsManager["autoadd"] and settingsManager["autoadd"]["value"]
                sLog("post-reload autoadd in memory=" .. tostring(spot))
            end
            if not okReload or reloadResult == false then
                local reloadError = okReload and "reloadLES returned false" or reloadResult
                reportRuntimeApplyFailure(reloadError)
                return
            end
            -- Full success requires both disk persistence and runtime application.
            reportSaveResult(true, string.format(L("settings_save_applied_count"), patchCount))
            pcall(function()
                if hs.notify then
                    hs.notify
                        .new({ title = programName or "LES", informativeText = L("settings_save_notification") })
                        :send()
                end
            end)
            -- Cosmetic teardown only: delete the webview after a short delay so the
            -- toast stays visible. The apply (reloadLES) already happened above.
            if pendingReloadTimer ~= nil then
                pcall(function() pendingReloadTimer:stop() end)
                pendingReloadTimer = nil
            end
            local wv = settingsWebview
            pendingReloadTimer = hs.timer.doAfter(0.6, function()
                pendingReloadTimer = nil
                if wv then
                    pcall(function() wv:delete() end)
                end
                if settingsWebview == wv then
                    settingsWebview = nil
                    settingsUC = nil
                end
            end)
        else
            -- Empty patch: report failure to the GUI, keep dirty=true and the button enabled.
            reportSaveResult(false, L("settings_no_valid_keys"))
            HSMakeAlert(
                programName,
                L("settings_no_valid_keys_alert"),
                true,
                "warning"
            )
        end
    end)

    -- Center on main screen
    local screen = hs.screen.mainScreen():frame()
    local frame = windowframe.center(screen, 520, 640, 12)

    settingsWebview = hs.webview.new(
        frame,
        {developerExtrasEnabled = false},
        settingsUC
    )
    if settingsWebview == nil then
        settingsUC = nil
        HSMakeAlert(programName, L("settings_open_failed"), true, "warning")
        return
    end
    local currentWebview = settingsWebview
    settingsWebview:deleteOnClose(true)
    settingsWebview:windowCallback(function(action)
        if action == "closing" and settingsWebview == currentWebview then
            settingsWebview = nil
            settingsUC = nil
        end
    end)
    settingsWebview:windowStyle({"titled", "closable", "resizable"})
    settingsWebview:windowTitle(L("settings_title"))
    settingsWebview:allowTextEntry(true)
    settingsWebview:html(buildSettingsHTML())
    settingsWebview:show()
    settingsWebview:bringToFront()
end

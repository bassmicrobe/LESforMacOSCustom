--  SPDX-License-Identifier: MIT
--
--  Copyright (c) 2019-2023 LESforMacOS authors, see AUTHORS.txt
--  for a list
--
--  Distributed under the MIT software license, see the accompanying
--  file COPYING.txt or visit https://opensource.org/license/mit/

-------------------------------------------------
--  Keyboard Shortcut Cheatsheet Overlay       --
--  Toggle with Cmd+Shift+/                    --
-------------------------------------------------

local cheatsheet = {}
local windowframe = require("util.windowframe")

---@type hs.webview|nil
local _webview = nil

-- Shortcut definitions displayed in the overlay.
-- Use { section = "..." } for section headers, { key = "...", desc = "..." } for rows.
local function shortcutDefinitions()
    return {
    { section = L("cheatsheet_section_plugins") },
    { key = L("cheatsheet_key_double_right_click"), desc = L("cheatsheet_desc_plugin_menu") },
    { key = L("cheatsheet_key_shift_double_click"), desc = L("cheatsheet_desc_pianoroll_menu") },
    { key = "Cmd+Shift+H",                   desc = L("cheatsheet_desc_plugin_search") },
    { section = L("cheatsheet_section_pianoroll") },
    { key = L("cheatsheet_key_backquote"),   desc = L("cheatsheet_desc_pianoroll_macro") },
    { section = L("cheatsheet_section_project") },
    { key = "Cmd+B",                         desc = L("cheatsheet_desc_duplicate") },
    { key = "Cmd+Alt+S",                     desc = L("cheatsheet_desc_versioning") },
    { key = "Shift+L / Alt+L",               desc = L("cheatsheet_desc_marker") },
    { key = "Cmd+W",                         desc = L("cheatsheet_desc_close_front_plugin") },
    { key = "Cmd+Alt+W / Cmd+Alt+Esc",       desc = L("cheatsheet_desc_close_all_plugins") },
    { key = "Ctrl+Alt+D",                    desc = L("cheatsheet_desc_abs_drag") },
    { key = "Ctrl+Alt+V",                    desc = L("cheatsheet_desc_abs_paste") },
    { section = L("cheatsheet_section_note_editing") },
    { key = L("cheatsheet_key_alt_click"),   desc = L("cheatsheet_desc_middle_click") },
    { key = L("cheatsheet_key_alt_hold"),    desc = L("cheatsheet_desc_envelope") },
    { key = L("cheatsheet_key_double_zero"), desc = L("cheatsheet_desc_double_zero") },
    { section = "FabFilter Pro-Q 3" },
    { key = "Cmd+Z",                         desc = L("cheatsheet_desc_proq_undo") },
    { key = "Cmd+Shift+Z",                   desc = L("cheatsheet_desc_proq_redo") },
    { section = L("cheatsheet_section_ai") },
    { key = "Cmd+Shift+A",                   desc = L("cheatsheet_desc_ai_chat") },
    { section = L("cheatsheet_section_les") },
    { key = "Cmd+Shift+1",                   desc = L("cheatsheet_desc_macro_toggle") },
    { key = "Cmd+Shift+/",                   desc = L("cheatsheet_desc_show_shortcuts") },
    }
end

local function escapeHTML(value)
    return tostring(value or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
end

--- Build the HTML content for the cheatsheet.
---@return string
local function buildHTML()
    local rows = {}
    for _, item in ipairs(shortcutDefinitions()) do
        if item.section then
            rows[#rows + 1] = string.format(
                '<tr><th colspan="2" scope="colgroup" class="section">%s</th></tr>', escapeHTML(item.section))
        else
            rows[#rows + 1] = string.format(
                '<tr><td class="key">%s</td><td class="desc">%s</td></tr>',
                escapeHTML(item.key), escapeHTML(item.desc))
        end
    end

    return [[<!DOCTYPE html><html lang="]] .. escapeHTML(L("locale_code")) .. [["><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { height: 100%; }
body {
    color-scheme: dark;
    background: rgba(28,28,30,0.95);
    color: #e5e5ea;
    font-family: -apple-system, "Helvetica Neue", sans-serif;
    font-size: 13px;
    padding: 18px 20px 14px;
    border-radius: 14px;
    overflow-y: auto;
}
h1 {
    font-size: 14px;
    font-weight: 600;
    color: #fff;
    margin-bottom: 14px;
    text-align: center;
    letter-spacing: 0.01em;
}
table { width: 100%; border-collapse: collapse; }
td { padding: 3px 8px; vertical-align: middle; }
th.section {
    font-size: 10px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    color: #a1a1a6;
    padding-top: 11px;
    padding-bottom: 4px;
    border-bottom: 1px solid #2c2c2e;
    padding-left: 0;
}
td.key {
    font-family: "SF Mono", "Menlo", monospace;
    font-size: 11.5px;
    color: #0a84ff;
    white-space: nowrap;
    width: 48%;
    padding-left: 0;
}
td.desc { color: #c7c7cc; }
.hint {
    text-align: center;
    color: #8e8e93;
    font-size: 11px;
    margin-top: 14px;
}
</style></head><body>
<h1>⌨&nbsp;&nbsp;]] .. escapeHTML(L("cheatsheet_title")) .. [[</h1>
<table>]] .. table.concat(rows, "\n") .. [[</table>
<p class="hint">]] .. escapeHTML(L("cheatsheet_hint")) .. [[</p>
</body></html>]]
end

--- Toggle the cheatsheet overlay. Opens if closed, closes if open.
function cheatsheet.toggle()
    if _webview ~= nil then
        local closingWebview = _webview
        _webview = nil
        closingWebview:delete()
        return
    end

    local screen = hs.screen.mainScreen():frame()
    local frame = windowframe.center(screen, 490, 570, 12)

    _webview = hs.webview.new(frame)
    if _webview == nil then return end
    local currentWebview = _webview
    _webview:deleteOnClose(true)
    _webview:windowStyle({ "titled", "closable", "resizable", "nonactivating" })
    _webview:windowTitle(L("cheatsheet_window_title"))
    _webview:level(hs.drawing.windowLevels.floating)
    _webview:alpha(0.97)
    _webview:allowTextEntry(false)
    _webview:html(buildHTML())
    _webview:windowCallback(function(action)
        if action == "closing" and _webview == currentWebview then
            _webview = nil
        end
    end)
    _webview:show()
end

return cheatsheet

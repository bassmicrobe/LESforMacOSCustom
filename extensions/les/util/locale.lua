--  SPDX-License-Identifier: MIT
--
--  Copyright (c) 2019-2023 LESforMacOS authors, see AUTHORS.txt
--  for a list
--
--  Distributed under the MIT software license, see the accompanying
--  file COPYING.txt or visit https://opensource.org/license/mit/

-- Localization table for English and Japanese.
-- Access strings via the global L("key") function.

local strings = {
  en = {
    -- Shared buttons
    btn_ok          = "Ok",
    btn_yes         = "Yes",
    btn_no          = "No",
    btn_cancel      = "Cancel",
    btn_reset_time  = "Reset Time",

    -- Menu bar items
    menu_console              = "Console",
    menu_restart              = "Restart",
    menu_open_hs_folder       = "Open Hammerspoon Folder",
    menu_search_plugins       = "Search Plugins...",
    menu_project_notes        = "Project Notes...",
    menu_settings             = "Settings...",
    menu_scan_plugins         = "Scan Plugins...",
    menu_force_rescan         = "Force Full Rescan...",
    menu_configure_menu       = "Configure Menu",
    menu_configure_settings   = "Configure Settings (Raw)",
    menu_project_time         = "Project Time",
    menu_strict_time          = "Strict Time",
    menu_reload               = "Reload",
    menu_install_insertwhere  = "Install InsertWhere",
    menu_manual               = "Manual 📖",
    menu_exit                 = "Exit",
    menu_ai_assistant         = "AI Assistant...",
    menu_ai_recommend         = "AI Plugin Suggestions...",
    menu_ai_namegen           = "AI Project Name Suggestions...",
    menu_track_notes          = "Track Notes...",
    menu_language             = "言語: 日本語",  -- shows option to switch TO Japanese

    -- Shared localized UI
    locale_code               = "en",
    ai_empty_response         = "The AI returned an empty response.",
    ai_request_failed         = "Could not get a response from AI. Check your connection and Settings.",
    notes_unsaved_project     = "Unsaved Project",
    notes_item_label          = "Note from %s",
    notes_delete_label        = "Delete this note",
    notes_empty               = "No notes yet.<br>Add one using the field below.",
    notes_input_placeholder   = "Enter a note... (Cmd+Enter to add)",
    notes_add                 = "Add",
    notes_saving              = "Saving...",
    notes_saved               = "Saved.",
    notes_save_failed         = "Failed to save.",
    notes_save_failed_preserved = "Failed to save. Your input has been preserved.",
    notes_too_long            = "Keep the note within 20,000 characters.",
    notes_delete_confirm      = "Delete this note?",
    notes_deleted             = "Deleted.",
    notes_delete_failed       = "Failed to delete.",

    -- AI chat
    chat_title                = "AI Assistant",
    chat_clear                = "Clear Chat",
    chat_welcome_line1        = "Ask anything about music production",
    chat_welcome_line2        = "in Ableton Live.",
    chat_input_label          = "Question for AI",
    chat_input_placeholder    = "Enter a question... (Cmd+Enter to send)",
    chat_send                 = "Send",
    chat_thinking             = "Thinking...",
    chat_input_required       = "Enter a question.",
    chat_input_too_long       = "Keep the question within 8,000 characters.",
    chat_context_project      = "Current project: %s",
    chat_context_session      = "Session time: %d hr %d min",
    chat_system_prompt = [[You are a music production assistant specializing in Ableton Live.
The user works with Ableton Live and Live Enhancement Suite Custom, a Hammerspoon-based extension.
Respond concisely in English.
Answer questions about mixing, sound design, plugin selection, chord progressions, composition techniques, and related topics.
Markdown is allowed. Put code blocks inside triple backticks.]],

    -- AI plugin suggestions
    recommend_title             = "AI Plugin Suggestions",
    recommend_subtitle          = "AI suggests plugins based on your usage statistics.",
    recommend_loading_stats     = "Analyzing plugin statistics...",
    recommend_loading_ai        = "AI is thinking...",
    recommend_extra_label       = "Additional preferences for new suggestions",
    recommend_extra_placeholder = "Additional preferences (e.g. fuller bass, Lo-Fi)",
    recommend_again             = "Suggest Again",
    recommend_pending           = "Suggesting...",
    recommend_no_history        = "No plugin usage history is available. Suggest generally useful plugins.",
    recommend_usage_header      = "Plugin usage statistics follow (most used first, ★ = favorite):",
    recommend_usage_count       = "Uses: %d%s",
    recommend_extra_context     = "Additional user request: %s",
    recommend_config_required   = "Enter an OpenAI API key in Settings to use AI Plugin Suggestions.",
    recommend_input_too_long    = "Keep the input within %d characters.",
    recommend_system_prompt     = "You are a music-production plugin expert. Suggest plugins for Ableton Live users and respond in English.",
    recommend_user_prompt = [[Based on the usage patterns above, suggest 5–8 VST/AU plugins the user may like.
For each plugin, give its name, type (EQ, compressor, synthesizer, and so on), and a one-line reason.
Include free plugins.]],

    -- AI name generator
    namegen_context_project     = "Current project name: %s",
    namegen_context_notes       = "Recent project notes:\n%s",
    namegen_context_plugins     = "Frequently used plugins: %s",
    namegen_context_empty       = "No context is available. Suggest general music project names.",
    namegen_config_required     = "Enter an OpenAI API key in Settings to use the AI Name Generator.",
    namegen_copied              = "Copied “%s” to the clipboard.",
    namegen_loading_placeholder = "AI is generating names...",
    namegen_loading             = "⏳ Generating...",
    namegen_wait                = "Please wait.",
    namegen_error               = "❌ Error",
    namegen_empty_result        = "No names could be generated.",
    namegen_retry               = "Please try again.",
    namegen_choose              = "Select a suggestion.",
    namegen_user_hint           = "User hint: %s",
    namegen_system_prompt       = "You suggest creative names for music projects and tracks. Respond in English.",
    namegen_user_prompt = [[Based on the context above, suggest 10 names for a music project or track.
Use short, creative, memorable names of one to four words.
Add a brief image or description in parentheses after each name.
Write one suggestion per line without numbering.]],

    -- Project and track notes
    projectnotes_title                    = "Project Notes",
    projectnotes_input_label              = "Project note",
    projectnotes_ai_summary               = "AI Summary",
    projectnotes_ai_summarizing           = "Summarizing...",
    projectnotes_ai_status                = "Summarizing with AI...",
    projectnotes_ai_added                 = "Summary added.",
    projectnotes_ai_failed                = "AI summary failed.",
    projectnotes_ai_prefix                = "📋 AI Summary:\n",
    projectnotes_summary_already_pending  = "A summary is already in progress.",
    projectnotes_summary_config_required  = "Set an OpenAI API key in Settings to use AI Summary.",
    projectnotes_summary_config_short     = "Set an OpenAI API key.",
    projectnotes_summary_no_notes         = "There are no notes to summarize.",
    projectnotes_summary_request_failed   = "AI summary failed. Check Settings and your connection.",
    projectnotes_summary_empty_response   = "The AI returned an empty response.",
    projectnotes_summary_save_failed      = "Failed to save the summary.",
    projectnotes_summary_system_prompt    = "Summarize music-production project notes concisely in English.",
    projectnotes_summary_user_prompt      = "These are the notes for project “%s”:\n\n%s\n\nSummarize progress, remaining tasks, and the next actions.",
    tracknotes_title              = "Track Notes",
    tracknotes_prev_label         = "Previous track",
    tracknotes_next_label         = "Next track",
    tracknotes_track_label        = "Track name",
    tracknotes_track_placeholder  = "Enter a track name...",
    tracknotes_detect             = "Detect",
    tracknotes_input_label        = "Track note",
    tracknotes_track_required     = "Enter or detect a track name first.",
    tracknotes_detect_failed      = "Could not detect the track name. Enter it manually.",
    tracknotes_input_too_long     = "The track name or note is too long.",
    tracknotes_switched_status    = "Selected track: %s",

    -- Shortcut reference and HUD
    cheatsheet_title                   = "Live Enhancement Suite Custom — Shortcuts",
    cheatsheet_window_title            = "Shortcuts",
    cheatsheet_hint                    = "Press Cmd+Shift+/ again or close the window to hide it.",
    cheatsheet_section_plugins         = "Plugins",
    cheatsheet_section_pianoroll       = "Piano Roll",
    cheatsheet_section_project         = "Project",
    cheatsheet_section_note_editing    = "Note Editing",
    cheatsheet_section_ai              = "AI Features",
    cheatsheet_section_les             = "LES",
    cheatsheet_key_double_right_click  = "Double right-click",
    cheatsheet_key_shift_double_click  = "Shift + double right-click",
    cheatsheet_key_backquote           = "` (backquote)",
    cheatsheet_key_alt_click           = "Alt + click",
    cheatsheet_key_alt_hold            = "Hold Alt",
    cheatsheet_key_double_zero         = "0 × 2",
    cheatsheet_desc_plugin_menu        = "Plugin menu (trackpad: Control + double left-click also works)",
    cheatsheet_desc_pianoroll_menu     = "Piano Roll menu",
    cheatsheet_desc_plugin_search      = "Plugin search UI",
    cheatsheet_desc_pianoroll_macro    = "Piano Roll macro",
    cheatsheet_desc_duplicate          = "Duplicate track or clip",
    cheatsheet_desc_versioning         = "Save a new project version",
    cheatsheet_desc_marker             = "Add a locator",
    cheatsheet_desc_close_front_plugin = "Close the frontmost plugin window",
    cheatsheet_desc_close_all_plugins  = "Close all plugin windows",
    cheatsheet_desc_abs_drag           = "Absolute Replace (drag)",
    cheatsheet_desc_abs_paste          = "Absolute Replace (paste)",
    cheatsheet_desc_middle_click       = "Middle-click emulation",
    cheatsheet_desc_envelope           = "Toggle envelope mode",
    cheatsheet_desc_double_zero        = "Delete a note with double zero",
    cheatsheet_desc_proq_undo          = "Undo while Pro-Q 3 is focused",
    cheatsheet_desc_proq_redo          = "Redo while Pro-Q 3 is focused",
    cheatsheet_desc_ai_chat            = "AI chat assistant",
    cheatsheet_desc_macro_toggle       = "Enable or pause LES shortcuts",
    cheatsheet_desc_show_shortcuts     = "Show or hide this shortcut reference",
    hud_active                         = "LES Active",
    hud_paused                         = "LES Paused",
    hud_inactive                       = "LES Inactive",
    scanner_title                      = "Plugin Scan",
    scanner_progress_detail            = "Scanning Audio Units and VST3 bundles may take several seconds. This window closes when scanning finishes.",
    scanner_preparing                  = "Preparing...",
    scanner_detecting_au               = "Scanning Audio Units...",
    scanner_detecting_vst3             = "Scanning VST3 bundles...",
    scanner_updating_cache             = "Updating the plugin cache...",
    scanner_complete                   = "Complete",
    scanner_cache_save_failed          = "The plugin cache could not be saved. Check folder permissions and free space.",
    scanner_cache_clear_failed         = "The plugin cache could not be cleared. The full scan was not started.",
    scanner_no_plugins                 = "No plugins were found.\n\nCheck that AU or VST3 plugins are installed.",
    scanner_first_scan_prompt          = "First scan: detected %d plugins.\n\nGenerate a categorized menuconfig.ini?\n(The current file will be backed up.)",
    scanner_menuconfig_save_failed     = "menuconfig.ini could not be saved. The existing configuration was not changed.",
    scanner_backup_created             = "Backup: %s",
    scanner_menuconfig_generated       = "Generated menuconfig.ini with %d plugins.%s",
    scanner_no_changes                 = "No changes (%d plugins detected).\n\nNo new plugins were found.",
    scanner_new_count                  = "New: %d",
    scanner_more_count                 = "  ... and %d more",
    scanner_removed_count              = "\nUninstalled: %d",
    scanner_append_prompt              = "Add the new plugins to menuconfig.ini?\n(The existing menu layout will be preserved.)",
    scanner_plugins_appended           = "Added %d plugins to menuconfig.ini.",
    scanner_plugins_already_present    = "All selected plugins are already present in menuconfig.ini.",
    scanner_au_error                   = "Audio Unit scan error:\n%s",
    scanner_finish_error               = "Scan finalization error:\n%s",
    scanner_vst3_error                 = "VST3 scan error:\n%s",
    scanner_start_error                = "Could not start the scan:\n%s",

    -- Settings editor
    settings_title                         = "LES Settings",
    settings_save_apply                    = "Save and Apply",
    settings_section_toggles               = "Feature Toggles",
    settings_section_timing                = "Performance and Timing",
    settings_section_mapping               = "Input Mapping",
    settings_section_ai                    = "AI Settings",
    settings_toggle_autoadd_label          = "Automatically Add Plugins",
    settings_toggle_autoadd_desc           = "Automatically add the selected plugin to the track.",
    settings_toggle_resettobrowserbookmark_label = "Reset to Browser Bookmark",
    settings_toggle_resettobrowserbookmark_desc  = "Click the saved browser position after adding a plugin (full screen only).",
    settings_toggle_disableloop_label      = "Disable MIDI Clip Looping",
    settings_toggle_disableloop_desc       = "Turn off looping for clips created with Cmd+Shift+M.",
    settings_toggle_saveasnewver_label     = "Versioned Save (Cmd+Alt+S)",
    settings_toggle_saveasnewver_desc      = "Save a new copy with FL Studio-style _2, _3, ... suffixes.",
    settings_toggle_altgrmarker_label      = "Add Locator with Alt+L",
    settings_toggle_altgrmarker_desc       = "Use Alt+L instead of Shift+L to avoid conflicts with uppercase entry.",
    settings_toggle_double0todelete_label  = "Delete with 0 × 2",
    settings_toggle_double0todelete_desc   = "Press 0 twice quickly to trigger Delete.",
    settings_toggle_absolutereplace_label  = "Absolute Replace Shortcuts",
    settings_toggle_absolutereplace_desc   = "Enable Ctrl+Alt+D (Absolute Duplicate) and Ctrl+Alt+V (Absolute Paste).",
    settings_toggle_ctrlabsoluteduplicate_label = "Absolute Duplicate with Cmd+Ctrl+D",
    settings_toggle_ctrlabsoluteduplicate_desc  = "Use an alternative mapping that does not conflict with the Dock hide shortcut.",
    settings_toggle_enableclosewindow_label = "Close Plugins with Cmd+W",
    settings_toggle_enableclosewindow_desc  = "Enable Cmd+W / Cmd+Alt+W (or Cmd+Alt+Esc).",
    settings_toggle_vstshortcuts_label      = "VST Shortcuts",
    settings_toggle_vstshortcuts_desc       = "Enable VST-specific Undo/Redo for plugins such as FabFilter Pro-Q 3.",
    settings_toggle_dynamicreload_label     = "Dynamic Reload",
    settings_toggle_dynamicreload_desc      = "Reload menuconfig.ini whenever the menu opens (disable this if it is slow).",
    settings_toggle_texticon_label          = "Text Menu Bar Icon",
    settings_toggle_texticon_desc           = "Show the menu bar icon as the text “LES”.",
    settings_toggle_addtostartup_label      = "Launch at Login",
    settings_toggle_addtostartup_desc       = "Launch LES when you log in to macOS.",
    settings_toggle_launchwithlive_label    = "Launch When Live Starts",
    settings_toggle_launchwithlive_desc     = "Detect Ableton Live starting and launch LES with a Launch Agent.",
    settings_toggle_notifyexport_label      = "Export Completion Notification",
    settings_toggle_notifyexport_desc       = "Send a macOS Notification Center alert when rendering completes.",
    settings_toggle_notifyhourly_label      = "Hourly Work-Time Notification",
    settings_toggle_notifyhourly_desc       = "Notify you whenever the project session reaches another hour.",
    settings_toggle_enabledebug_label       = "Debug Mode",
    settings_toggle_enabledebug_desc        = "Show Console, Restart, Hammerspoon Folder, and other debugging options.",
    settings_toggle_checksanity_label       = "Version Check",
    settings_toggle_checksanity_desc        = "Check supported macOS and Ableton Live versions at startup.",
    settings_numeric_loadspeed_label        = "Load Wait Time (seconds)",
    settings_numeric_loadspeed_desc         = "Delay before adding a plugin after search (increase this for slower disks).",
    settings_numeric_bookmarkx_label        = "Bookmark X Coordinate (px)",
    settings_numeric_bookmarkx_desc         = "X coordinate clicked by resettobrowserbookmark.",
    settings_numeric_bookmarky_label        = "Bookmark Y Coordinate (px)",
    settings_numeric_bookmarky_desc         = "Y coordinate clicked by resettobrowserbookmark.",
    settings_macro_label                    = "Piano Roll Macro Key",
    settings_macro_desc                     = "One-character trigger for the Piano Roll macro (for example, ` or 1).",
    settings_ai_key_label                   = "OpenAI API Key",
    settings_ai_key_desc                    = "API key used by AI features (get one at platform.openai.com/api-keys).",
    settings_ai_key_placeholder             = "sk-...",
    settings_ai_key_saved_placeholder       = "Saved (enter a new value only to replace it)",
    settings_ai_key_clear                   = "Remove",
    settings_ai_key_clear_on_save           = "Will be removed when saved",
    settings_ai_key_clear_pending           = "Removal pending",
    settings_ai_model_label                 = "AI Model",
    settings_ai_model_desc                  = "Model name to use (for example, gpt-4o-mini, gpt-4o, or gpt-4.1-mini).",
    settings_ai_model_placeholder           = "gpt-4o-mini",
    settings_save_success                   = "Saved.",
    settings_save_failed                    = "Save failed.",
    settings_validation_failed              = "Check the range or format of the input value.",
    settings_saving                         = "Saving...",
    settings_no_response                    = "Save failed (no response).",
    settings_live_saved_applying            = "File saved / applying...",
    settings_live_apply_failed              = "File saved / apply failed",
    settings_live_recovery_failed_suffix    = " (recovery also failed)",
    settings_alert_apply_failed_intro       = "The changes were saved to the settings file, but could not be applied to the running LES.",
    settings_alert_recovery_succeeded       = "Settings were reloaded, but rebuilding the full LES runtime did not complete.",
    settings_alert_recovery_failed          = "Settings recovery also failed (%s).",
    settings_unknown                        = "unknown",
    settings_alert_retry_instruction        = "Keep this window open and save again, or restart LES manually.",
    settings_form_unrecognized              = "Could not save (the form values were not recognized).",
    settings_form_unrecognized_alert        = "Could not save the settings because the form values were not recognized.\nCheck the [settingsgui] log in Console.",
    settings_write_failed                   = "Save failed (could not write the settings file).",
    settings_write_failed_alert             = "Could not write the settings file. Check permissions and available disk space.\n~/.les/settings.ini",
    settings_save_applied_count             = "Saved and applied (%d items).",
    settings_save_notification              = "Settings were saved and applied to the running LES.",
    settings_no_valid_keys                  = "Could not save (there are no valid setting keys).",
    settings_no_valid_keys_alert            = "Could not save because there are no valid setting keys.\nUpdate to the latest build or edit ~/.les/settings.ini directly.",
    settings_open_failed                    = "Could not open Settings. Restart LES and try again.",

    -- Plugin menu editor
    menuconfig_title                        = "Plugin Menu Settings",
    menuconfig_window_title                 = "Plugin Menu Settings — Live Enhancement Suite Custom",
    menuconfig_add_category                 = "＋ Add Category",
    menuconfig_add_plugin                   = "＋ Add Plugin",
    menuconfig_cancel                       = "Cancel",
    menuconfig_save                         = "Save",
    menuconfig_picker_title                 = "Add Plugin",
    menuconfig_close_label                  = "Close",
    menuconfig_search_label                 = "Search plugins",
    menuconfig_search_placeholder           = "Search by plugin name...",
    menuconfig_uncategorized                = "Uncategorized",
    menuconfig_move_placeholder             = "Move...",
    menuconfig_no_plugins                   = "No plugins",
    menuconfig_move_up_label                = "Move %s up",
    menuconfig_move_down_label              = "Move %s down",
    menuconfig_rename_label                 = "Rename %s",
    menuconfig_move_destination_label       = "Move %s to another category",
    menuconfig_move_uncategorized_label     = "Move %s to Uncategorized",
    menuconfig_rename_category_prompt       = "Rename category:",
    menuconfig_new_category_prompt          = "New category name:",
    menuconfig_saving                       = "Saving...",
    menuconfig_no_response                  = "No response. Try again.",
    menuconfig_unsaved_confirm              = "Discard unsaved changes and close?",
    menuconfig_newer_edits_suffix           = " (later changes are not saved)",
    menuconfig_picker_empty                 = "No matching plugins",
    menuconfig_save_success                 = "Saved.",
    menuconfig_partial_success              = "File saved, but applying it to the live menu failed. Reload LES.",
    menuconfig_save_failed                  = "Save failed.",
    menuconfig_unsupported_warning          = "This menu configuration contains subcategories (//) or separators.\nThis editor supports only a flat structure; saving will remove nesting and separators.\n(The original file is backed up automatically before saving.)",
    menuconfig_open_failed                  = "Could not open Plugin Menu Settings. Restart LES and try again.",

    -- Plugin chooser
    chooser_not_loaded   = "Plugin menu is not loaded yet",
    chooser_no_plugins   = "No plugins found in menuconfig.ini",

    -- Plugin menu
    plugin_readme        = "read me",
    menuconfig_missing   = "Your menuconfig.ini is missing or corrupt.\n\nDo you want to restore the default menuconfig?",

    -- Welcome / readme
    readme_body = [[Welcome to Live Enhancement Suite Custom for macOS.

This app is a fork of Live Enhancement Suite; it builds on the macOS rewrite. Thanks to @InvertedSilence and @DirectOfficial for that rewrite, and to @actuallyjamez for the installer.

Double right-click in Ableton Live (when Live is frontmost) to open the custom plug-in menu. On a trackpad, Control + two quick left clicks (secondary double-click) does the same.

Click the LES icon in the menu bar to manage plug-ins, change settings, and open the manual.

Happy producing.]],

    -- Accessibility permission
    accessibility_system_settings     = "System Settings > Privacy & Security > Accessibility",
    accessibility_system_preferences  = "System Preferences > Security & Privacy > Privacy > Accessibility",
    -- %1=programName, %2=asyNavPath (matches module.lua's format args)
    accessibility_alert = "Please grant accessibility permissions for \"%s\" by navigating to %s and enabling it.\n\nIf it isn't already present, please drag and drop the application to the allowlist.",

    -- Version check
    -- %1=programName, %2=minVer, %3=maxVer, %4=curVer, %5=progName, %6=programBugTracker
    version_fail = "%s is only validated to run between %s and %s and is currently being run on %s.\n\nThe program may behave in an undefined manner and may cause disruption but will continue running until prompted to exit.\n\nIf you believe this is in error or that the program must be updated to support a newer release of %s, please file an issue at %s.",
    version_disable_query = "Would you like to disable startup version verification on future launches?\n\nYou can choose to configure this in the future by editing settings.ini and changing the value of \"checksanity\"",

    -- Settings
    settings_startup_query  = "You're all set! Would you like to set LES to launch on login? (this can be changed later)",
    settings_pianoroll_error = "Hey! The settings entry for \"pianorollmacro\" is not a character corresponding to a key on your keyboard.\n\nClosing this dialog box will open the settings file for you; please change the character under \"pianorollmacro\" to a key that exists on your keyboard and then restart the program.\n\nYou won't be able to properly use many features without it.\n\nLES will continue to run without a proper pianoroll macro mapped.",

    -- VST scaling
    macros_scaling_error = "If you're seeing this, it means that Midas didn't properly think about the way VST plugins deal with scaling at your current display resolution.\n\nPerhaps you have the plugin (or your OS) set to a custom scaling amount?\n\nIt is recommended to disable the VST specific shortcuts in the settings.ini if you want to continue to use custom scaling.\n\nThese shortcuts will be disabled until LES is reloaded.",

    -- Project time
    timer_no_project_title  = "There was no open project detected.",
    timer_no_project_detail = "Please open or focus Live for a second and try again.",
    timer_zero              = "0 hours, 0 minutes, and 0 seconds",
    timer_format            = "%d hours, %d minutes, and %02d seconds",
    timer_unsaved_project   = "Time spent in unsaved projects:",
    timer_project           = "Time spent inside the [%s] project:",
    timer_reset_title       = "Are you sure?",
    timer_reset_detail      = "This action cannot be undone",

    -- InsertWhere
    insertwhere_query = "InsertWhere is a Max For Live companion device developed by Mat Zo.\n\nInsertWhere allows you to change the position where plugins are autoinserted after using the LES plugin menu.\n\nOnce loaded, it will allow you to switch between these settings:\n\n- Autoadd plugins before the one you have selected\n- Autoadd plugins after the the one you have selected\n- Always autoadd plugins at the end of the chain like normal\n\nTo activate InsertWhere, place a single instance of the device on the master channel in your project and choose your desired setting.\n\nDo you want to install the InsertWhere M4L plugin?",
    insertwhere_location_alert  = "Please select the location where you want LES to extract the InsertWhere companion plugin.\n\nRecommended: Ableton User Library",
    insertwhere_folder_dialog   = "Please select the location to extract InsertWhere:",
    insertwhere_success = "Success!!\n\nFor extra ease of use, include InsertWhere in your default template.\n\nFor more information on InsertWhere, visit the documentation website linked under the \"Manual 📖\" button in the tray.\n\nThank you Mat Zo for making this amazing device!",

    -- Cheat menu
    cheat_title  = "A mysterious aura surrounds you...",
    cheat_prompt = "Enter cheat",

    -- AppleScript
    rightclick_sleep_error = "applescript sleep failed to execute properly",

    -- Jumpstart (LESmain)
    jumpstart_mismatch          = "LES has detected a mismatched jumpstart script.\n\nThis may be because you're upgrading from an older version of LES, if so, this is normal. Would you like to repair your jumpstart script?",
    jumpstart_success           = "LES has successfully repaired the jumpstart script. Please restart LES for these changes to apply.",
    jumpstart_failure           = "LES was unable to repair the jumpstart script. Please check permissions for ~/.les or clear the directory and try again.",
    jumpstart_continue_warning  = "LES cannot guarantee that it will behave as tested. Would you like to exit LES?",
  },

  ja = {
    -- Shared buttons
    btn_ok          = "OK",
    btn_yes         = "はい",
    btn_no          = "いいえ",
    btn_cancel      = "キャンセル",
    btn_reset_time  = "時間をリセット",

    -- Menu bar items
    menu_console              = "コンソール",
    menu_restart              = "再起動",
    menu_open_hs_folder       = "Hammerspoon フォルダを開く",
    menu_search_plugins       = "プラグインを検索...",
    menu_project_notes        = "プロジェクトノート...",
    menu_settings             = "設定...",
    menu_scan_plugins         = "プラグインをスキャン...",
    menu_force_rescan         = "強制フルスキャン...",
    menu_configure_menu       = "メニュー設定を編集",
    menu_configure_settings   = "設定を直接編集 (Raw)",
    menu_project_time         = "プロジェクト作業時間",
    menu_strict_time          = "厳密な時間計測",
    menu_reload               = "再読み込み",
    menu_install_insertwhere  = "InsertWhere をインストール",
    menu_manual               = "マニュアル 📖",
    menu_exit                 = "終了",
    menu_ai_assistant         = "AI アシスタント...",
    menu_ai_recommend         = "AI プラグイン提案...",
    menu_ai_namegen           = "AI プロジェクト名提案...",
    menu_track_notes          = "トラックメモ",
    menu_language             = "Language: English",  -- shows option to switch TO English

    -- Shared localized UI
    locale_code               = "ja",
    ai_empty_response         = "空の応答が返されました",
    ai_request_failed         = "AI から応答を取得できませんでした。接続と設定を確認してください。",
    notes_unsaved_project     = "未保存のプロジェクト",
    notes_item_label          = "%s のメモ",
    notes_delete_label        = "このメモを削除",
    notes_empty               = "メモはまだありません。<br>下の入力欄から追加できます。",
    notes_input_placeholder   = "メモを入力... (Cmd+Enter で追加)",
    notes_add                 = "追加",
    notes_saving              = "保存中...",
    notes_saved               = "保存しました",
    notes_save_failed         = "保存に失敗しました",
    notes_save_failed_preserved = "保存に失敗しました。入力内容は保持されています。",
    notes_too_long            = "メモは20000文字以内で入力してください",
    notes_delete_confirm      = "このメモを削除しますか？",
    notes_deleted             = "削除しました",
    notes_delete_failed       = "削除に失敗しました",

    -- AI chat
    chat_title                = "AI アシスタント",
    chat_clear                = "会話クリア",
    chat_welcome_line1        = "Ableton Live の音楽制作について",
    chat_welcome_line2        = "何でも質問してください。",
    chat_input_label          = "AIへの質問",
    chat_input_placeholder    = "質問を入力... (Cmd+Enter で送信)",
    chat_send                 = "送信",
    chat_thinking             = "考え中...",
    chat_input_required       = "質問を入力してください",
    chat_input_too_long       = "質問は8000文字以内で入力してください",
    chat_context_project      = "現在のプロジェクト: %s",
    chat_context_session      = "セッション時間: %d時間%d分",
    chat_system_prompt = [[あなたは Ableton Live に特化した音楽制作アシスタントです。
ユーザーは Ableton Live + Live Enhancement Suite Custom (Hammerspoon ベースの拡張ツール) を使用しています。
質問には日本語で簡潔に回答してください。
ミキシング、サウンドデザイン、プラグイン選び、コード進行、作曲テクニックなどの質問に対応します。
回答は Markdown 形式で構いません。コードブロックは ```で囲んでください。]],

    -- AI plugin suggestions
    recommend_title             = "AI プラグイン提案",
    recommend_subtitle          = "使用統計をもとに AI がプラグインを提案します",
    recommend_loading_stats     = "プラグイン統計を分析中...",
    recommend_loading_ai        = "AI が考え中...",
    recommend_extra_label       = "再提案の追加条件",
    recommend_extra_placeholder = "追加の条件（例: ベースを太くしたい、Lo-Fi系）",
    recommend_again             = "再提案",
    recommend_pending           = "提案中...",
    recommend_no_history        = "プラグインの使用履歴がまだありません。一般的なおすすめを提案してください。",
    recommend_usage_header      = "以下はユーザーのプラグイン使用統計です（使用頻度順、★=お気に入り）:",
    recommend_usage_count       = "使用回数: %d%s",
    recommend_extra_context     = "ユーザーからの追加リクエスト: %s",
    recommend_config_required   = "AI プラグイン提案を使うには、設定画面で OpenAI API キーを入力してください。",
    recommend_input_too_long    = "入力は%d文字以内にしてください",
    recommend_system_prompt     = "あなたは音楽制作プラグインの専門家です。Ableton Live ユーザー向けにプラグインを提案します。日本語で回答してください。",
    recommend_user_prompt = [[上記の使用傾向に基づいて、ユーザーが気に入りそうなプラグイン（VST/AU）を5〜8個提案してください。
各プラグインについて: 名前、種類（EQ/コンプ/シンセ等）、おすすめ理由を1行で。
無料プラグインも含めてください。]],

    -- AI name generator
    namegen_context_project     = "現在のプロジェクト名: %s",
    namegen_context_notes       = "最近のプロジェクトメモ:\n%s",
    namegen_context_plugins     = "よく使うプラグイン: %s",
    namegen_context_empty       = "コンテキスト情報なし。一般的な音楽プロジェクト名を提案してください。",
    namegen_config_required     = "AI 名前ジェネレーターを使うには、設定画面で OpenAI API キーを入力してください。",
    namegen_copied              = "「%s」をクリップボードにコピーしました",
    namegen_loading_placeholder = "AI が名前を生成中...",
    namegen_loading             = "⏳ 生成中...",
    namegen_wait                = "少々お待ちください",
    namegen_error               = "❌ エラー",
    namegen_empty_result        = "名前を生成できませんでした",
    namegen_retry               = "もう一度お試しください",
    namegen_choose              = "候補を選択してください",
    namegen_user_hint           = "ユーザーからのヒント: %s",
    namegen_system_prompt       = "あなたはクリエイティブな音楽プロジェクト名を提案するアシスタントです。日本語で回答してください。",
    namegen_user_prompt = [[上記のコンテキストに基づいて、音楽プロジェクト/トラックの名前を10個提案してください。
条件:
- クリエイティブで印象的な短い名前（1〜4語）
- 英語・日本語・造語のミックスOK
- 各名前の後に括弧でイメージを一言添える
- 1行に1つずつ、番号なしで出力]],

    -- Project and track notes
    projectnotes_title                    = "プロジェクトメモ",
    projectnotes_input_label              = "プロジェクトメモ",
    projectnotes_ai_summary               = "AI 要約",
    projectnotes_ai_summarizing           = "要約中...",
    projectnotes_ai_status                = "AIで要約しています...",
    projectnotes_ai_added                 = "要約を追加しました",
    projectnotes_ai_failed                = "AI要約に失敗しました",
    projectnotes_ai_prefix                = "📋 AI 要約:\n",
    projectnotes_summary_already_pending  = "要約はすでに処理中です",
    projectnotes_summary_config_required  = "AI 要約を使うには、設定画面で OpenAI API キーを入力してください。",
    projectnotes_summary_config_short     = "OpenAI APIキーを設定してください",
    projectnotes_summary_no_notes         = "要約するメモがありません",
    projectnotes_summary_request_failed   = "AI要約に失敗しました。設定と通信状態を確認してください。",
    projectnotes_summary_empty_response   = "AIから空の応答が返されました",
    projectnotes_summary_save_failed      = "要約の保存に失敗しました",
    projectnotes_summary_system_prompt    = "あなたは音楽制作プロジェクトのメモを要約するアシスタントです。日本語で簡潔に回答してください。",
    projectnotes_summary_user_prompt      = "以下はプロジェクト「%s」のメモです:\n\n%s\n\n上記のメモを要約してください。進捗状況、残タスク、次にやるべきことを簡潔にまとめてください。",
    tracknotes_title              = "トラックメモ",
    tracknotes_prev_label         = "前のトラック",
    tracknotes_next_label         = "次のトラック",
    tracknotes_track_label        = "トラック名",
    tracknotes_track_placeholder  = "トラック名を入力...",
    tracknotes_detect             = "検出",
    tracknotes_input_label        = "トラックメモ",
    tracknotes_track_required     = "先にトラック名を入力または検出してください",
    tracknotes_detect_failed      = "トラック名を検出できませんでした。手動で入力してください。",
    tracknotes_input_too_long     = "トラック名またはメモが長すぎます",
    tracknotes_switched_status    = "選択中のトラック: %s",

    -- Shortcut reference and HUD
    cheatsheet_title                   = "Live Enhancement Suite Custom — ショートカット",
    cheatsheet_window_title            = "ショートカット一覧",
    cheatsheet_hint                    = "Cmd+Shift+/ または ウィンドウを閉じて非表示",
    cheatsheet_section_plugins         = "プラグイン",
    cheatsheet_section_pianoroll       = "ピアノロール",
    cheatsheet_section_project         = "プロジェクト操作",
    cheatsheet_section_note_editing    = "ノート編集",
    cheatsheet_section_ai              = "AI 機能",
    cheatsheet_section_les             = "LES 管理",
    cheatsheet_key_double_right_click  = "ダブル右クリック",
    cheatsheet_key_shift_double_click  = "Shift + ダブル右クリック",
    cheatsheet_key_backquote           = "` (バッククォート)",
    cheatsheet_key_alt_click           = "Alt + クリック",
    cheatsheet_key_alt_hold            = "Alt（ホールド）",
    cheatsheet_key_double_zero         = "0 × 2",
    cheatsheet_desc_plugin_menu        = "プラグインメニュー（トラックパッド: Control+左ダブルでも可）",
    cheatsheet_desc_pianoroll_menu     = "ピアノロールメニュー",
    cheatsheet_desc_plugin_search      = "プラグイン検索 UI",
    cheatsheet_desc_pianoroll_macro    = "ピアノロールマクロ",
    cheatsheet_desc_duplicate          = "トラック / クリップ複製",
    cheatsheet_desc_versioning         = "プロジェクトバージョニング",
    cheatsheet_desc_marker             = "マーカー作成",
    cheatsheet_desc_close_front_plugin = "前面のプラグインウィンドウを閉じる",
    cheatsheet_desc_close_all_plugins  = "すべてのプラグインウィンドウを閉じる",
    cheatsheet_desc_abs_drag           = "Absolute Replace（ドラッグ）",
    cheatsheet_desc_abs_paste          = "Absolute Replace（貼り付け）",
    cheatsheet_desc_middle_click       = "中クリックエミュレーション",
    cheatsheet_desc_envelope           = "エンベロープモード切替",
    cheatsheet_desc_double_zero        = "ダブル 0 削除（ノート削除）",
    cheatsheet_desc_proq_undo          = "Undo（Pro-Q 3 フォーカス時）",
    cheatsheet_desc_proq_redo          = "Redo（Pro-Q 3 フォーカス時）",
    cheatsheet_desc_ai_chat            = "AI チャットアシスタント",
    cheatsheet_desc_macro_toggle       = "マクロ 有効 / 無効切替",
    cheatsheet_desc_show_shortcuts     = "ショートカット一覧（このウィンドウ）",
    hud_active                         = "LES アクティブ",
    hud_paused                         = "LES 一時停止",
    hud_inactive                       = "LES 非アクティブ",
    scanner_title                      = "プラグインスキャン",
    scanner_progress_detail            = "Audio Units と VST3 バンドルの走査には数十秒かかることがあります。このウィンドウは完了後に閉じます。",
    scanner_preparing                  = "準備中...",
    scanner_detecting_au               = "Audio Units を検出中...",
    scanner_detecting_vst3             = "VST3 バンドルを検出中...",
    scanner_updating_cache             = "プラグインキャッシュを更新中...",
    scanner_complete                   = "完了",
    scanner_cache_save_failed          = "プラグインキャッシュを保存できませんでした。フォルダの権限と空き容量を確認してください。",
    scanner_cache_clear_failed         = "プラグインキャッシュを消去できなかったため、フルスキャンを開始しませんでした。",
    scanner_no_plugins                 = "プラグインが見つかりませんでした。\n\nAU / VST3 プラグインがインストールされているか確認してください。",
    scanner_first_scan_prompt          = "初回スキャン: %d 個のプラグインを検出しました。\n\nカテゴリ分類済みの menuconfig.ini を生成しますか？\n（現在のファイルはバックアップされます）",
    scanner_menuconfig_save_failed     = "menuconfig.ini の保存に失敗しました。既存の設定は変更していません。",
    scanner_backup_created             = "バックアップ: %s",
    scanner_menuconfig_generated       = "menuconfig.ini を生成しました（%d プラグイン）%s",
    scanner_no_changes                 = "変更なし（%d プラグイン検出済み）\n\n新しいプラグインは見つかりませんでした。",
    scanner_new_count                  = "新規: %d 個",
    scanner_more_count                 = "  ... 他 %d 個",
    scanner_removed_count              = "\nアンインストール済み: %d 個",
    scanner_append_prompt              = "新規プラグインを menuconfig.ini に追加しますか？\n（既存のメニュー構成は維持されます）",
    scanner_plugins_appended           = "%d 個のプラグインを menuconfig.ini に追加しました。",
    scanner_plugins_already_present    = "追加対象のプラグインはすべて menuconfig.ini に存在していました。",
    scanner_au_error                   = "Audio Unit スキャンでエラー:\n%s",
    scanner_finish_error               = "スキャン完了処理でエラー:\n%s",
    scanner_vst3_error                 = "VST3 スキャンでエラー:\n%s",
    scanner_start_error                = "スキャン開始でエラー:\n%s",

    -- Settings editor
    settings_title                         = "LES 設定",
    settings_save_apply                    = "保存して反映",
    settings_section_toggles               = "機能トグル",
    settings_section_timing                = "パフォーマンス・タイミング",
    settings_section_mapping               = "入力マッピング",
    settings_section_ai                    = "AI 設定",
    settings_toggle_autoadd_label          = "プラグイン自動追加",
    settings_toggle_autoadd_desc           = "選択後に自動でトラックへ追加する",
    settings_toggle_resettobrowserbookmark_label = "ブックマークへリセット",
    settings_toggle_resettobrowserbookmark_desc  = "追加後にブックマーク位置をクリック（フルスクリーン時のみ）",
    settings_toggle_disableloop_label      = "MIDIループ無効化",
    settings_toggle_disableloop_desc       = "Cmd+Shift+M で作成したクリップのループをオフにする",
    settings_toggle_saveasnewver_label     = "バージョン保存 (Cmd+Alt+S)",
    settings_toggle_saveasnewver_desc      = "FL Studio 風の _2, _3 ... 付き新規保存",
    settings_toggle_altgrmarker_label      = "Alt+L でマーカー追加",
    settings_toggle_altgrmarker_desc       = "Shift+L の代わりに Alt+L を使用（大文字入力と競合しない）",
    settings_toggle_double0todelete_label  = "0×2 で削除",
    settings_toggle_double0todelete_desc   = "0 キーを素早く 2 回押して Delete を実行",
    settings_toggle_absolutereplace_label  = "絶対置換ショートカット",
    settings_toggle_absolutereplace_desc   = "Ctrl+Alt+D（絶対複製）と Ctrl+Alt+V（絶対貼付け）を有効化",
    settings_toggle_ctrlabsoluteduplicate_label = "Cmd+Ctrl+D で絶対複製",
    settings_toggle_ctrlabsoluteduplicate_desc  = "Dock の非表示ショートカットと競合しない代替マッピング",
    settings_toggle_enableclosewindow_label = "Cmd+W でプラグインを閉じる",
    settings_toggle_enableclosewindow_desc  = "Cmd+W / Cmd+Alt+W（または Cmd+Alt+Esc）を有効化",
    settings_toggle_vstshortcuts_label      = "VST ショートカット",
    settings_toggle_vstshortcuts_desc       = "FabFilter Pro-Q 3 など VST 専用の Undo/Redo",
    settings_toggle_dynamicreload_label     = "動的リロード",
    settings_toggle_dynamicreload_desc      = "メニューを開くたびに menuconfig.ini を再読み込み（重い場合は無効化）",
    settings_toggle_texticon_label          = "テキストアイコン",
    settings_toggle_texticon_desc           = "メニューバーのアイコンを “LES” テキストで表示",
    settings_toggle_addtostartup_label      = "ログイン時に自動起動",
    settings_toggle_addtostartup_desc       = "macOS ログイン時に LES を起動",
    settings_toggle_launchwithlive_label    = "Live 起動時に自動起動",
    settings_toggle_launchwithlive_desc     = "Ableton Live の起動を検知して LES を自動起動（Launch Agent）",
    settings_toggle_notifyexport_label      = "エクスポート完了通知",
    settings_toggle_notifyexport_desc       = "レンダリング完了時に macOS 通知センターへ通知",
    settings_toggle_notifyhourly_label      = "1時間ごとの作業時間通知",
    settings_toggle_notifyhourly_desc       = "プロジェクトのセッション時間が 1 時間経過するたびに通知",
    settings_toggle_enabledebug_label       = "デバッグモード",
    settings_toggle_enabledebug_desc        = "コンソール・再起動・Hammerspoon フォルダなどのオプションを表示",
    settings_toggle_checksanity_label       = "バージョン検証",
    settings_toggle_checksanity_desc        = "macOS と Ableton Live のサポートバージョンを起動時に確認",
    settings_numeric_loadspeed_label        = "ロード待機時間（秒）",
    settings_numeric_loadspeed_desc         = "プラグイン検索後に追加するまでの待機秒数（HDDが遅い場合は増やす）",
    settings_numeric_bookmarkx_label        = "ブックマーク X 座標（px）",
    settings_numeric_bookmarkx_desc         = "resettobrowserbookmark のクリック先 X 座標",
    settings_numeric_bookmarky_label        = "ブックマーク Y 座標（px）",
    settings_numeric_bookmarky_desc         = "resettobrowserbookmark のクリック先 Y 座標",
    settings_macro_label                    = "ピアノロールマクロキー",
    settings_macro_desc                     = "ピアノロールマクロのトリガーキー（例: ` や 1 など 1 文字）",
    settings_ai_key_label                   = "OpenAI API キー",
    settings_ai_key_desc                    = "AI 機能で使用する API キー（platform.openai.com/api-keys で取得）",
    settings_ai_key_placeholder             = "sk-...",
    settings_ai_key_saved_placeholder       = "保存済み（変更する場合のみ入力）",
    settings_ai_key_clear                   = "削除",
    settings_ai_key_clear_on_save           = "保存時に削除されます",
    settings_ai_key_clear_pending           = "削除予定",
    settings_ai_model_label                 = "AI モデル",
    settings_ai_model_desc                  = "使用するモデル名（例: gpt-4o-mini, gpt-4o, gpt-4.1-mini）",
    settings_ai_model_placeholder           = "gpt-4o-mini",
    settings_save_success                   = "保存しました",
    settings_save_failed                    = "保存に失敗しました",
    settings_validation_failed              = "入力値の範囲または形式を確認してください",
    settings_saving                         = "保存中...",
    settings_no_response                    = "保存に失敗しました（応答なし）",
    settings_live_saved_applying            = "ファイル保存済み／反映中...",
    settings_live_apply_failed              = "ファイル保存済み／反映失敗",
    settings_live_recovery_failed_suffix    = "（復旧にも失敗）",
    settings_alert_apply_failed_intro       = "設定ファイルへの保存は完了しましたが、実行中の LES への反映に失敗しました。",
    settings_alert_recovery_succeeded       = "設定値の再読み込みは完了しましたが、LES 全体の再構築は完了していません。",
    settings_alert_recovery_failed          = "設定状態の復旧にも失敗しました（%s）。",
    settings_unknown                        = "不明",
    settings_alert_retry_instruction        = "この画面を残したまま、再度保存するか LES を手動で再起動してください。",
    settings_form_unrecognized              = "保存できませんでした（フォームの値を認識できません）",
    settings_form_unrecognized_alert        = "設定を保存できませんでした（フォームの値を認識できません）。\nコンソールの [settingsgui] ログを確認してください。",
    settings_write_failed                   = "保存に失敗しました（設定ファイルへ書き込めません）",
    settings_write_failed_alert             = "設定ファイルへ書き込めませんでした（権限またはディスク容量を確認してください）。\n~/.les/settings.ini",
    settings_save_applied_count             = "保存・反映しました（%d 項目）",
    settings_save_notification              = "設定を保存し、実行中の LES に反映しました。",
    settings_no_valid_keys                  = "保存できませんでした（有効な設定キーがありません）",
    settings_no_valid_keys_alert            = "設定を保存できませんでした（有効な設定キーがありません）。\nアプリを最新ビルドに更新するか、~/.les/settings.ini を直接編集してください。",
    settings_open_failed                    = "設定画面を開けませんでした。LES を再起動してもう一度お試しください。",

    -- Plugin menu editor
    menuconfig_title                        = "プラグインメニュー設定",
    menuconfig_window_title                 = "プラグインメニュー設定 — Live Enhancement Suite Custom",
    menuconfig_add_category                 = "＋ カテゴリ追加",
    menuconfig_add_plugin                   = "＋ プラグインを追加",
    menuconfig_cancel                       = "キャンセル",
    menuconfig_save                         = "保存",
    menuconfig_picker_title                 = "プラグインを追加",
    menuconfig_close_label                  = "閉じる",
    menuconfig_search_label                 = "プラグインを検索",
    menuconfig_search_placeholder           = "プラグイン名で検索...",
    menuconfig_uncategorized                = "未分類",
    menuconfig_move_placeholder             = "移動...",
    menuconfig_no_plugins                   = "プラグインがありません",
    menuconfig_move_up_label                = "%sを上へ",
    menuconfig_move_down_label              = "%sを下へ",
    menuconfig_rename_label                 = "%sの名前を変更",
    menuconfig_move_destination_label       = "%sの移動先",
    menuconfig_move_uncategorized_label     = "%sを未分類へ移動",
    menuconfig_rename_category_prompt       = "カテゴリ名を変更:",
    menuconfig_new_category_prompt          = "新しいカテゴリ名:",
    menuconfig_saving                       = "保存中...",
    menuconfig_no_response                  = "応答がありませんでした。再度お試しください。",
    menuconfig_unsaved_confirm              = "未保存の変更があります。破棄して閉じますか？",
    menuconfig_newer_edits_suffix           = "（その後の変更は未保存です）",
    menuconfig_picker_empty                 = "該当するプラグインがありません",
    menuconfig_save_success                 = "保存しました",
    menuconfig_partial_success              = "ファイルは保存しましたが、ライブメニューへの反映に失敗しました。LES を再読み込みしてください。",
    menuconfig_save_failed                  = "保存に失敗しました",
    menuconfig_unsupported_warning          = "このメニュー設定にはサブカテゴリ（//）や区切り線が含まれています。\nこのエディタはフラットな構造のみ編集でき、保存するとネストや区切りは失われます。\n（保存前に元のファイルは自動でバックアップされます）",
    menuconfig_open_failed                  = "プラグインメニュー設定を開けませんでした。LES を再起動してもう一度お試しください。",

    -- Plugin chooser
    chooser_not_loaded   = "プラグインメニューがまだ読み込まれていません",
    chooser_no_plugins   = "menuconfig.ini にプラグインが見つかりません",

    -- Plugin menu
    plugin_readme       = "はじめに",
    menuconfig_missing  = "menuconfig.ini が見つからないか破損しています。\n\nデフォルトの menuconfig を復元しますか？",

    -- Welcome / readme
    readme_body = [[Live Enhancement Suite Custom（macOS 版）へようこそ。

本アプリは Live Enhancement Suite のフォークで、macOS 向けリライトを土台にしています。
オリジナルのリライトは @InvertedSilence と @DirectOfficial、インストーラーは @actuallyjamez によるものです（御礼申し上げます）。

Ableton Live のウィンドウが前面のとき、ダブル右クリックでカスタムのプラグインメニューが開きます。トラックパッドでは Control を押したまま左クリックを続けて 2 回（副ボタンのダブル相当）でも同じ動作になります。

メニューバーの LES アイコンから、プラグインの整理・各種設定・マニュアルを開けます。

制作、楽しんでください。]],

    -- Accessibility permission
    accessibility_system_settings     = "システム設定 > プライバシーとセキュリティ > アクセシビリティ",
    accessibility_system_preferences  = "システム環境設定 > セキュリティとプライバシー > プライバシー > アクセシビリティ",
    -- %1=programName, %2=asyNavPath, %3=programName (unused)
    accessibility_alert = "「%s」にアクセシビリティの権限を付与してください。%s に移動して有効にしてください。\n\nリストにない場合は、アプリをドラッグ＆ドロップで許可リストに追加してください。",

    -- Version check
    -- %1=programName, %2=minVer, %3=maxVer, %4=curVer, %5=progName, %6=programBugTracker
    version_fail = "%s は macOS %s から macOS %s の間でのみ動作が検証されていますが、現在 macOS %s で実行されています。\n\nこのプログラムは予期しない動作をしたり、問題を引き起こす可能性がありますが、終了を求められるまで動作を継続します。\n\nこれが誤りであると思われる場合、またはより新しい macOS バージョンへの対応が必要な場合は、%s の issue トラッカーに報告してください: %s",
    version_disable_query = "今後の起動時にバージョン確認を無効にしますか？\n\nこの設定は、settings.ini を編集して \"checksanity\" の値を変更することで、後から変更できます。",

    -- Settings
    settings_startup_query  = "設定が完了しました！ログイン時に LES を自動起動しますか？（後から変更できます）",
    settings_pianoroll_error = "設定ファイルの \"pianorollmacro\" にキーボード上に存在しない文字が設定されています。\n\nこのダイアログを閉じると設定ファイルが開きます。\"pianorollmacro\" の値をキーボード上に存在するキーに変更して、プログラムを再起動してください。\n\nこの設定がないと多くの機能が正常に使用できません。\n\nLES はピアノロールマクロなしで動作を継続します。",

    -- VST scaling
    macros_scaling_error = "現在のディスプレイ解像度では、VST プラグインのスケーリングが正しく認識できませんでした。\n\nプラグインまたは OS にカスタムスケーリングが設定されている可能性があります。\n\nカスタムスケーリングを使用し続ける場合は、settings.ini で VST 専用ショートカットを無効にすることをお勧めします。\n\nこれらのショートカットは LES を再読み込みするまで無効になります。",

    -- Project time
    timer_no_project_title  = "開いているプロジェクトが見つかりませんでした。",
    timer_no_project_detail = "Live を開くか、フォーカスしてからもう一度試してください。",
    timer_zero              = "0時間 0分 0秒",
    timer_format            = "%d時間 %d分 %02d秒",
    timer_unsaved_project   = "未保存プロジェクトの作業時間:",
    timer_project           = "[%s] プロジェクトの作業時間:",
    timer_reset_title       = "本当にリセットしますか？",
    timer_reset_detail      = "この操作は元に戻せません",

    -- InsertWhere
    insertwhere_query = "InsertWhere は Mat Zo が開発した Max For Live コンパニオンデバイスです。\n\nInsertWhere を使うと、LES プラグインメニューからプラグインを自動挿入する際の位置を変更できます。\n\nロード後、以下の設定を切り替えられます:\n\n- 選択中のプラグインの前に自動挿入\n- 選択中のプラグインの後に自動挿入\n- 通常通り常にチェーンの末尾に自動挿入\n\nInsertWhere を有効にするには、プロジェクトのマスターチャンネルにデバイスを1つ配置し、希望する設定を選んでください。\n\nInsertWhere M4L プラグインをインストールしますか？",
    insertwhere_location_alert  = "InsertWhere コンパニオンプラグインの展開先を選択してください。\n\n推奨: Ableton ユーザーライブラリ",
    insertwhere_folder_dialog   = "InsertWhere の展開先を選択してください:",
    insertwhere_success = "インストール完了！\n\nより使いやすくするために、デフォルトテンプレートに InsertWhere を含めることをお勧めします。\n\nInsertWhere の詳細については、トレイの「マニュアル 📖」ボタンからドキュメントサイトをご覧ください。\n\n素晴らしいデバイスを作ってくれた Mat Zo に感謝！",

    -- Cheat menu
    cheat_title  = "不思議なオーラに包まれた...",
    cheat_prompt = "チートコードを入力",

    -- AppleScript
    rightclick_sleep_error = "AppleScript のスリープ処理に失敗しました",

    -- Jumpstart (LESmain)
    jumpstart_mismatch          = "LES が起動スクリプトの不一致を検出しました。\n\n旧バージョンからアップグレード中の場合は正常です。起動スクリプトを修復しますか？",
    jumpstart_success           = "起動スクリプトの修復が完了しました。変更を反映するには LES を再起動してください。",
    jumpstart_failure           = "起動スクリプトの修復に失敗しました。~/.les のアクセス権限を確認するか、ディレクトリを削除してから再試行してください。",
    jumpstart_continue_warning  = "LES の動作を保証できません。LES を終了しますか？",
  },
}

--- Global localization function.
--- Returns the UI string for `key` in the current language (_G.uiLanguage).
--- Falls back to Japanese, then to the key itself if not found.
local locale = {}

function locale.translate(key, language)
  local lang = language or _G.uiLanguage or "ja"
  local t = strings[lang] or strings["ja"]
  local s = t[key]
  if s == nil then
    s = strings["ja"][key]
  end
  return s or key
end

function locale.stringsFor(language)
  local source = strings[language] or strings["ja"]
  local copy = {}
  for key, value in pairs(source) do copy[key] = value end
  return copy
end

function L(key)
  return locale.translate(key)
end

return locale

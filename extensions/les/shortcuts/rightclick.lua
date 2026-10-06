--  SPDX-License-Identifier: MIT
--
--  Copyright (c) 2019-2023 LESforMacOS authors, see AUTHORS.txt
--  for a list
--
--  Distributed under the MIT software license, see the accompanying
--  file COPYING.txt or visit https://opensource.org/license/mit/

-----------------------------
--  Right Clicking & Menus --
-----------------------------

function spawnPluginMenu() -- spawns and moves the invisible menu bar menu to the mouse location.
    if pluginMenu then
        pluginMenu:popupMenu(hs.mouse.absolutePosition())
    end
end

function spawnPianoMenu() -- spawns and moves the invisible menu bar menu to the mouse location.
    if pianoMenu then
        pianoMenu:popupMenu(hs.mouse.absolutePosition())
    end
end

function getABSTime()
    return hs.timer.absoluteTime()
end

--- Convert nanoseconds to seconds.
--- NOTE: Currently unused. Retained for potential external callers.
---@param nanoseconds number
---@return number
function nanoToSec(nanoseconds)
    return nanoseconds / 1000000000
end

-- The macOS system menu right click behavior is to open the
-- menu on the mouseDown event. If we trigger our action on
-- that event as well the system menu will delay being opened
-- and essentially store the action until our menu closes. We
-- must trigger our event on the mouse up event. -- Direct

-- timeRMBTime: nil = no pending first click; otherwise epoch seconds of last first rightMouseUp
timeRMBTime, firstDown, secondDown = nil, false, true
-- Control + 左クリック用（clickState が届かないトラックパッド向け）
local ctrlTapTime, ctrlFirstPhase = nil, false

-- Double-right is slower than double-left for many users; never go below system interval
local timeFrame = math.max(hs.eventtap.doubleClickInterval(), 0.85)

local clickStateProp = hs.eventtap.event.properties.mouseEventClickState

local rightMouseUpType = hs.eventtap.event.types.rightMouseUp
local leftMouseUpType = hs.eventtap.event.types.leftMouseUp

--- Open plugin or piano menu after a confirmed double secondary click.
---@param usePiano boolean
local function spawnMenuAfterDoubleSecondary(usePiano)
    local function spawnMenu()
        if usePiano then spawnPianoMenu() else spawnPluginMenu() end
    end
    if _G.dynamicreload == 1 then
        -- quickreload() does file I/O + full menu rebuild; defer to next run-loop
        -- tick so the click handler returns immediately and avoids a UI freeze.
        hs.timer.doAfter(0, function()
            quickreload()
            spawnMenu()
        end)
    else
        spawnMenu()
    end
end

-- Trackpad「Control + クリック」は OS によっては right ではなく left + ctrl として届く。
firstRightClick = hs.eventtap.new({
    hs.eventtap.event.types.rightMouseDown,
    rightMouseUpType,
    leftMouseUpType,
}, function(event)
        if timeRMBTime ~= nil and (hs.timer.secondsSinceEpoch() - timeRMBTime) > timeFrame then
            timeRMBTime, firstDown, secondDown = nil, false, true
        end

        -- Control + 左ダブルクリック（トラックパッドの副ボタン相当）。Live 前面のみ。
        if event:getType() == leftMouseUpType then
            local flags = event:getFlags()
            if not (flags.ctrl and not flags.cmd and isLiveFocused()) then
                return false
            end
            local clickState = event:getProperty(clickStateProp)
            if type(clickState) == "number" and clickState >= 2 then
                ctrlTapTime, ctrlFirstPhase = nil, false
                local usePiano = flags.shift or (_G.pressingshit == true)
                spawnMenuAfterDoubleSecondary(usePiano)
                return true
            end
            if ctrlTapTime ~= nil and (hs.timer.secondsSinceEpoch() - ctrlTapTime) > timeFrame then
                ctrlTapTime, ctrlFirstPhase = nil, false
            end
            if not ctrlFirstPhase then
                ctrlFirstPhase = true
                ctrlTapTime = hs.timer.secondsSinceEpoch()
                return false
            end
            ctrlTapTime, ctrlFirstPhase = nil, false
            local usePiano = flags.shift or (_G.pressingshit == true)
            spawnMenuAfterDoubleSecondary(usePiano)
            return true
        end

        if event:getType() == rightMouseUpType then
            -- Prefer system click count (double / triple right-click) when available — more reliable than timing alone.
            local clickState = event:getProperty(clickStateProp)
            if type(clickState) == "number" and clickState >= 2 then
                timeRMBTime, firstDown, secondDown = nil, false, true
                spawnMenuAfterDoubleSecondary(_G.pressingshit == true)
                return true
            end
            if firstDown and secondDown then
                spawnMenuAfterDoubleSecondary(_G.pressingshit == true)
                timeRMBTime, firstDown, secondDown = nil, false, true
                return true
            elseif not firstDown then
                firstDown = true
                timeRMBTime = hs.timer.secondsSinceEpoch()
                return false
            elseif firstDown then
                secondDown = true
                return false
            else
                timeRMBTime, firstDown, secondDown = nil, false, true
                return false
            end
        end

        return false
    end):start() -- starts the eventtap listener for double right clicks.

function titlebarheight()
    local w = hs.window.focusedWindow()
    if not w then return 22 end
    local rect = w:zoomButtonRect()
    if not rect or not rect.h then return 22 end
    return rect.h + 4
end

function bookmarkfunc() -- this allows you to use the bookmark click stuff.
    -- Runs from a bare hs.timer.doAfter callback (NOT inside macros.lua's pcall),
    -- so guard both derefs: Live can quit / lose its main window during the delay.
    local app = getLiveHsAppObj()
    local mainwin = app and app:mainWindow()
    if not mainwin then return end
    local point = {}
    local dimensions = mainwin:frame()
    local bookmark = {}
    bookmark["x"] = _G.bookmarkx + dimensions.x
    bookmark["y"] = _G.bookmarky + dimensions.y + titlebarheight()
    point = hs.mouse.absolutePosition()
    point["__luaSkinType"] = nil
    hs.eventtap.event.newMouseEvent(hs.eventtap.event.types["leftMouseDown"], bookmark):setProperty(hs.eventtap.event
                                                                                                        .properties
                                                                                                        .mouseEventClickState,
        1):post()
    local delay = _G.loadspeed <= 0.5 and 0.1 or 0.3
    hs.timer.doAfter(delay, function()
        hs.eventtap.event.newMouseEvent(hs.eventtap.event.types["leftMouseUp"], bookmark):setProperty(hs.eventtap.event
                                                                                                          .properties
                                                                                                          .mouseEventClickState,
            1):post()
        hs.eventtap.event.newMouseEvent(hs.eventtap.event.types["leftMouseUp"], point):post()
    end)
end

local pluginStats = require("tracking.pluginstats")
local loadGeneration = 0
local pendingLoadTimer

function cancelPendingPluginLoad()
    loadGeneration = loadGeneration + 1
    if pendingLoadTimer then pendingLoadTimer:stop() end
    pendingLoadTimer = nil
end

local function rcLog(msg)
    -- Only log when debug mode is enabled. Previously this appended to debug.log
    -- on every plugin load with no gate or rotation, growing the file unbounded.
    if _G.enabledebug ~= 1 then return end
    local path = ScriptUserPath .. "/debug.log"
    local pre = io.open(path, "r")
    local existed = pre ~= nil
    if pre then pre:close() end
    local f = io.open(path, "a")
    if not f then return end
    f:write(os.date("[%H:%M:%S][rightclick] ") .. tostring(msg) .. "\n")
    f:close()
    if not existed and type(SetSecureFileMode) == "function" then SetSecureFileMode(path) end
end
-- the plugin names need to have any newline characters removed
function loadPlugin(plugin)
    cancelPendingPluginLoad()
    if type(plugin) ~= "string" then return false end
    local pluginCleaned = plugin:match '^%s*(.*%S)' or ''
    pluginCleaned = pluginCleaned:gsub('^"(.*)"$', '%1')
    if pluginCleaned == "" or pluginCleaned:find("[%c]") then return false end
    local liveApp = getLiveHsAppObj and getLiveHsAppObj()
    rcLog("loadPlugin called: plugin=" .. tostring(pluginCleaned) .. " liveApp=" .. tostring(liveApp ~= nil))
    if not liveApp then return false end
    local requestGeneration = loadGeneration
    local loadSpeed = math.max(tonumber(_G.loadspeed) or 0.3, 0.1)
    local function isCurrentAndFocused()
        if requestGeneration ~= loadGeneration then return false end
        local ok, front = pcall(function() return liveApp:isFrontmost() end)
        return ok and front == true
    end
    local function schedule(delay, callback)
        pendingLoadTimer = hs.timer.doAfter(delay, function()
            if requestGeneration ~= loadGeneration then return end
            pendingLoadTimer = nil
            if not isCurrentAndFocused() then cancelPendingPluginLoad(); return end
            callback()
        end)
    end

    -- Capture modifier state NOW before any async delay; the user may release
    -- Cmd before the timer fires so we must snapshot it synchronously.
    local cmdHeld = hs.eventtap.checkKeyboardModifiers().cmd
    local tempautoadd
    if cmdHeld then
        if _G.autoadd == 1 then
            tempautoadd = 0
        elseif _G.autoadd == 0 then
            tempautoadd = 1
        else
            tempautoadd = _G.autoadd or 0
        end
    else
        tempautoadd = _G.autoadd or 0
    end

    local function doTypeAndAdd()
        rcLog("typing: plugin=" .. pluginCleaned .. " tempautoadd=" .. tostring(tempautoadd))
        hs.eventtap.keyStrokes(pluginCleaned, liveApp)
        pluginStats.recordUse(pluginCleaned)

        local function resetBookmark()
            if _G.resettobrowserbookmark == 1 then
                schedule(loadSpeed <= 0.5 and 0.1 or 0.3, bookmarkfunc)
            end
        end

        if tempautoadd == 1 then
            local addDelay = math.max(loadSpeed, 1.0)
            schedule(addDelay, function()
                rcLog("sending down+return+escape delay=" .. tostring(addDelay))
                hs.eventtap.keyStroke({}, "down", 0, liveApp)
                schedule(0.1, function()
                    hs.eventtap.keyStroke({}, "return", 0, liveApp)
                    hs.eventtap.keyStroke({}, "escape", 0, liveApp)
                    resetBookmark()
                end)
            end)
        else
            resetBookmark()
        end
    end

    rcLog("activating liveApp")
    local activated, result = pcall(function() return liveApp:activate() end)
    if not activated or result == false then return false end
    -- Use elapsed time so a busy run loop cannot extend the activation wait.
    local deadline = hs.timer.secondsSinceEpoch() + 2
    pendingLoadTimer = hs.timer.waitUntil(
        function()
            return requestGeneration ~= loadGeneration or isCurrentAndFocused() or hs.timer.secondsSinceEpoch() >= deadline
        end,
        function()
            if requestGeneration ~= loadGeneration then return end
            pendingLoadTimer = nil
            if not isCurrentAndFocused() then
                rcLog("Live activation timed out; plugin insertion cancelled")
                cancelPendingPluginLoad()
                return
            end
            hs.eventtap.keyStroke({"cmd"}, "f", 0, liveApp)
            schedule(loadSpeed, doTypeAndAdd)
        end,
        0.05
    )
    return true
end

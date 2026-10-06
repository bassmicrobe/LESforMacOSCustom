--  SPDX-License-Identifier: MIT
--
--  LES unit tests for menus/plugin.lua buildPluginMenu()
--
--  Exercises the menuconfig.ini -> nested menu-table builder WITHOUT Hammerspoon
--  by mocking hs + the few globals buildPluginMenu touches, writing a temp
--  menuconfig fixture, and inspecting the resulting `menu` / `_pluginCategories`
--  tables. Focus: correct folder nesting (regression net for the fragile parser).
--
--  Run via Docker: docker build -f Dockerfile.test -t les-test . && docker run --rm les-test

-- ── Sandbox / mocks ───────────────────────────────────────────────────
package.path = package.path .. ";extensions/les/?.lua"

rawset(_G, "hs", rawget(_G, "hs") or {
    timer = { secondsSinceEpoch = function() return 1 end },
})
rawset(_G, "loadPlugin", function() end)   -- fn closures reference it; never invoked here
rawset(_G, "L", function(key) return key end)
rawset(_G, "readme", function() end)

local _fixturePath = "/tmp/lua_les_plugin_menu_test.ini"
rawset(_G, "GetDataPath", function() return _fixturePath end)

-- plugin.lua defines its functions as real globals (no module return)
require("menus.plugin")

-- ── Helpers ───────────────────────────────────────────────────────────

--- Write `cfg` to the fixture path, reset menu state, and build.
--- Returns the root `menu` table.
local function build(cfg)
    local f = assert(io.open(_fixturePath, "w"))
    f:write(cfg)
    f:close()
    rawset(_G, "menu", {})
    rawset(_G, "pluginArray", nil)
    rawset(_G, "_pluginCategories", {})
    buildPluginMenu()
    return _G.menu
end

--- Find a menu entry by its title within a menu array.
local function item(menuTbl, title)
    if type(menuTbl) ~= "table" then return nil end
    for _, it in ipairs(menuTbl) do
        if it.title == title then return it end
    end
    return nil
end

--- Collect the titles of a menu array (order preserved).
local function titles(menuTbl)
    local out = {}
    if type(menuTbl) == "table" then
        for _, it in ipairs(menuTbl) do out[#out + 1] = it.title end
    end
    return out
end

local function hasTitle(menuTbl, title)
    return item(menuTbl, title) ~= nil
end

-- ── Tests ─────────────────────────────────────────────────────────────

describe("buildPluginMenu nesting", function()

    it("retains comma-bearing category names and nested sibling folders", function()
        local root = build([[
/Mix, Mastering
//Dynamics, Sidechain
Comp, Gate
"comp, gate"
..
//EQ, Filters
EQ, Wide
"eq, wide" vst
..
/Instrument, Synth
Soft, Warm
"soft, warm" au
End
]])
        local mixing = item(root, "Mix, Mastering")
        local instruments = item(root, "Instrument, Synth")
        assert.is_truthy(mixing and mixing.menu, "the complete category name must be retained")
        assert.is_truthy(instruments and instruments.menu)
        assert.are.same({ "Mix, Mastering", "Instrument, Synth" }, titles(root))
        assert.are.same({ "Dynamics, Sidechain", "EQ, Filters" }, titles(mixing.menu))

        local dynamics = item(mixing.menu, "Dynamics, Sidechain")
        local eq = item(mixing.menu, "EQ, Filters")
        local compressor = item(dynamics.menu, "Comp, Gate")
        local equalizer = item(eq.menu, "EQ, Wide")
        local synth = item(instruments.menu, "Soft, Warm")
        assert.is_truthy(compressor)
        assert.is_truthy(equalizer)
        assert.is_truthy(synth)
        local originalLoadPlugin = rawget(_G, "loadPlugin")
        local loaded = {}
        rawset(_G, "loadPlugin", function(query) loaded[#loaded + 1] = query:match("^%s*(.-)%s*$") end)
        compressor.fn()
        equalizer.fn()
        synth.fn()
        rawset(_G, "loadPlugin", originalLoadPlugin)
        assert.are.same({ '"comp, gate"', '"eq, wide" vst', '"soft, warm" au' }, loaded)
    end)

    it("retains commas in display names and queries alongside categories and separators", function()
        local root = build([[
Root, Utility
"root,utility" vst
/Effects
//Tools
🔴 Mix, Master
"mix, master, tools" au
--
Utility
"Utility"
End
]])
        local effects = item(root, "Effects")
        local tools = effects and item(effects.menu, "Tools")
        assert.is_truthy(tools and tools.menu, "the nested category must retain its hierarchy")
        local rootPlugin = item(root, "Root, Utility")
        local coloredPlugin = item(tools.menu, "🔴 Mix, Master")
        local utility = item(tools.menu, "Utility")
        assert.is_truthy(rootPlugin, "the root plugin name must retain its comma")
        assert.is_truthy(coloredPlugin, "the decorated plugin name must retain its comma")
        assert.is_truthy(utility, "ordinary plugin entries must remain loadable")
        assert.are.same({ "🔴 Mix, Master", "-", "Utility" }, titles(tools.menu))

        local originalLoadPlugin = rawget(_G, "loadPlugin")
        local loaded = {}
        rawset(_G, "loadPlugin", function(query) loaded[#loaded + 1] = query:match("^%s*(.-)%s*$") end)
        rootPlugin.fn()
        coloredPlugin.fn()
        utility.fn()
        rawset(_G, "loadPlugin", originalLoadPlugin)
        assert.are.same({ '"root,utility" vst', '"mix, master, tools" au', '"Utility"' }, loaded)
    end)

    it("preserves plugin names and search queries containing End", function()
        local root = build([[
/Effects
Endorphin
"Endorphin"
Blend
"Blend End"
End
]])
        local effects = item(root, "Effects")
        assert.is_truthy(effects and effects.menu)
        local endorphin = item(effects.menu, "Endorphin")
        local blend = item(effects.menu, "Blend")
        assert.is_truthy(endorphin, "Endorphin must not be treated as a terminator")
        assert.is_truthy(blend, "a query containing End must not remove its plugin")

        local originalLoadPlugin = rawget(_G, "loadPlugin")
        local loaded = {}
        rawset(_G, "loadPlugin", function(query) loaded[#loaded + 1] = query:match("^%s*(.-)%s*$") end)
        endorphin.fn()
        blend.fn()
        rawset(_G, "loadPlugin", originalLoadPlugin)
        assert.are.same({ '"Endorphin"', '"Blend End"' }, loaded)
    end)

    it("continues to accept surrounding whitespace and trailing comments on End markers", function()
        for _, marker in ipairs({ "End", "  End  ", "End ; required terminator", "End; required terminator" }) do
            local root = build('/Utility\nUtility\n"Utility"\n' .. marker .. "\n")
            local utility = item(root, "Utility")
            assert.is_truthy(utility and utility.menu)
            assert.are.same({ "Utility" }, titles(utility.menu))
        end
    end)

    it("builds a realistic two-level config (mirrors the default menuconfig.ini)", function()
        local root = build([[
/Instruments

//Synth
Analog
Analog
..

//Drums
Kick
Kick
..

/EQ
EQ Eight
EQ Eight

End
]])
        -- Root contains the two top-level categories.
        assert.is_truthy(item(root, "Instruments"), "root should contain Instruments; got: " .. table.concat(titles(root), ", "))
        assert.is_truthy(item(root, "EQ"), "root should contain EQ; got: " .. table.concat(titles(root), ", "))

        -- Instruments holds the two subfolders.
        local instr = item(root, "Instruments")
        assert.is_truthy(instr.menu, "Instruments should be a folder")
        assert.is_truthy(hasTitle(instr.menu, "Synth"), "Instruments should contain Synth; got: " .. table.concat(titles(instr.menu), ", "))
        assert.is_truthy(hasTitle(instr.menu, "Drums"), "Instruments should contain Drums; got: " .. table.concat(titles(instr.menu), ", "))

        -- Subfolders hold their plugins.
        assert.is_truthy(hasTitle(item(instr.menu, "Synth").menu, "Analog"))
        assert.is_truthy(hasTitle(item(instr.menu, "Drums").menu, "Kick"))

        -- EQ (a depth-1 folder with a direct plugin).
        assert.is_truthy(hasTitle(item(root, "EQ").menu, "EQ Eight"))

        -- Subfolders must NOT leak to the root.
        assert.is_falsy(hasTitle(root, "Synth"), "Synth must not appear at root")
        assert.is_falsy(hasTitle(root, "Drums"), "Drums must not appear at root")
    end)

    it("nests sibling subfolders under the correct parent after a deep-then-shallow excursion (#11)", function()
        -- Depths: A1  B2  C3  D4 (deep)  ->  back to root  ->  F2 under A,
        -- then G3 under F, back to F, then Gx3 — Gx must be a sibling of G
        -- under F (the old scopes stack mis-routed it under C).
        local root = build([[
/A
//B
///C
////D
Dp
Dp
..
..
..
//F
///G
Gp
Gp
..
///Gx
Gxp
Gxp
End
]])
        local a = item(root, "A")
        assert.is_truthy(a and a.menu, "root should contain folder A")

        -- A holds B and F as subfolders.
        assert.is_truthy(hasTitle(a.menu, "B"), "A should contain B; got: " .. table.concat(titles(a.menu), ", "))
        assert.is_truthy(hasTitle(a.menu, "F"), "A should contain F; got: " .. table.concat(titles(a.menu), ", "))

        -- F must hold BOTH G and Gx (the #11 bug nested Gx under C instead).
        local f = item(a.menu, "F")
        assert.is_truthy(f and f.menu, "F should be a folder")
        assert.is_truthy(hasTitle(f.menu, "G"), "F should contain G; got: " .. table.concat(titles(f.menu), ", "))
        assert.is_truthy(hasTitle(f.menu, "Gx"), "F should contain Gx (was mis-nested under C); got: " .. table.concat(titles(f.menu), ", "))

        -- The deep branch is intact: A > B > C > D > Dp.
        local b = item(a.menu, "B")
        local c = b and item(b.menu, "C")
        local d = c and item(c.menu, "D")
        assert.is_truthy(d and d.menu, "deep chain A>B>C>D should exist")
        assert.is_truthy(hasTitle(d.menu, "Dp"), "D should contain plugin Dp")

        -- Gx must not have leaked into C.
        assert.is_falsy(c and hasTitle(c.menu, "Gx"), "Gx must NOT be nested under C")
    end)
end)

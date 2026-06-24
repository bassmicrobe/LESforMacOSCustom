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

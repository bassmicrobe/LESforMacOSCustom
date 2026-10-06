--  SPDX-License-Identifier: MIT

package.path = package.path .. ";extensions/les/?.lua"

local function makeHarness(source)
    local state = { shiftedLines = 0 }
    local tables = setmetatable({}, { __index = table })
    tables.insert = function(destination, position, value)
        if value ~= nil then
            state.shiftedLines = state.shiftedLines + #destination - position + 1
            return table.insert(destination, position, value)
        end
        return table.insert(destination, position)
    end
    local environment = setmetatable({
        table = tables,
        MenuConfigFile = "menuconfig.ini",
        GetDataPath = function(path) return path end,
        fileToTable = function(_, destination)
            for _, line in ipairs(source) do destination[#destination + 1] = line end
            return true
        end,
        tableToFile = function(_, lines)
            state.persisted = lines
            return true
        end,
    }, { __index = _G })
    local scanner = assert(loadfile("extensions/les/vst/scanner.lua", "t", environment))()
    return scanner, state
end

describe("scanner menuconfig appends", function()
    it("appends before a comment-bearing End marker while preserving its text", function()
        for _, marker in ipairs({ "  End  ", "End ; required terminator", "End; required terminator" }) do
            local scanner, state = makeHarness({ "/Utility", "Endorphin", '"Endorphin"', marker, "; Footer" })
            local count, err = scanner.appendToMenuconfig({
                Endorphin = { category = "Utility", format = "VST3" },
                ["New Utility"] = { category = "Utility", format = "VST3" },
            })

            assert.is_nil(err)
            assert.are.equal(1, count)
            assert.are.equal(marker, state.persisted[#state.persisted - 1])
            assert.are.equal("; Footer", state.persisted[#state.persisted])
            assert.are.equal("New Utility", state.persisted[7])
        end
    end)

    it("keeps an existing plugin whose name starts with End without duplicating it", function()
        local scanner, state = makeHarness({ "/Utility", "Endorphin", '"Endorphin"', "End" })
        local count, err = scanner.appendToMenuconfig({
            Endorphin = { category = "Utility", format = "VST3" },
        })

        assert.is_nil(err)
        assert.are.equal(0, count)
        assert.is_nil(state.persisted)
    end)

    it("rejects a missing End marker even if a plugin name begins with End", function()
        local scanner, state = makeHarness({ "/Utility", "Endorphin", '"Endorphin"' })
        local count, err = scanner.appendToMenuconfig({
            ["New Utility"] = { category = "Utility", format = "VST3" },
        })

        assert.is_nil(count)
        assert.matches("End marker missing", err, 1, true)
        assert.is_nil(state.persisted)
    end)

    it("preserves ordering while avoiding quadratic line shifts for a large append", function()
        local source = { "; Existing header", "/Utility", "Existing Utility", '"Existing Utility"', "End", "; Footer" }
        local scanner, state = makeHarness(source)
        local additions = {}
        for index = 1, 1000 do
            additions[string.format("New Utility %04d", index)] = { category = "Utility", format = "VST3" }
        end

        local count, err = scanner.appendToMenuconfig(additions)

        assert.is_nil(err)
        assert.are.equal(1000, count)
        assert.are.same({ "; Existing header", "/Utility", "Existing Utility", '"Existing Utility"' },
            { table.unpack(state.persisted, 1, 4) })
        assert.are.equal("New Utility 0001", state.persisted[8])
        assert.are.equal("New Utility 1000", state.persisted[#state.persisted - 5])
        assert.are.equal("/nocategory", state.persisted[#state.persisted - 2])
        assert.are.equal("End", state.persisted[#state.persisted - 1])
        assert.are.equal("; Footer", state.persisted[#state.persisted])
        -- Count element relocations, rather than asserting wall-clock timing on a shared CI host.
        assert.is_true(state.shiftedLines <= #state.persisted * 2,
            "large appends must use linear element movement, got " .. state.shiftedLines .. " shifts")
    end)
end)

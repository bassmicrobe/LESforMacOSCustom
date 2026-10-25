-- SPDX-License-Identifier: MIT

local SOURCE_PATH = "extensions/les/util/io.lua"

local function createHarness(failure)
    local writes = {}
    local removed = {}
    local renames = {}
    local closeCalls = 0
    local secured = false
    local writeSecurity = {}
    local file = {}
    function file:write(value, newline)
        writeSecurity[#writeSecurity + 1] = secured
        if failure == "write" then return nil, "disk full" end
        writes[#writes + 1] = value .. newline
        return self
    end
    function file.flush()
        if failure == "flush" then return nil, "disk full" end
        return true
    end
    function file.close()
        closeCalls = closeCalls + 1
        if failure == "close" then return nil, "disk full" end
        return true
    end
    local environment = setmetatable({
        io = {open = function(path, mode)
            assert.are.equal("/fixture/settings.ini.tmp", path)
            assert.are.equal("w", mode)
            return file
        end},
        os = {
            remove = function(path) removed[#removed + 1] = path return true end,
            rename = function(from, to)
                renames[#renames + 1] = {from, to}
                return true
            end,
        },
        print = function() end,
        SetSecureFileMode = function()
            if failure == "permissions" then return false end
            secured = true
            return true
        end,
        hs = {fs = {symlinkAttributes = function()
            if failure == "symlink" then return {mode = "link"} end
        end}},
    }, {__index = _G})
    assert(loadfile(SOURCE_PATH, "t", environment))()
    return {
        save = environment.tableToFile,
        writes = writes,
        removed = removed,
        renames = renames,
        closeCalls = function() return closeCalls end,
        isSecured = function() return secured end,
        writeSecurity = writeSecurity,
    }
end

describe("atomic file save", function()
    it("secures the temporary file before writing sensitive content", function()
        local harness = createHarness()
        assert.is_true(harness.save("/fixture/settings.ini", {"openaikey = fixture-key"}))
        assert.is_true(harness.isSecured())
        assert.same({true}, harness.writeSecurity)
    end)

    it("does not write or replace the original when permissions cannot be secured", function()
        local harness = createHarness("permissions")
        assert.is_false(harness.save("/fixture/settings.ini", {"openaikey = fixture-key"}))
        assert.same({}, harness.writes)
        assert.same({}, harness.renames)
    end)

    it("does not follow a pre-existing temporary-file symlink", function()
        local harness = createHarness("symlink")
        assert.is_false(harness.save("/fixture/settings.ini", {"openaikey = fixture-key"}))
        assert.same({}, harness.writes)
        assert.same({}, harness.renames)
        assert.same({}, harness.removed)
        assert.are.equal(0, harness.closeCalls())
    end)

    for _, failure in ipairs({"write", "flush", "close"}) do
        it("keeps the original file after a " .. failure .. " failure", function()
            local harness = createHarness(failure)
            assert.is_false(harness.save("/fixture/settings.ini", {"openaikey = fixture-key"}))
            assert.are.equal(0, #harness.renames)
            assert.same({"/fixture/settings.ini.tmp"}, harness.removed)
            assert.are.equal(1, harness.closeCalls())
        end)
    end

    it("replaces the file only after all lines are flushed and closed", function()
        local harness = createHarness()
        assert.is_true(harness.save("/fixture/settings.ini", {"first", "second"}))
        assert.same({"first\n", "second\n"}, harness.writes)
        assert.same({{"/fixture/settings.ini.tmp", "/fixture/settings.ini"}}, harness.renames)
        assert.are.equal(0, #harness.removed)
        assert.are.equal(1, harness.closeCalls())
    end)
end)

describe("file read status", function()
    it("reports failure when closing the input file fails", function()
        local environment = setmetatable({
            io = {open = function()
                return {
                    lines = function() return ipairs({}) end,
                    close = function() return nil, "read error" end,
                }
            end},
        }, {__index = _G})
        assert(loadfile(SOURCE_PATH, "t", environment))()
        assert.is_false(environment.fileToTable("/fixture/settings.ini", {}))
    end)
end)

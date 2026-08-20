--  SPDX-License-Identifier: MIT

package.path = package.path .. ";extensions/les/?.lua"

local lfs = require("lfs")
local migration = require("util.migration")

local TEST_DIR = "/tmp/les_migration_'quoted_path"
local USER_INIT = TEST_DIR .. "/init.lua"
local BUNDLED_INIT = TEST_DIR .. "/jumpstart.lua"

local function writeFile(path, contents)
    local file = assert(io.open(path, "wb"))
    assert(file:write(contents))
    assert(file:close())
end

local function readFile(path)
    local file = assert(io.open(path, "rb"))
    local contents = assert(file:read("*a"))
    assert(file:close())
    return contents
end

describe("startup migration", function()
    before_each(function()
        os.remove(USER_INIT)
        os.remove(USER_INIT .. ".bak")
        os.remove(USER_INIT .. ".repair.tmp")
        os.remove(BUNDLED_INIT)
        lfs.rmdir(TEST_DIR)
        assert(lfs.mkdir(TEST_DIR))
    end)

    after_each(function()
        os.remove(USER_INIT)
        os.remove(USER_INIT .. ".bak")
        os.remove(USER_INIT .. ".repair.tmp")
        os.remove(BUNDLED_INIT)
        lfs.rmdir(TEST_DIR)
    end)

    it("compares files without invoking a shell", function()
        writeFile(USER_INIT, "same\0content")
        writeFile(BUNDLED_INIT, "same\0content")

        local differs, compareError = migration.filesDiffer(USER_INIT, BUNDLED_INIT)
        assert.is_nil(compareError)
        assert.is_false(differs)

        writeFile(BUNDLED_INIT, "different")
        differs, compareError = migration.filesDiffer(USER_INIT, BUNDLED_INIT)
        assert.is_nil(compareError)
        assert.is_true(differs)
    end)

    it("repairs paths containing a single quote and preserves a backup", function()
        writeFile(USER_INIT, "old init")
        writeFile(BUNDLED_INIT, "new init")
        local securedBeforeWrite = {}

        local ok, err = migration.repair(USER_INIT, BUNDLED_INIT, function(path)
            securedBeforeWrite[path] = lfs.attributes(path, "size") == 0
            return true
        end)

        assert.is_true(ok, err)
        assert.are.equal("new init", readFile(USER_INIT))
        assert.are.equal("old init", readFile(USER_INIT .. ".bak"))
        assert.is_true(securedBeforeWrite[USER_INIT .. ".bak.tmp"])
        assert.is_true(securedBeforeWrite[USER_INIT .. ".repair.tmp"])
        assert.is_nil(io.open(USER_INIT .. ".repair.tmp", "rb"))
    end)

    it("leaves the original intact when the bundled file is missing", function()
        writeFile(USER_INIT, "keep me")

        local ok, err = migration.repair(USER_INIT, BUNDLED_INIT)

        assert.is_false(ok)
        assert.is_string(err)
        assert.are.equal("keep me", readFile(USER_INIT))
    end)
end)

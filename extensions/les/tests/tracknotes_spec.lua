--  SPDX-License-Identifier: MIT

package.path = package.path .. ";extensions/les/?.lua"

local dkjson = require("dkjson")
local lfs = require("lfs")

local TEST_DIR = "/tmp/les_tracknotes_test"

local function mkdir(path)
    local current = ""
    for part in path:gmatch("[^/]+") do
        current = current .. "/" .. part
        lfs.mkdir(current)
    end
end

local hsGlobal = rawget(_G, "hs") or {}
hsGlobal.json = {
    decode = function(raw)
        local value, _, err = dkjson.decode(raw, 1, nil)
        if err then error(err) end
        return value
    end,
    encode = function(value, pretty)
        return dkjson.encode(value, { indent = pretty == true })
    end,
}
hsGlobal.timer = hsGlobal.timer or {}
hsGlobal.timer.secondsSinceEpoch = function() return 1234567890 end
local uuidSequence = 0
hsGlobal.host = hsGlobal.host or {}
hsGlobal.host.uuid = function()
    uuidSequence = uuidSequence + 1
    return "track-note-" .. tostring(uuidSequence)
end
hsGlobal.hash = hsGlobal.hash or {
    SHA256 = function(value)
        local total = 0
        for index = 1, #value do total = (total + value:byte(index) * index) % 0xFFFFFFFF end
        return string.format("%064x", total)
    end,
}
rawset(_G, "hs", hsGlobal)

rawset(_G, "ScriptUserResourcesPath", TEST_DIR)
rawset(_G, "strJoinPaths", function(left, right) return left .. "/" .. right end)
rawset(_G, "ShellCreateDirectory", mkdir)

package.loaded["util.noteid"] = nil
package.loaded["tracking.tracknotes"] = nil
local tracknotes = require("tracking.tracknotes")

local function writeLegacy(projectName, contents)
    mkdir(TEST_DIR .. "/tracknotes")
    local path = TEST_DIR .. "/tracknotes/" .. projectName .. ".json"
    local file = assert(io.open(path, "wb"))
    assert(file:write(contents))
    assert(file:close())
    return path
end

describe("track notes storage", function()
    before_each(function()
        mkdir(TEST_DIR .. "/tracknotes")
        for entry in lfs.dir(TEST_DIR .. "/tracknotes") do
            if entry ~= "." and entry ~= ".." then
                os.remove(TEST_DIR .. "/tracknotes/" .. entry)
            end
        end
    end)

    it("sanitizes malformed on-disk records before exposing them", function()
        writeLegacy("fixture", [[{
          "Lead": [
            {"ts": 12.9, "body": "ok"},
            {"ts": "13", "body": 42},
            {"ts": "bad", "body": "drop"},
            "drop"
          ],
          "Broken": "not-an-array"
        }]])

        local all = tracknotes.loadAll("fixture")

        assert.are.same({
            Lead = {
                { id = "legacy-12-1", ts = 12, body = "ok" },
                { id = "legacy-13-2", ts = 13, body = "42" },
            },
        }, all)
    end)

    it("recovers from a malformed track collection when adding a note", function()
        writeLegacy("fixture", [[{"Lead":"not-an-array"}]])

        assert.has_no.errors(function()
            assert.is_true(tracknotes.addNote("fixture", "Lead", "new note"))
        end)

        local saved = tracknotes.loadAll("fixture")
        assert.are.equal(1, #saved.Lead)
        assert.are.equal(1234567890, saved.Lead[1].ts)
        assert.are.equal("new note", saved.Lead[1].body)
        assert.is_string(saved.Lead[1].id)
    end)

    it("reports successful atomic writes", function()
        assert.is_true(tracknotes.saveAll("fixture", {
            Lead = {{ ts = 1, body = "saved" }},
        }))

        local all = tracknotes.loadAll("fixture")
        assert.are.equal("saved", all.Lead[1].body)
    end)

    it("deletes only the selected note when timestamps collide", function()
        assert.is_true(tracknotes.addNote("fixture", "Lead", "first"))
        assert.is_true(tracknotes.addNote("fixture", "Lead", "second"))

        local notes = tracknotes.loadAll("fixture").Lead
        assert.are.equal(2, #notes)
        assert.are_not.equal(notes[1].id, notes[2].id)
        assert.are.equal(notes[1].ts, notes[2].ts)

        assert.is_true(tracknotes.deleteNote("fixture", "Lead", notes[1].id))
        local remaining = tracknotes.loadAll("fixture").Lead
        assert.are.equal(1, #remaining)
        assert.are.equal(notes[2].id, remaining[1].id)
    end)
end)

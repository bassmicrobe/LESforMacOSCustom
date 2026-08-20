--  SPDX-License-Identifier: MIT

package.path = package.path .. ";extensions/les/?.lua"

local dkjson = require("dkjson")
local lfs = require("lfs")

local TEST_DIR = "/tmp/les_projectnotes_test"

local function mkdir(path)
    local current = ""
    for part in path:gmatch("[^/]+") do
        current = current .. "/" .. part
        lfs.mkdir(current)
    end
end

local uuidSequence = 0
local hsGlobal = rawget(_G, "hs") or {}
hsGlobal.json = {
    decode = function(raw)
        local value, _, err = dkjson.decode(raw, 1, nil)
        if err then error(err) end
        return value
    end,
    encode = function(value, pretty)
        return dkjson.encode(value, {indent = pretty == true})
    end,
}
hsGlobal.timer = hsGlobal.timer or {}
hsGlobal.timer.secondsSinceEpoch = function() return 1234567890 end
hsGlobal.host = hsGlobal.host or {}
hsGlobal.host.uuid = function()
    uuidSequence = uuidSequence + 1
    return "project-note-" .. tostring(uuidSequence)
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
package.loaded["tracking.projectnotes"] = nil
local projectnotes = require("tracking.projectnotes")

local function clearNotes()
    mkdir(TEST_DIR .. "/notes")
    for entry in lfs.dir(TEST_DIR .. "/notes") do
        if entry ~= "." and entry ~= ".." then os.remove(TEST_DIR .. "/notes/" .. entry) end
    end
end

describe("project notes storage", function()
    before_each(clearNotes)

    it("assigns stable legacy ids while sanitizing records", function()
        local legacy = TEST_DIR .. "/notes/fixture.json"
        local file = assert(io.open(legacy, "wb"))
        assert(file:write([[
            [{"timestamp":12.9,"body":"first"},{"timestamp":"12","body":"second"}]
        ]]))
        assert(file:close())

        assert.are.same({
            {id = "legacy-12-1", timestamp = 12, body = "first"},
            {id = "legacy-12-2", timestamp = 12, body = "second"},
        }, projectnotes.load("fixture"))
    end)

    it("deletes only the selected note when timestamps collide", function()
        assert.is_true(projectnotes.addNote("fixture", "first"))
        assert.is_true(projectnotes.addNote("fixture", "second"))

        local notes = projectnotes.load("fixture")
        assert.are.equal(2, #notes)
        assert.are_not.equal(notes[1].id, notes[2].id)
        assert.are.equal(notes[1].timestamp, notes[2].timestamp)

        assert.is_true(projectnotes.deleteNote("fixture", notes[1].id))
        local remaining = projectnotes.load("fixture")
        assert.are.equal(1, #remaining)
        assert.are.equal(notes[2].id, remaining[1].id)
    end)
end)

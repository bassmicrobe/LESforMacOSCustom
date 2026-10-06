--  SPDX-License-Identifier: MIT

package.path = package.path .. ";extensions/les/?.lua"

describe("asynchronous VST3 scanner", function()
    local environment
    local scheduled
    local reads
    local scanner
    local readNanoseconds
    local rawMetadata

    before_each(function()
        scheduled = {}
        reads = 0
        readNanoseconds = 0
        rawMetadata = '{"sub_categories":"Fx|Reverb"}'
        local elapsedNanoseconds = 0
        local hsMock = {
            fs = {
                dir = function(path)
                    local count = path == "/Library/Audio/Plug-Ins/VST3" and 51 or 0
                    local position = 0
                    return function()
                        position = position + 1
                        if position <= count then return "Plugin " .. position .. ".vst3" end
                    end
                end,
            },
            timer = {
                absoluteTime = function() return elapsedNanoseconds end,
                doAfter = function(_, callback)
                    scheduled[#scheduled + 1] = callback
                    return {}
                end,
            },
        }
        local function openMetadata()
            reads = reads + 1
            elapsedNanoseconds = elapsedNanoseconds + readNanoseconds
            return {
                read = function() return rawMetadata end,
                close = function() return true end,
            }
        end
        environment = setmetatable({hs = hsMock, io = {open = openMetadata}}, {__index = _G})
        scanner = assert(loadfile("extensions/les/vst/scanner.lua", "t", environment))()
    end)

    local function runNext()
        local callback = table.remove(scheduled, 1)
        assert.is_function(callback)
        callback()
    end

    it("yields between batches and returns every plugin once", function()
        assert.is_function(scanner.scanVST3Async)
        local completed
        local scanError
        local callbacks = 0
        scanner.scanVST3Async(function(results, err)
            completed = results
            scanError = err
            callbacks = callbacks + 1
        end)

        assert.are.equal(0, reads)
        runNext()
        assert.is_true(reads > 0 and reads <= 12)
        assert.is_nil(completed)

        while #scheduled > 0 do
            local previousReads = reads
            runNext()
            assert.is_true(reads - previousReads <= 12)
        end

        assert.is_nil(scanError)
        assert.are.equal(1, callbacks)
        assert.are.equal(51, #completed)
        assert.are.equal(51, reads)
        assert.are.same({name = "Plugin 51", format = "VST3", category = "Reverb"}, completed[51])
    end)

    it("reports read failures once without returning partial results", function()
        assert.is_function(scanner.scanVST3Async)
        environment.io.open = function() error("metadata read failed") end
        local completed
        local scanError
        local callbacks = 0
        scanner.scanVST3Async(function(results, err)
            completed = results
            scanError = err
            callbacks = callbacks + 1
        end)

        while #scheduled > 0 do runNext() end

        assert.is_nil(completed)
        assert.matches("metadata read failed", scanError, 1, true)
        assert.are.equal(1, callbacks)
    end)

    it("yields early when metadata reads exhaust the run-loop time budget", function()
        readNanoseconds = 6 * 1000 * 1000
        local completed
        local scanError
        scanner.scanVST3Async(function(results, err)
            completed, scanError = results, err
        end)

        runNext()
        assert.is_true(reads > 0 and reads <= 2, "slow metadata reads should not fill the entire 12-entry batch")
        assert.is_nil(completed)
        while #scheduled > 0 do
            local previousReads = reads
            runNext()
            assert.is_true(reads - previousReads <= 2)
        end

        assert.is_nil(scanError)
        assert.are.equal(51, #completed)
    end)

    it("keeps synchronous scanning available for non-UI callers", function()
        local results = scanner.scanVST3()
        assert.are.equal(51, #results)
        assert.are.equal(0, #scheduled)
    end)

    it("finds the next valid metadata value after an unsupported occurrence", function()
        rawMetadata = '{"sub_categories":null,"classes":[{"sub_categories":"Fx|Delay"}]}'
        local results = scanner.scanVST3()
        assert.are.equal("Delay", results[1].category)
    end)

    it("retains array subcategory metadata support", function()
        rawMetadata = '{"subcategories":["Fx|Dynamics","Fx"]}'
        local results = scanner.scanVST3()
        assert.are.equal("Compressor", results[1].category)
    end)

    it("retains the category metadata fallback", function()
        rawMetadata = '{"category":"Instrument|Synth"}'
        local results = scanner.scanVST3()
        assert.are.equal("Synthesizer", results[1].category)
    end)
end)

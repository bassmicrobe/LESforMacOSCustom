--  SPDX-License-Identifier: MIT

package.path = package.path .. ";extensions/les/?.lua"

local hsGlobal = rawget(_G, "hs") or {}
rawset(_G, "hs", hsGlobal)
hsGlobal.timer = hsGlobal.timer or {}
hsGlobal.timer.secondsSinceEpoch = hsGlobal.timer.secondsSinceEpoch or function() return 123 end

local SAMPLE_OUTPUT = [[
Audio:

    Example Synth:

      Type: Music Device

    Example Reverb:

      Type: Effect
]]

local scanner = require("vst.scanner")

describe("plugin scanner", function()
    it("parses Audio Unit output independently from process execution", function()
        local results = scanner.parseAUOutput(SAMPLE_OUTPUT)

        assert.are.equal(2, #results)
        assert.are.same({
            name = "Example Synth",
            format = "AU",
            category = "Synthesizer",
        }, results[1])
        assert.are.same({
            name = "Example Reverb",
            format = "AU",
            category = "Reverb",
        }, results[2])
    end)

    it("runs system_profiler through hs.task without a shell", function()
        local launchPath
        local launchArgs
        local callbackResult
        local callbackError

        hsGlobal.task = {
            new = function(path, callback, args)
                launchPath = path
                launchArgs = args
                return {
                    start = function()
                        callback(0, SAMPLE_OUTPUT, "")
                        return true
                    end,
                }
            end,
        }

        local task, err = scanner.scanAUAsync(function(results, scanErr)
            callbackResult = results
            callbackError = scanErr
        end)

        assert.is_not_nil(task, err)
        assert.are.equal("/usr/sbin/system_profiler", launchPath)
        assert.are.same({"SPAudioDataType"}, launchArgs)
        assert.is_nil(callbackError)
        assert.are.equal(2, #callbackResult)
    end)

    it("reports a failed background scan without parsing partial output", function()
        hsGlobal.task = {
            new = function(_, callback)
                return {
                    start = function()
                        callback(1, "partial", "failed")
                        return true
                    end,
                }
            end,
        }

        local callbackResult
        local callbackError
        scanner.scanAUAsync(function(results, scanErr)
            callbackResult = results
            callbackError = scanErr
        end)

        assert.is_nil(callbackResult)
        assert.matches("system_profiler", callbackError, 1, true)
    end)

    it("does not report appended plugins when menuconfig persistence fails", function()
        local originalGetDataPath = rawget(_G, "GetDataPath")
        local originalMenuConfigFile = rawget(_G, "MenuConfigFile")
        local originalFileToTable = rawget(_G, "fileToTable")
        local originalTableToFile = rawget(_G, "tableToFile")

        rawset(_G, "GetDataPath", function(path) return path end)
        rawset(_G, "MenuConfigFile", "menuconfig.ini")
        rawset(_G, "fileToTable", function(_, destination)
            destination[#destination + 1] = "End"
            return true
        end)
        rawset(_G, "tableToFile", function() return false end)

        local appended, err = scanner.appendToMenuconfig({
            ["New Utility"] = {category = "Utility", format = "VST3"},
        })

        rawset(_G, "GetDataPath", originalGetDataPath)
        rawset(_G, "MenuConfigFile", originalMenuConfigFile)
        rawset(_G, "fileToTable", originalFileToTable)
        rawset(_G, "tableToFile", originalTableToFile)

        assert.is_nil(appended)
        assert.matches("menuconfig", err, 1, true)
    end)

    it("does not create an invalid menuconfig when the End marker is missing", function()
        local originalGetDataPath = rawget(_G, "GetDataPath")
        local originalMenuConfigFile = rawget(_G, "MenuConfigFile")
        local originalFileToTable = rawget(_G, "fileToTable")
        local originalTableToFile = rawget(_G, "tableToFile")
        local wrote = false

        rawset(_G, "GetDataPath", function(path) return path end)
        rawset(_G, "MenuConfigFile", "menuconfig.ini")
        rawset(_G, "fileToTable", function(_, destination)
            destination[#destination + 1] = "/Utility"
            return true
        end)
        rawset(_G, "tableToFile", function()
            wrote = true
            return true
        end)

        local appended, err = scanner.appendToMenuconfig({
            ["New Utility"] = {category = "Utility", format = "VST3"},
        })

        rawset(_G, "GetDataPath", originalGetDataPath)
        rawset(_G, "MenuConfigFile", originalMenuConfigFile)
        rawset(_G, "fileToTable", originalFileToTable)
        rawset(_G, "tableToFile", originalTableToFile)

        assert.is_nil(appended)
        assert.matches("End", err, 1, true)
        assert.is_false(wrote)
    end)

    it("refuses to replace menuconfig when its backup cannot be created", function()
        assert.is_function(scanner.saveGeneratedMenuconfig)

        local originalGetDataPath = rawget(_G, "GetDataPath")
        local originalMenuConfigFile = rawget(_G, "MenuConfigFile")
        local originalPresent = rawget(_G, "ioIsFilePresent")
        local originalCopy = rawget(_G, "ShellCopy")
        local originalTableToFile = rawget(_G, "tableToFile")
        local wrote = false

        rawset(_G, "GetDataPath", function(path) return path end)
        rawset(_G, "MenuConfigFile", "menuconfig.ini")
        rawset(_G, "ioIsFilePresent", function() return true end)
        rawset(_G, "ShellCopy", function() return false end)
        rawset(_G, "tableToFile", function()
            wrote = true
            return true
        end)

        local ok, err = scanner.saveGeneratedMenuconfig({}, 123)

        rawset(_G, "GetDataPath", originalGetDataPath)
        rawset(_G, "MenuConfigFile", originalMenuConfigFile)
        rawset(_G, "ioIsFilePresent", originalPresent)
        rawset(_G, "ShellCopy", originalCopy)
        rawset(_G, "tableToFile", originalTableToFile)

        assert.is_false(ok)
        assert.matches("backup", err, 1, true)
        assert.is_false(wrote)
    end)

    it("surfaces cache persistence failure from an incremental scan", function()
        local originalLoadCache = scanner.loadCache
        local originalFullScan = scanner.fullScan
        local originalSaveCache = scanner.saveCache

        scanner.loadCache = function() return {plugins = {}, scanned_at = 0} end
        scanner.fullScan = function()
            return {Utility = {category = "Utility", format = "VST3"}}
        end
        scanner.saveCache = function() return false end

        local added, removed, all, err = scanner.incrementalScan()

        scanner.loadCache = originalLoadCache
        scanner.fullScan = originalFullScan
        scanner.saveCache = originalSaveCache

        assert.is_table(added)
        assert.is_table(removed)
        assert.is_table(all)
        assert.matches("cache", err, 1, true)
    end)

    it("does not start a forced scan when clearing the cache fails", function()
        local originalSaveCache = scanner.saveCache
        local originalScanAndPrompt = scanner.scanAndPrompt
        local originalAlert = rawget(_G, "HSMakeAlert")
        local originalProgramName = rawget(_G, "programName")
        local scanStarted = false
        local alertMessage = nil

        scanner.saveCache = function() return false end
        scanner.scanAndPrompt = function() scanStarted = true end
        rawset(_G, "HSMakeAlert", function(_, message) alertMessage = message end)
        rawset(_G, "programName", "LES Test")

        local started = scanner.forceFullScan()

        scanner.saveCache = originalSaveCache
        scanner.scanAndPrompt = originalScanAndPrompt
        rawset(_G, "HSMakeAlert", originalAlert)
        rawset(_G, "programName", originalProgramName)

        assert.is_false(started)
        assert.is_false(scanStarted)
        assert.matches("cache", alertMessage, 1, true)
    end)
end)

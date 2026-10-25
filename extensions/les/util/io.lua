--  SPDX-License-Identifier: MIT
--
--  Copyright (c) 2019-2023 LESforMacOS authors, see AUTHORS.txt
--  for a list
--
--  Distributed under the MIT software license, see the accompanying
--  file COPYING.txt or visit https://opensource.org/license/mit/

-- Converts a file to a newline-separated index table
function fileToTable(filePath, retTable)
  local fileHdl = io.open(filePath, "r")
  if not fileHdl then
    return false
  end
  for _line in fileHdl:lines() do
    table.insert(retTable, _line)
  end
  local closed, closeErr = fileHdl:close()
  if not closed then
    print("fileToTable(): failed to close input file: " .. tostring(closeErr))
    return false
  end
  return true
end

-- Converts an index table into a newline-seperated file.
-- WARNING: tableToFile does not append, it overwrites.
-- The write is ATOMIC: contents are written to a sibling temp file and then
-- os.rename()'d over the destination, so an interrupted/failed save never
-- leaves a half-written (corrupt) file behind. os.rename is atomic on the
-- same filesystem; the temp file lives next to the target to guarantee that.
---@param filePath string
---@param retTable table
---@return boolean ok
function tableToFile(filePath, retTable)
  local tmpPath = filePath .. ".tmp"
  -- Never follow an existing link/device at the scratch path. The settings
  -- directory is private; checking before opening also avoids stale links
  -- left by another tool overwriting an unrelated file.
  if hs and hs.fs and type(hs.fs.symlinkAttributes) == "function" then
    local inspected, attrs = pcall(hs.fs.symlinkAttributes, tmpPath)
    if not inspected or (attrs and attrs.mode ~= "file") then
      print("tableToFile(): unsafe temporary path; keeping original file")
      return false
    end
  end
  local fileHdl = io.open(tmpPath, "w")
  if not fileHdl then
    print("tableToFile(): failed to open for write: " .. tostring(tmpPath))
    return false
  end
  local function discardTemp(stage, err, alreadyClosed)
    if not alreadyClosed then fileHdl:close() end
    os.remove(tmpPath)
    print("tableToFile(): failed to " .. stage .. " temp file: " .. tostring(err))
    return false
  end
  -- A new file starts with the process umask. Restrict the empty file BEFORE
  -- writing any API key, and fail closed if chmod fails. This also keeps 600
  -- permissions across the atomic rename without a shell stat subprocess.
  local secured, modeOK = pcall(function()
    if type(SetSecureFileMode) == "function" then return SetSecureFileMode(tmpPath) end
    -- util.io is also usable before helpers.lua is loaded.
    return os.execute("chmod 600 " .. strQuote(tmpPath)) == true
  end)
  if not secured or modeOK ~= true then return discardTemp("secure", "owner-only permissions unavailable") end
  local maxIdx = 0
  for k in pairs(retTable) do
    if type(k) == "number" and k > maxIdx then
      maxIdx = k
    end
  end
  for idx = 1, maxIdx do
    local val = retTable[idx]
    if val ~= nil then
      local written, writeErr = fileHdl:write(val, "\n")
      if not written then return discardTemp("write", writeErr) end
    end
  end
  local flushed, flushErr = fileHdl:flush()
  if not flushed then return discardTemp("flush", flushErr) end
  local closed, closeErr = fileHdl:close()
  if not closed then return discardTemp("close", closeErr, true) end
  local renamed, renameErr = os.rename(tmpPath, filePath)
  if not renamed then
    os.remove(tmpPath)
    print("tableToFile(): failed to rename temp over destination: " .. tostring(renameErr))
    return false
  end
  return true
end

-- Checks if a file is present
function ioIsFilePresent(fileName)
  local fileHdl = io.open(fileName, "r")
  if fileHdl ~= nil then
      fileHdl:close()
      return true
  else
      return false
  end
end

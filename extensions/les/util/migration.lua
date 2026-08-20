--  SPDX-License-Identifier: MIT
--  Safe startup migration helpers. No command is evaluated by a shell.

local migration = {}

local CHUNK_SIZE = 64 * 1024

local function validatePath(path, label)
    if type(path) ~= "string" or path == "" then
        return nil, string.format("%s path must be a non-empty string", label)
    end
    return true
end

local function copyFile(sourcePath, destinationPath, secureFile)
    local valid, validationError = validatePath(sourcePath, "source")
    if not valid then return false, validationError end
    valid, validationError = validatePath(destinationPath, "destination")
    if not valid then return false, validationError end

    local source, sourceError = io.open(sourcePath, "rb")
    if not source then
        return false, string.format("unable to open source %q: %s", sourcePath, tostring(sourceError))
    end

    local destination, destinationError = io.open(destinationPath, "wb")
    if not destination then
        source:close()
        return false, string.format("unable to open destination %q: %s", destinationPath, tostring(destinationError))
    end
    if secureFile and not secureFile(destinationPath) then
        destination:close()
        source:close()
        os.remove(destinationPath)
        return false, string.format("unable to secure destination %q", destinationPath)
    end

    while true do
        local chunk, readError = source:read(CHUNK_SIZE)
        if not chunk then
            if readError then
                destination:close()
                source:close()
                os.remove(destinationPath)
                return false, string.format("unable to read %q: %s", sourcePath, tostring(readError))
            end
            break
        end

        local written, writeError = destination:write(chunk)
        if not written then
            destination:close()
            source:close()
            os.remove(destinationPath)
            return false, string.format("unable to write %q: %s", destinationPath, tostring(writeError))
        end
    end

    local sourceClosed, sourceCloseError = source:close()
    local destinationClosed, destinationCloseError = destination:close()
    if not sourceClosed or not destinationClosed then
        os.remove(destinationPath)
        return false, string.format(
            "unable to finalize copy: source=%s destination=%s",
            tostring(sourceCloseError),
            tostring(destinationCloseError)
        )
    end

    return true
end

--- Compare two files in bounded chunks.
---@param leftPath string
---@param rightPath string
---@return boolean|nil differ
---@return string|nil err
function migration.filesDiffer(leftPath, rightPath)
    local valid, validationError = validatePath(leftPath, "left")
    if not valid then return nil, validationError end
    valid, validationError = validatePath(rightPath, "right")
    if not valid then return nil, validationError end

    local left, leftError = io.open(leftPath, "rb")
    if not left then
        return nil, string.format("unable to open %q: %s", leftPath, tostring(leftError))
    end

    local right, rightError = io.open(rightPath, "rb")
    if not right then
        left:close()
        return nil, string.format("unable to open %q: %s", rightPath, tostring(rightError))
    end

    while true do
        local leftChunk, leftReadError = left:read(CHUNK_SIZE)
        local rightChunk, rightReadError = right:read(CHUNK_SIZE)
        if leftReadError or rightReadError then
            left:close()
            right:close()
            return nil, string.format(
                "file comparison failed: left=%s right=%s",
                tostring(leftReadError),
                tostring(rightReadError)
            )
        end
        if leftChunk ~= rightChunk then
            left:close()
            right:close()
            return true
        end
        if leftChunk == nil then
            left:close()
            right:close()
            return false
        end
    end
end

--- Back up the user's init file, then atomically replace it with the bundled file.
---@param userInitPath string
---@param bundledInitPath string
---@param secureFile fun(path: string): boolean|nil
---@return boolean ok
---@return string|nil err
function migration.repair(userInitPath, bundledInitPath, secureFile)
    local backupPath = userInitPath .. ".bak"
    local backupTempPath = backupPath .. ".tmp"
    local installTempPath = userInitPath .. ".repair.tmp"

    os.remove(backupTempPath)
    os.remove(installTempPath)

    local backupOk, backupError = copyFile(userInitPath, backupTempPath, secureFile)
    if not backupOk then return false, backupError end

    local installOk, installError = copyFile(bundledInitPath, installTempPath, secureFile)
    if not installOk then
        os.remove(backupTempPath)
        return false, installError
    end

    local backupRenamed, backupRenameError = os.rename(backupTempPath, backupPath)
    if not backupRenamed then
        os.remove(backupTempPath)
        os.remove(installTempPath)
        return false, string.format("unable to install backup %q: %s", backupPath, tostring(backupRenameError))
    end

    local installed, installRenameError = os.rename(installTempPath, userInitPath)
    if not installed then
        os.remove(installTempPath)
        return false, string.format("unable to replace %q: %s", userInitPath, tostring(installRenameError))
    end

    return true
end

return migration

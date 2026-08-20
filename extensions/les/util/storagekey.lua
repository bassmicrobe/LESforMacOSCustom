--  SPDX-License-Identifier: MIT
--  Collision-resistant, bounded filenames for per-project local data.

local storageKey = {}

local DEFAULT_PROJECT_NAME = "unsaved_project"
local MAX_READABLE_LENGTH = 80

local function defaultSHA256(value)
    if not hs or not hs.hash or type(hs.hash.SHA256) ~= "function" then
        error("hs.hash.SHA256 is required to build a project storage key", 2)
    end
    return hs.hash.SHA256(value)
end

--- Build a readable key plus the full SHA-256 digest of the original name.
--- The digest prevents names such as "Client A", "Client-A", and "Client/A"
--- from sharing the same notes or timer file after punctuation is sanitized.
---@param projectName string|nil
---@param hasher fun(value: string): string|nil  test injection only
---@return string
function storageKey.forProject(projectName, hasher)
    local rawName = type(projectName) == "string" and projectName or DEFAULT_PROJECT_NAME
    if rawName == "" then rawName = DEFAULT_PROJECT_NAME end

    local readable = rawName:gsub("[^%w_-]+", "_"):gsub("_+", "_")
    readable = readable:gsub("^_+", ""):gsub("_+$", "")
    if readable == "" then readable = "project" end
    readable = readable:sub(1, MAX_READABLE_LENGTH)

    local digest = (hasher or defaultSHA256)(rawName)
    if type(digest) ~= "string" or not digest:match("^[0-9a-fA-F]+$") or #digest < 64 then
        error("project storage key hasher must return a SHA-256 hex digest", 2)
    end

    return readable .. "_" .. digest:sub(1, 64):lower()
end

return storageKey

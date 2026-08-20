--  SPDX-License-Identifier: MIT

local appidentity = {}

local LIVE_BUNDLE_ID = "com.ableton.live"

--- Return true only for Ableton Live's exact bundle identifier.
---@param bundleID string|nil
---@return boolean
function appidentity.isLiveBundleID(bundleID)
    return type(bundleID) == "string" and bundleID == LIVE_BUNDLE_ID
end

return appidentity

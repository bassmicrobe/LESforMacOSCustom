--  SPDX-License-Identifier: MIT

package.path = package.path .. ";extensions/les/?.lua"

local appidentity = require("util.appidentity")

describe("Ableton Live application identity", function()
    it("accepts only the exact Ableton bundle identifier", function()
        assert.is_true(appidentity.isLiveBundleID("com.ableton.live"))
        assert.is_false(appidentity.isLiveBundleID("com.ableton.live.beta"))
        assert.is_false(appidentity.isLiveBundleID("Live"))
        assert.is_false(appidentity.isLiveBundleID(nil))
    end)
end)

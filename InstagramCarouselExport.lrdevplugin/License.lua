--[[
  Placeholder for a future Free vs Pro unlock.

  Right now everything is unlocked (full 2–5 slides) so we can ship
  GitHub updates without a store/license flow. Flip this later.
]]

local LrPrefs = import "LrPrefs"

local License = {}

-- Keep true until free/paid is implemented.
License.forcePro = true

local prefs = LrPrefs.prefsForPlugin()

function License.isPro()
    if License.forcePro then
        return true
    end
    local key = tostring(prefs.licenseKey or "")
    return key ~= "" and prefs.licenseValid == true
end

function License.maxColumns()
    if License.isPro() then
        return 5
    end
    return 3
end

function License.setLicenseKey(key, valid)
    prefs.licenseKey = tostring(key or "")
    prefs.licenseValid = valid == true
end

function License.statusText()
    local v = (_PLUGIN and _PLUGIN.version) or {}
    return ("Instagram Carousel Export %d.%d.%d.%d")
        :format(v.major or 1, v.minor or 0, v.revision or 0, v.build or 0)
end

return License

--[[
  Free vs Full Licence

  Free:
    - 4:5 only
    - 2–3 slides
    - Matching presets only
    - Buy me a coffee + Buy full licence

  Full (paid build or activated key):
    - 3:4 + 4:5
    - 2–5 slides
    - Full preset set
    - No upsell buttons

  Paid zip: set License.forcePro = true before packaging.
  Free zip: leave forcePro = false; buyers unlock with a licence key.
]]

local LrBinding = import "LrBinding"
local LrDialogs = import "LrDialogs"
local LrFileUtils = import "LrFileUtils"
local LrFunctionContext = import "LrFunctionContext"
local LrHttp = import "LrHttp"
local LrPathUtils = import "LrPathUtils"
local LrPrefs = import "LrPrefs"
local LrView = import "LrView"

local License = {}

-- true = ship as paid/full build (no upsell UI, all features).
License.forcePro = false

License.BUY_ME_A_COFFEE_URL = "https://buymeacoffee.com/garethgabriel"
-- Replace with Gumroad / Lemon Squeezy checkout when live.
License.BUY_LICENCE_URL = "https://garethgabriel.com"

-- Temporary unlock key for testing / early buyers. Replace with signed keys later.
local UNLOCK_KEYS = {
    ["ICE-PRO-UNLOCK"] = true,
}

local prefs = LrPrefs.prefsForPlugin()

local function normalizeKey(key)
    return tostring(key or ""):upper():gsub("%s+", ""):gsub("_", "-")
end

function License.isPro()
    if License.forcePro then
        return true
    end
    if prefs.licenseValid == true then
        return true
    end
    local key = normalizeKey(prefs.licenseKey)
    return key ~= "" and UNLOCK_KEYS[key] == true
end

function License.minColumns()
    return 2
end

function License.maxColumns()
    if License.isPro() then
        return 5
    end
    return 3
end

function License.allowedAspects()
    if License.isPro() then
        return { "3:4", "4:5" }
    end
    return { "4:5" }
end

function License.defaultAspect()
    return "4:5"
end

function License.isAspectAllowed(aspectKey)
    for _, allowed in ipairs(License.allowedAspects()) do
        if allowed == aspectKey then
            return true
        end
    end
    return false
end

function License.clampColumns(columns)
    local value = tonumber(columns) or 3
    local minColumns = License.minColumns()
    local maxColumns = License.maxColumns()
    if value < minColumns then
        return minColumns
    end
    if value > maxColumns then
        return maxColumns
    end
    return value
end

function License.clampAspect(aspectKey)
    if License.isAspectAllowed(aspectKey) then
        return aspectKey
    end
    return License.defaultAspect()
end

function License.columnOptions(labelSuffix)
    labelSuffix = labelSuffix or ""
    local options = {}
    for columns = License.minColumns(), License.maxColumns() do
        options[#options + 1] = {
            title = tostring(columns) .. labelSuffix,
            value = columns,
        }
    end
    return options
end

function License.aspectOptions()
    local titles = {
        ["3:4"] = "3:4 portrait",
        ["4:5"] = "4:5 portrait",
    }
    local options = {}
    for _, aspect in ipairs(License.allowedAspects()) do
        options[#options + 1] = {
            title = titles[aspect] or aspect,
            value = aspect,
        }
    end
    return options
end

function License.presetAspects()
    return License.allowedAspects()
end

function License.setLicenseKey(key, valid)
    prefs.licenseKey = tostring(key or "")
    prefs.licenseValid = valid == true
end

function License.activateKey(key)
    local normalized = normalizeKey(key)
    if normalized == "" then
        return false, "Enter a licence key."
    end
    if UNLOCK_KEYS[normalized] then
        License.setLicenseKey(normalized, true)
        return true, "Full licence activated. Re-open Export / the Crop Ratio Helper to see all options."
    end
    return false, "That licence key is not valid."
end

function License.clearLicense()
    License.setLicenseKey("", false)
end

local function versionFromInfoLua()
    local root = _PLUGIN and _PLUGIN.path
    if not root then
        return nil
    end
    local infoPath = LrPathUtils.child(root, "Info.lua")
    if LrFileUtils.exists(infoPath) ~= "file" then
        return nil
    end
    local body = LrFileUtils.readFile(infoPath) or ""
    local block = body:match("VERSION%s*=%s*{([^}]+)}")
    if not block then
        return nil
    end
    return {
        major = tonumber(block:match("major%s*=%s*(%d+)")) or 0,
        minor = tonumber(block:match("minor%s*=%s*(%d+)")) or 0,
        revision = tonumber(block:match("revision%s*=%s*(%d+)")) or 0,
        build = tonumber(block:match("build%s*=%s*(%d+)")) or 0,
    }
end

function License.currentVersionLabel()
    local v = versionFromInfoLua() or (_PLUGIN and _PLUGIN.version) or {}
    if type(v) ~= "table" then
        v = {}
    end
    return ("%d.%d.%d.%d"):format(
        tonumber(v.major) or 1,
        tonumber(v.minor) or 0,
        tonumber(v.revision) or 0,
        tonumber(v.build) or 0
    )
end

function License.statusText()
    local version = License.currentVersionLabel()
    if License.isPro() then
        if License.forcePro then
            return ("Full licence · %s"):format(version)
        end
        return ("Full licence activated · %s"):format(version)
    end
    return ("Free · 4:5 · 2–3 slides · %s"):format(version)
end

function License.openBuyMeACoffee()
    pcall(function()
        LrHttp.openUrlInBrowser(License.BUY_ME_A_COFFEE_URL)
    end)
end

function License.openBuyLicence()
    pcall(function()
        LrHttp.openUrlInBrowser(License.BUY_LICENCE_URL)
    end)
end

function License.promptActivate()
    LrFunctionContext.callWithContext("InstagramCarouselActivateLicence", function(context)
        local f = LrView.osFactory()
        local bind = LrView.bind
        local props = LrBinding.makePropertyTable(context)
        props.licenseKey = tostring(prefs.licenseKey or "")
        props.status = ""

        local result = LrDialogs.presentModalDialog({
            title = "Activate Full Licence",
            contents = f:column {
                bind_to_object = props,
                spacing = f:control_spacing(),
                f:static_text {
                    title = "Enter the licence key from your purchase email.",
                    fill_horizontal = 1,
                },
                f:row {
                    spacing = f:label_spacing(),
                    f:static_text { title = "Licence key", width = 90, alignment = "right" },
                    f:edit_field {
                        value = bind("licenseKey"),
                        width_in_chars = 28,
                    },
                },
                f:static_text {
                    title = bind("status"),
                    fill_horizontal = 1,
                },
            },
            actionVerb = "Activate",
            cancelVerb = "Cancel",
        })

        if result == "ok" then
            local ok, message = License.activateKey(props.licenseKey)
            if ok then
                LrDialogs.message("Licence Activated", message, "info")
            else
                LrDialogs.message("Activation Failed", message, "warning")
            end
        end
    end)
end

return License

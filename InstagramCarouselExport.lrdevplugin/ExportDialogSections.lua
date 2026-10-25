local LrView = import "LrView"
local LrHttp = import "LrHttp"

local License = require "License"
local UpdateService = require "UpdateService"

local ExportDialogSections = {}
local GARETH_URL = "https://garethgabriel.com"
local STUDIO_URL = "https://thestudiosheringham.com"
local SUPPORT_EMAIL_URL = "mailto:support@thestudiosheringham.com"
local ASPECT_OPTIONS = {
    { title = "3:4 portrait", value = "3:4" },
    { title = "4:5 portrait", value = "4:5" },
}

local function columnOptions()
    local options = {
        { title = "2", value = 2 },
        { title = "3", value = 3 },
    }
    if License.isPro() then
        options[#options + 1] = { title = "4", value = 4 }
        options[#options + 1] = { title = "5", value = 5 }
    else
        options[#options + 1] = { title = "4 (Pro)", value = 4 }
        options[#options + 1] = { title = "5 (Pro)", value = 5 }
    end
    return options
end

local CROP_MODE_OPTIONS = {
    { title = "Use existing Lightroom crop first (fallback to center crop)", value = "existing_first" },
    { title = "Always center crop", value = "center_crop" },
}

local function gcd(a, b)
    a = math.abs(math.floor(a))
    b = math.abs(math.floor(b))
    while b ~= 0 do
        a, b = b, a % b
    end
    return a
end

local function overallRatioText(columns, aspectKey)
    local tileWidth = (aspectKey == "3:4") and 3 or 4
    local tileHeight = (aspectKey == "3:4") and 4 or 5
    local num = columns * tileWidth
    local den = tileHeight
    local div = gcd(num, den)
    return ("%d:%d"):format(num / div, den / div)
end

local function overallRatioDecimal(columns, aspectKey)
    local tileWidth = (aspectKey == "3:4") and 3 or 4
    local tileHeight = (aspectKey == "3:4") and 4 or 5
    local num = columns * tileWidth
    local den = tileHeight
    return num / den
end

local function openExternal(url)
    if not url or url == "" then
        return
    end
    pcall(function()
        LrHttp.openUrlInBrowser(url)
    end)
end

local PRESET_OPTIONS = {
    { title = "Custom", value = "custom" },
}

for _, aspect in ipairs({ "3:4", "4:5" }) do
    for columns = 2, 5 do
        PRESET_OPTIONS[#PRESET_OPTIONS + 1] = {
            title = ("IG Carousel x%d (%s)"):format(columns, aspect),
            value = ("%d_%s"):format(columns, aspect:gsub(":", "x")),
        }
    end
end

local function parsePreset(presetValue)
    if not presetValue or presetValue == "custom" then
        return nil
    end
    local columns, aspectA, aspectB = presetValue:match("^(%d+)_(%d)x(%d)$")
    if not columns then
        -- Backward compatibility with old saved presets.
        columns, aspectA, aspectB = presetValue:match("^(%d+)x3_(%d)x(%d)$")
    end
    if not columns then
        return nil
    end
    return tonumber(columns), ("%s:%s"):format(aspectA, aspectB)
end

local function updateCropHelper(propertyTable)
    local columns = tonumber(propertyTable.carouselColumns) or 3
    local ratio = propertyTable.carouselAspect or "4:5"
    propertyTable.carouselOverallCropRatioValue = overallRatioText(columns, ratio)
    propertyTable.carouselOverallCropDecimalValue = overallRatioDecimal(columns, ratio)
    propertyTable.carouselOverallCropDecimalText = ("Decimal: %.4f"):format(propertyTable.carouselOverallCropDecimalValue)
    propertyTable.carouselOverallCropRatio = ("Suggested Develop Crop ratio: %s (overall frame)")
        :format(propertyTable.carouselOverallCropRatioValue)
end

local function syncFromPrefixedFields(propertyTable)
    if propertyTable.LR_carouselColumns ~= nil then
        propertyTable.carouselColumns = tonumber(propertyTable.LR_carouselColumns) or propertyTable.carouselColumns
    end
    if propertyTable.LR_carouselAspect ~= nil then
        propertyTable.carouselAspect = propertyTable.LR_carouselAspect
    end
    if propertyTable.LR_carouselPreset ~= nil then
        propertyTable.carouselPreset = propertyTable.LR_carouselPreset
    end
    if propertyTable.LR_carouselCropMode ~= nil then
        propertyTable.carouselCropMode = propertyTable.LR_carouselCropMode
    end
    if propertyTable.LR_carouselTileWidthPx ~= nil then
        propertyTable.carouselTileWidthPx = tonumber(propertyTable.LR_carouselTileWidthPx) or propertyTable.carouselTileWidthPx
    end
    if propertyTable.LR_carouselJpegQuality ~= nil then
        propertyTable.carouselJpegQuality = tonumber(propertyTable.LR_carouselJpegQuality) or propertyTable.carouselJpegQuality
    end
    if propertyTable.LR_carouselCreateSubfolder ~= nil then
        propertyTable.carouselCreateSubfolder = propertyTable.LR_carouselCreateSubfolder
    end
    if propertyTable.LR_carouselReverseColumns ~= nil then
        propertyTable.carouselReverseColumns = propertyTable.LR_carouselReverseColumns
    end
end

local function syncPresetFromManualValues(propertyTable)
    local columns = tonumber(propertyTable.carouselColumns) or 3
    local ratio = propertyTable.carouselAspect or "4:5"
    local expected = ("%d_%s"):format(columns, ratio:gsub(":", "x"))
    for _, opt in ipairs(PRESET_OPTIONS) do
        if opt.value == expected then
            propertyTable.carouselPreset = expected
            return
        end
    end
    propertyTable.carouselPreset = "custom"
end

local function summarize(propertyTable)
    local columns = tonumber(propertyTable.carouselColumns) or 3
    local ratio = propertyTable.carouselAspect or "4:5"
    propertyTable.carouselSynopsis = ("%d carousel slides, %s portrait"):format(columns, ratio)
    updateCropHelper(propertyTable)
end

local function validate(propertyTable)
    local columns = tonumber(propertyTable.carouselColumns)
    local maxColumns = License.maxColumns()
    if not columns or columns < 2 or columns > 5 then
        propertyTable.LR_canExport = false
        propertyTable.carouselValidationError = "Columns must be between 2 and 5."
        return false
    end

    if columns > maxColumns then
        propertyTable.LR_canExport = false
        propertyTable.carouselValidationError =
            ("Free version supports up to %d slides. Upgrade to Pro for 4–5."):format(maxColumns)
        return false
    end

    if propertyTable.carouselAspect ~= "3:4" and propertyTable.carouselAspect ~= "4:5" then
        propertyTable.LR_canExport = false
        propertyTable.carouselValidationError = "Aspect ratio must be 3:4 or 4:5."
        return false
    end

    if propertyTable.carouselCropMode ~= "existing_first" and propertyTable.carouselCropMode ~= "center_crop" then
        propertyTable.LR_canExport = false
        propertyTable.carouselValidationError = "Crop mode is invalid."
        return false
    end

    local tileWidth = tonumber(propertyTable.carouselTileWidthPx)
    if not tileWidth or tileWidth < 320 or tileWidth > 4000 then
        propertyTable.LR_canExport = false
        propertyTable.carouselValidationError = "Tile width must be between 320 and 4000 pixels."
        return false
    end

    local quality = tonumber(propertyTable.carouselJpegQuality)
    if not quality or quality < 50 or quality > 100 then
        propertyTable.LR_canExport = false
        propertyTable.carouselValidationError = "JPEG quality must be between 50 and 100."
        return false
    end

    propertyTable.LR_canExport = true
    propertyTable.carouselValidationError = ""
    return true
end

local function enforceLicenseLimits(propertyTable)
    local maxColumns = License.maxColumns()
    local columns = tonumber(propertyTable.carouselColumns) or 3
    if columns > maxColumns then
        propertyTable.carouselColumns = maxColumns
    end
    propertyTable.carouselLicenseStatus = License.statusText()
end

function ExportDialogSections.startDialog(propertyTable)
    propertyTable.carouselPreset = propertyTable.carouselPreset or "custom"
    propertyTable.carouselColumns = tonumber(propertyTable.carouselColumns) or 3
    propertyTable.carouselAspect = propertyTable.carouselAspect or "4:5"
    propertyTable.carouselCropMode = propertyTable.carouselCropMode or "existing_first"
    propertyTable.carouselTileWidthPx = tonumber(propertyTable.carouselTileWidthPx) or 1080
    propertyTable.carouselJpegQuality = tonumber(propertyTable.carouselJpegQuality) or 92
    propertyTable.carouselCreateSubfolder = propertyTable.carouselCreateSubfolder ~= false
    propertyTable.carouselReverseColumns = propertyTable.carouselReverseColumns == true

    syncFromPrefixedFields(propertyTable)
    enforceLicenseLimits(propertyTable)
    summarize(propertyTable)
    syncPresetFromManualValues(propertyTable)
    validate(propertyTable)

    propertyTable:addObserver("carouselPreset", function()
        local columns, aspect = parsePreset(propertyTable.carouselPreset)
        if columns and aspect then
            propertyTable.carouselColumns = columns
            propertyTable.carouselAspect = aspect
        end
        summarize(propertyTable)
        validate(propertyTable)
    end)

    propertyTable:addObserver("carouselColumns", function()
        enforceLicenseLimits(propertyTable)
        syncPresetFromManualValues(propertyTable)
        summarize(propertyTable)
        validate(propertyTable)
    end)
    propertyTable:addObserver("carouselAspect", function()
        syncPresetFromManualValues(propertyTable)
        summarize(propertyTable)
        validate(propertyTable)
    end)
    propertyTable:addObserver("carouselCropMode", function()
        validate(propertyTable)
    end)
    propertyTable:addObserver("carouselTileWidthPx", function()
        validate(propertyTable)
    end)
    propertyTable:addObserver("carouselJpegQuality", function()
        validate(propertyTable)
    end)

    propertyTable:addObserver("LR_carouselColumns", function()
        syncFromPrefixedFields(propertyTable)
        summarize(propertyTable)
        validate(propertyTable)
    end)
    propertyTable:addObserver("LR_carouselAspect", function()
        syncFromPrefixedFields(propertyTable)
        summarize(propertyTable)
        validate(propertyTable)
    end)
    propertyTable:addObserver("LR_carouselPreset", function()
        syncFromPrefixedFields(propertyTable)
        summarize(propertyTable)
        validate(propertyTable)
    end)
    propertyTable:addObserver("LR_carouselCropMode", function()
        syncFromPrefixedFields(propertyTable)
        summarize(propertyTable)
        validate(propertyTable)
    end)
    propertyTable:addObserver("LR_carouselTileWidthPx", function()
        syncFromPrefixedFields(propertyTable)
        summarize(propertyTable)
        validate(propertyTable)
    end)
    propertyTable:addObserver("LR_carouselJpegQuality", function()
        syncFromPrefixedFields(propertyTable)
        summarize(propertyTable)
        validate(propertyTable)
    end)
    propertyTable:addObserver("LR_carouselCreateSubfolder", function()
        syncFromPrefixedFields(propertyTable)
        summarize(propertyTable)
        validate(propertyTable)
    end)
    propertyTable:addObserver("LR_carouselReverseColumns", function()
        syncFromPrefixedFields(propertyTable)
        summarize(propertyTable)
        validate(propertyTable)
    end)
end

function ExportDialogSections.sectionsForTopOfDialog(f, propertyTable)
    local bind = LrView.bind

    return {
        {
            title = "Instagram Carousel",
            synopsis = bind("carouselSynopsis"),
            f:column {
                spacing = f:control_spacing(),

                f:row {
                    spacing = f:label_spacing(),
                    f:static_text {
                        title = "Preset",
                        width = 150,
                        alignment = "right",
                    },
                    f:popup_menu {
                        value = bind("carouselPreset"),
                        items = PRESET_OPTIONS,
                    },
                },

                f:row {
                    spacing = f:label_spacing(),
                    f:static_text {
                        title = "Carousel slides",
                        width = 150,
                        alignment = "right",
                    },
                    f:popup_menu {
                        value = bind("carouselColumns"),
                        items = columnOptions(),
                        width_in_chars = 8,
                    },
                },

                f:row {
                    spacing = f:label_spacing(),
                    f:static_text {
                        title = "Post ratio",
                        width = 150,
                        alignment = "right",
                    },
                    f:popup_menu {
                        value = bind("carouselAspect"),
                        items = ASPECT_OPTIONS,
                    },
                },

                f:row {
                    spacing = f:label_spacing(),
                    f:static_text {
                        title = "Crop source mode",
                        width = 150,
                        alignment = "right",
                    },
                    f:popup_menu {
                        value = bind("carouselCropMode"),
                        items = CROP_MODE_OPTIONS,
                        width_in_chars = 42,
                    },
                },

                f:static_text {
                    title = bind("carouselOverallCropRatio"),
                    fill_horizontal = 1,
                },
                f:static_text {
                    title = bind("carouselOverallCropDecimalText"),
                    fill_horizontal = 1,
                },
                f:static_text {
                    title = "Tip: Use Plug-in Extras > Instagram Carousel Crop Ratio Helper for copy actions.",
                    fill_horizontal = 1,
                },

                f:row {
                    spacing = f:label_spacing(),
                    f:static_text {
                        title = "Tile width (px)",
                        width = 150,
                        alignment = "right",
                    },
                    f:edit_field {
                        value = bind("carouselTileWidthPx"),
                        width_in_chars = 8,
                    },
                },

                f:row {
                    spacing = f:label_spacing(),
                    f:static_text {
                        title = "JPEG quality",
                        width = 150,
                        alignment = "right",
                    },
                    f:edit_field {
                        value = bind("carouselJpegQuality"),
                        width_in_chars = 8,
                    },
                },

                f:checkbox {
                    title = "Create per-photo subfolder for tiles",
                    value = bind("carouselCreateSubfolder"),
                },
                f:checkbox {
                    title = "Reverse slide order (for posting)",
                    value = bind("carouselReverseColumns"),
                },

                f:static_text {
                    title = bind("carouselValidationError"),
                    fill_horizontal = 1,
                },
                f:static_text {
                    title = "Tip: Open Crop Ratio Helper, then click Create Export Presets to auto-add left-panel presets.",
                    fill_horizontal = 1,
                },
                f:static_text {
                    title = bind("carouselLicenseStatus"),
                    fill_horizontal = 1,
                },
                f:static_text {
                    title = "Support: support@thestudiosheringham.com",
                    fill_horizontal = 1,
                },
                f:row {
                    spacing = f:control_spacing(),
                    f:push_button {
                        title = "Check for updates",
                        action = function()
                            UpdateService.runCheckFromUi()
                        end,
                    },
                    f:push_button {
                        title = "Gareth website",
                        action = function()
                            openExternal(GARETH_URL)
                        end,
                    },
                    f:push_button {
                        title = "Studio website",
                        action = function()
                            openExternal(STUDIO_URL)
                        end,
                    },
                    f:push_button {
                        title = "Email support",
                        action = function()
                            openExternal(SUPPORT_EMAIL_URL)
                        end,
                    },
                },
            },
        },
    }
end

return ExportDialogSections

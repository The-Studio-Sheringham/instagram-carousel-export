local LrDialogs = import "LrDialogs"
local LrFileUtils = import "LrFileUtils"
local LrPathUtils = import "LrPathUtils"

local TOOLKIT_ID = "com.garethgabriel.instagramcarousel"
local PROVIDER_TITLE = "Instagram Carousel Export"

local function newGuid()
    local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    return (template:gsub("[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end)):upper()
end

local function escapeLuaString(value)
    local s = tostring(value or "")
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    return s
end

local function presetFolderPath()
    local appData = LrPathUtils.getStandardFilePath("appData")
    return LrPathUtils.child(appData, "Adobe/Lightroom/Export Presets/User Presets")
end

local function presetId(columns, aspectKey)
    return ("%d_%s"):format(columns, aspectKey:gsub(":", "x"))
end

local function presetName(columns, aspectKey)
    return ("IG Carousel x%d (%s)"):format(columns, aspectKey)
end

local function buildTemplateText(name, columns, aspectKey)
    local idValue = presetId(columns, aspectKey)
    local jpegQuality = 0.92
    return table.concat({
        "s = {",
        ('\tid = "%s",'):format(newGuid()),
        ('\tinternalName = "%s",'):format(escapeLuaString(name)),
        ('\ttitle = "%s",'):format(escapeLuaString(name)),
        '\ttype = "Export",',
        "\tvalue = {",
        '\t\texportServiceProvider = "' .. TOOLKIT_ID .. '",',
        '\t\texportServiceProviderTitle = "' .. PROVIDER_TITLE .. '",',
        '\t\tformat = "JPEG",',
        '\t\textensionCase = "lowercase",',
        '\t\texport_colorSpace = "sRGB",',
        '\t\texport_videoFileHandling = "exclude",',
        "\t\tincludeVideoFiles = false,",
        '\t\tcollisionHandling = "ask",',
        '\t\texport_destinationType = "chooseLater",',
        '\t\texport_postProcessing = "doNothing",',
        ('\t\tjpeg_quality = %.2f,'):format(jpegQuality),
        '\t\tjpeg_useLimitSize = false,',
        ('\t\tcarouselColumns = %d,'):format(columns),
        ('\t\tcarouselAspect = "%s",'):format(aspectKey),
        ('\t\tcarouselPreset = "%s",'):format(idValue),
        '\t\tcarouselCropMode = "existing_first",',
        "\t\tcarouselTileWidthPx = 1080,",
        "\t\tcarouselJpegQuality = 92,",
        "\t\tcarouselCreateSubfolder = true,",
        "\t\tcarouselReverseColumns = false,",
        "\t},",
        "\tversion = 0,",
        "}",
        "",
    }, "\n")
end

math.randomseed(os.time())
math.random()
math.random()
math.random()

local folder = presetFolderPath()
if LrFileUtils.exists(folder) ~= "directory" then
    LrFileUtils.createAllDirectories(folder)
end

local written = {}
for _, aspect in ipairs({ "3:4", "4:5" }) do
    for columns = 2, 5 do
        local name = presetName(columns, aspect)
        local path = LrPathUtils.child(folder, name .. ".lrtemplate")
        local content = buildTemplateText(name, columns, aspect)
        local handle, err = io.open(path, "w")
        if not handle then
            LrDialogs.message(
                "Create Carousel Export Presets",
                ("Could not write preset:\n%s\n\n%s"):format(path, tostring(err or "unknown error")),
                "critical"
            )
            return
        end
        handle:write(content)
        handle:close()
        written[#written + 1] = name
    end
end

LrDialogs.message(
    "Create Carousel Export Presets",
    ("Created/updated %d presets in User Presets.\n\nRe-open the Export dialog if the left preset list does not refresh immediately."):format(#written),
    "info"
)

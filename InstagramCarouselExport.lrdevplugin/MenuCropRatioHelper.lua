local LrBinding = import "LrBinding"
local LrDialogs = import "LrDialogs"
local LrFileUtils = import "LrFileUtils"
local LrFunctionContext = import "LrFunctionContext"
local LrHttp = import "LrHttp"
local LrPathUtils = import "LrPathUtils"
local LrTasks = import "LrTasks"
local LrView = import "LrView"

local License = require "License"
local UpdateService = require "UpdateService"

local TOOLKIT_ID = "com.garethgabriel.instagramcarousel"
local PROVIDER_TITLE = "Instagram Carousel Export"
local GARETH_URL = "https://garethgabriel.com"
local STUDIO_URL = "https://thestudiosheringham.com"
local SUPPORT_EMAIL_URL = "mailto:support@thestudiosheringham.com"
local function detectWindows()
    local appData = tostring(LrPathUtils.getStandardFilePath("appData") or "")
    if appData:match("^%a:[/\\]") then
        return true
    end
    return appData:find("\\", 1, true) ~= nil
end

local IS_WINDOWS = detectWindows()

local function namespacedKey(field)
    return TOOLKIT_ID .. "_" .. field
end

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function windowsQuote(value)
    return '"' .. tostring(value):gsub('"', '""') .. '"'
end

local function gcd(a, b)
    a = math.abs(math.floor(a))
    b = math.abs(math.floor(b))
    while b ~= 0 do
        a, b = b, a % b
    end
    return a
end

local function computeRatio(columns, aspectKey)
    local tileW = (aspectKey == "3:4") and 3 or 4
    local tileH = (aspectKey == "3:4") and 4 or 5
    local num = columns * tileW
    local den = tileH
    local d = gcd(num, den)
    return ("%d:%d"):format(num / d, den / d), num / den
end

local function copyToClipboard(text)
    if IS_WINDOWS then
        local scriptPath = LrPathUtils.child(
            LrPathUtils.getStandardFilePath("temp"),
            ("instagram-carousel-clipboard-%d-%d.ps1"):format(os.time(), math.random(1000, 999999))
        )
        local handle = io.open(scriptPath, "w")
        if not handle then
            return false
        end
        handle:write("param([string]$Text)\nSet-Clipboard -Value $Text\n")
        handle:close()

        local command = table.concat({
            "powershell",
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy", "Bypass",
            "-File", windowsQuote(scriptPath),
            windowsQuote(text),
        }, " ")
        local code = LrTasks.execute(command)
        LrFileUtils.delete(scriptPath)
        return code == 0
    end

    local command = "printf %s " .. shellQuote(text) .. " | /usr/bin/pbcopy"
    local code = LrTasks.execute("/bin/zsh -lc " .. shellQuote(command))
    return code == 0
end

local function openExternal(url)
    if not url or url == "" then
        return
    end
    pcall(function()
        LrHttp.openUrlInBrowser(url)
    end)
end

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
    local lightroomBase = appData
    if not lightroomBase:match("Adobe/Lightroom/?$") then
        lightroomBase = LrPathUtils.child(lightroomBase, "Adobe/Lightroom")
    end
    local exportPresets = LrPathUtils.child(lightroomBase, "Export Presets")
    return LrPathUtils.child(exportPresets, "Instagram Carousel Export")
end

local function presetId(columns, aspectKey)
    return ("%d_%s"):format(columns, aspectKey:gsub(":", "x"))
end

local function presetName(columns, aspectKey)
    return ("IG Carousel x%d (%s)"):format(columns, aspectKey)
end

local function buildTemplateText(name, columns, aspectKey)
    local idValue = presetId(columns, aspectKey)
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
        '\t\tjpeg_quality = 0.92,',
        '\t\tjpeg_useLimitSize = false,',
        ('\t\t["%s"] = %d,'):format(namespacedKey("carouselColumns"), columns),
        ('\t\t["%s"] = "%s",'):format(namespacedKey("carouselAspect"), aspectKey),
        ('\t\t["%s"] = "%s",'):format(namespacedKey("carouselPreset"), idValue),
        ('\t\t["%s"] = "existing_first",'):format(namespacedKey("carouselCropMode")),
        ('\t\t["%s"] = 1080,'):format(namespacedKey("carouselTileWidthPx")),
        ('\t\t["%s"] = "92",'):format(namespacedKey("carouselJpegQuality")),
        ('\t\t["%s"] = true,'):format(namespacedKey("carouselCreateSubfolder")),
        ('\t\t["%s"] = false,'):format(namespacedKey("carouselReverseColumns")),
        "\t},",
        "\tversion = 0,",
        "}",
        "",
    }, "\n")
end

local function createCarouselPresets()
    local folder = presetFolderPath()
    if LrFileUtils.exists(folder) ~= "directory" then
        LrFileUtils.createAllDirectories(folder)
    end

    local written = 0
    for _, aspect in ipairs(License.presetAspects()) do
        for columns = License.minColumns(), License.maxColumns() do
            local name = presetName(columns, aspect)
            local path = LrPathUtils.child(folder, name .. ".lrtemplate")
            local content = buildTemplateText(name, columns, aspect)
            local handle, err = io.open(path, "w")
            if not handle then
                return false, ("Could not write preset:\n%s\n\n%s"):format(path, tostring(err or "unknown error"))
            end
            handle:write(content)
            handle:close()
            written = written + 1
        end
    end

    local scopeNote = License.isPro()
        and "\n\nFull licence presets: 3:4 + 4:5, slides 2–5."
        or "\n\nFree presets: 4:5 only, slides 2–3. Buy a full licence for 3:4 and 4–5 slides."

    return true, ("Created/updated %d presets in:\n%s\n\nRe-open Export dialog if left list does not refresh immediately.%s")
        :format(written, folder, scopeNote)
end

local function updateState(props)
    props.columns = License.clampColumns(props.columns)
    props.aspect = License.clampAspect(props.aspect)
    local columns = props.columns
    local aspect = props.aspect
    local ratioText, decimalValue = computeRatio(columns, aspect)
    props.ratioText = ratioText
    props.decimalText = ("%.4f"):format(decimalValue)
    props.ratioHeadline = ("Suggested crop ratio: %s"):format(props.ratioText)
    props.decimalHeadline = ("Decimal: %s"):format(props.decimalText)
    props.licenseStatus = License.statusText()
    props.summary = ("Use this ratio in Develop Crop before exporting your carousel.")
end

LrFunctionContext.callWithContext("InstagramCarouselCropRatioHelper", function(context)
    math.randomseed(os.time())
    math.random()
    math.random()
    math.random()

    local f = LrView.osFactory()
    local bind = LrView.bind
    local props = LrBinding.makePropertyTable(context)

    local isPro = License.isPro()
    props.columns = License.clampColumns(2)
    props.aspect = License.defaultAspect()
    props.copyStatus = ""
    updateState(props)

    props:addObserver("columns", function()
        updateState(props)
    end)
    props:addObserver("aspect", function()
        updateState(props)
    end)

    local contents = {
        bind_to_object = props,
        spacing = f:control_spacing(),

        f:row {
            spacing = f:label_spacing(),
            f:static_text { title = "Carousel slides", width = 120, alignment = "right" },
            f:popup_menu {
                value = bind("columns"),
                items = License.columnOptions(" slides"),
                width_in_chars = 14,
            },
        },

        f:row {
            spacing = f:label_spacing(),
            f:static_text { title = "Post ratio", width = 120, alignment = "right" },
            f:popup_menu {
                value = bind("aspect"),
                items = License.aspectOptions(),
            },
        },

        f:static_text { title = bind("summary"), fill_horizontal = 1 },
        f:static_text {
            title = bind("ratioHeadline"),
            fill_horizontal = 1,
            font = "<system/bold>",
        },
        f:static_text {
            title = bind("decimalHeadline"),
            fill_horizontal = 1,
        },
        f:row {
            spacing = f:label_spacing(),
            f:static_text { title = "Ratio", width = 120, alignment = "right" },
            f:static_text { title = bind("ratioText"), width_in_chars = 12 },
            f:static_text { title = "Decimal", width = 70, alignment = "right" },
            f:static_text { title = bind("decimalText"), width_in_chars = 10 },
        },

        f:row {
            spacing = f:control_spacing(),
            f:push_button {
                title = "Copy Ratio",
                action = function()
                    if copyToClipboard(props.ratioText) then
                        props.copyStatus = ("Copied ratio %s"):format(props.ratioText)
                    else
                        props.copyStatus = "Could not copy ratio."
                    end
                end,
            },
            f:push_button {
                title = "Copy Decimal",
                action = function()
                    if copyToClipboard(props.decimalText) then
                        props.copyStatus = ("Copied decimal %s"):format(props.decimalText)
                    else
                        props.copyStatus = "Could not copy decimal."
                    end
                end,
            },
            f:static_text { title = bind("copyStatus"), fill_horizontal = 1 },
        },
        f:row {
            spacing = f:control_spacing(),
            f:push_button {
                title = "Create Export Presets",
                action = function()
                    local ok, message = createCarouselPresets()
                    if ok then
                        LrDialogs.message("Create Carousel Export Presets", message, "info")
                    else
                        LrDialogs.message("Create Carousel Export Presets", message, "critical")
                    end
                end,
            },
            f:push_button {
                title = "Check for updates",
                action = function()
                    UpdateService.runCheckFromUi()
                end,
            },
        },
    }

    if not isPro then
        contents[#contents + 1] = f:row {
            spacing = f:control_spacing(),
            f:push_button {
                title = "Buy me a coffee",
                action = function()
                    License.openBuyMeACoffee()
                end,
            },
            f:push_button {
                title = "Buy full licence",
                action = function()
                    License.openBuyLicence()
                end,
            },
            f:push_button {
                title = "Enter licence key",
                action = function()
                    License.promptActivate()
                    updateState(props)
                end,
            },
        }
    end

    contents[#contents + 1] = f:separator { fill_horizontal = 1 }
    contents[#contents + 1] = f:static_text {
        title = "How to use:\n1) Choose Carousel slides + Post ratio here.\n2) Copy the suggested ratio and set it in Develop Crop.\n3) In Export, use the same slides and post ratio settings.",
        fill_horizontal = 1,
    }
    contents[#contents + 1] = f:static_text {
        title = bind("licenseStatus"),
        fill_horizontal = 1,
    }
    contents[#contents + 1] = f:static_text {
        title = "Support: support@thestudiosheringham.com",
        fill_horizontal = 1,
    }
    contents[#contents + 1] = f:row {
        spacing = f:control_spacing(),
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
    }

    LrDialogs.presentModalDialog({
        title = "Instagram Carousel Crop Ratio Helper",
        contents = f:column(contents),
        actionVerb = "Close",
    })
end)

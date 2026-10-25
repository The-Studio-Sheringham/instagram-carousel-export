local LrBinding = import "LrBinding"
local LrDialogs = import "LrDialogs"
local LrFunctionContext = import "LrFunctionContext"
local LrTasks = import "LrTasks"
local LrView = import "LrView"

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
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
    local command = "printf %s " .. shellQuote(text) .. " | /usr/bin/pbcopy"
    local code = LrTasks.execute("/bin/zsh -lc " .. shellQuote(command))
    return code == 0
end

local COLUMN_OPTIONS = {
    { title = "2", value = 2 },
    { title = "3", value = 3 },
    { title = "4", value = 4 },
    { title = "5", value = 5 },
}

local ASPECT_OPTIONS = {
    { title = "3:4 portrait", value = "3:4" },
    { title = "4:5 portrait", value = "4:5" },
}

local function updateState(props)
    local columns = tonumber(props.columns) or 2
    local aspect = props.aspect or "3:4"
    local ratioText, decimalValue = computeRatio(columns, aspect)
    props.ratioText = ratioText
    props.decimalText = ("%.4f"):format(decimalValue)
    props.summary = ("Use this in Develop crop before export: %s (decimal %s)"):format(props.ratioText, props.decimalText)
end

LrFunctionContext.callWithContext("InstagramCarouselCropRatioHelper", function(context)
    local f = LrView.osFactory()
    local bind = LrView.bind
    local props = LrBinding.makePropertyTable(context)

    props.columns = 2
    props.aspect = "3:4"
    props.copyStatus = ""
    updateState(props)

    props:addObserver("columns", function()
        updateState(props)
    end)
    props:addObserver("aspect", function()
        updateState(props)
    end)

    local result = LrDialogs.presentModalDialog({
        title = "Instagram Carousel Crop Ratio Helper",
        contents = f:column {
            spacing = f:control_spacing(),

            f:row {
                spacing = f:label_spacing(),
                f:static_text { title = "Preset", width = 120, alignment = "right" },
                f:popup_menu { value = bind("columns"), items = COLUMN_OPTIONS, width_in_chars = 8 },
                f:popup_menu { value = bind("aspect"), items = ASPECT_OPTIONS },
            },

            f:static_text { title = bind("summary"), fill_horizontal = 1 },

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

            f:separator { fill_horizontal = 1 },
            f:static_text { title = "Quick Reference:", fill_horizontal = 1 },
            f:static_text { title = "x2 (3:4) = 3:2 | x3 (3:4) = 9:4 | x4 (3:4) = 3:1 | x5 (3:4) = 15:4", fill_horizontal = 1 },
            f:static_text { title = "x2 (4:5) = 8:5 | x3 (4:5) = 12:5 | x4 (4:5) = 16:5 | x5 (4:5) = 4:1", fill_horizontal = 1 },
        },
        actionVerb = "Close",
    })

    if result == "ok" then
        return
    end
end)

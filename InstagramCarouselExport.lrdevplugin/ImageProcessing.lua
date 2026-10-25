local LrFileUtils = import "LrFileUtils"
local LrPathUtils = import "LrPathUtils"
local LrTasks = import "LrTasks"

local TileMath = require "TileMath"

local ImageProcessing = {}
local function detectWindows()
    local appData = tostring(LrPathUtils.getStandardFilePath("appData") or "")
    if appData:match("^%a:[/\\]") then
        return true
    end
    return appData:find("\\", 1, true) ~= nil
end

local IS_WINDOWS = detectWindows()
local IS_MAC = not IS_WINDOWS

local function round(value)
    return math.floor(value + 0.5)
end

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function windowsQuote(value)
    return '"' .. tostring(value):gsub('"', '""') .. '"'
end

local function quoteArg(value)
    if IS_WINDOWS then
        return windowsQuote(value)
    end
    return shellQuote(value)
end

local function runCommand(command)
    local wrappedCommand
    if IS_WINDOWS then
        wrappedCommand = command
    else
        wrappedCommand = "/bin/zsh -lc " .. shellQuote(command)
    end
    local code = LrTasks.execute(wrappedCommand)
    if code ~= 0 then
        return false, ("command failed (%d): %s"):format(code, command)
    end
    return true
end

local function runAndCapture(command)
    local tmpOut = LrPathUtils.child(
        LrPathUtils.getStandardFilePath("temp"),
        ("instagram-carousel-output-%d-%d.txt"):format(os.time(), math.random(1000, 999999))
    )

    local captureCommand = command .. " > " .. quoteArg(tmpOut) .. " 2>&1"
    local ok, err = runCommand(captureCommand)
    local output = LrFileUtils.readFile(tmpOut) or ""
    LrFileUtils.delete(tmpOut)

    if not ok then
        return nil, err .. "\n" .. output
    end

    return output
end

local function writeTextFile(path, content)
    local handle, err = io.open(path, "w")
    if not handle then
        return false, err
    end
    handle:write(content)
    handle:close()
    return true
end

local function tempFilePath(prefix, extension)
    return LrPathUtils.child(
        LrPathUtils.getStandardFilePath("temp"),
        ("%s-%d-%d%s"):format(prefix, os.time(), math.random(1000, 999999), extension or "")
    )
end

local function runPowerShellScript(scriptBody, args, captureOutput)
    local scriptPath = tempFilePath("instagram-carousel-script", ".ps1")
    local outPath = captureOutput and tempFilePath("instagram-carousel-ps-output", ".txt") or nil
    local wrote, writeErr = writeTextFile(scriptPath, scriptBody)
    if not wrote then
        return nil, ("failed to write PowerShell script: %s"):format(writeErr or "unknown")
    end

    local commandParts = {
        "powershell",
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy", "Bypass",
        "-File", quoteArg(scriptPath),
    }
    for _, arg in ipairs(args or {}) do
        commandParts[#commandParts + 1] = quoteArg(arg)
    end
    local command = table.concat(commandParts, " ")
    if captureOutput then
        command = command .. " > " .. quoteArg(outPath) .. " 2>&1"
    end

    local ok, err = runCommand(command)
    local output = ""
    if captureOutput then
        output = LrFileUtils.readFile(outPath) or ""
        LrFileUtils.delete(outPath)
    end
    LrFileUtils.delete(scriptPath)

    if not ok then
        return nil, (err or "PowerShell command failed") .. (output ~= "" and ("\n" .. output) or "")
    end
    return output ~= "" and output or true
end

local function parseSipsDimension(output, key)
    local pattern = key .. ":%s*(%d+)"
    local value = output:match(pattern)
    if not value then
        return nil
    end
    return tonumber(value)
end

local function stripExtension(fileName)
    return (fileName:gsub("%.[^%.]+$", ""))
end

local function sanitizeBaseName(name)
    local cleaned = tostring(name or "photo")
    cleaned = cleaned:gsub("[^%w%-_]+", "_")
    cleaned = cleaned:gsub("_+", "_")
    cleaned = cleaned:gsub("^_", "")
    cleaned = cleaned:gsub("_$", "")
    if cleaned == "" then
        cleaned = "photo"
    end
    return cleaned
end

local function determineTargetTileSize(tileWidthPx, aspectKey)
    local width = clamp(tonumber(tileWidthPx) or 1080, 320, 4000)
    local ratio, ratioErr = TileMath.parseAspectRatio(aspectKey or "4:5")
    if not ratio then
        return nil, ratioErr
    end

    local height = round(width / ratio)
    return { width = width, height = height }
end

function ImageProcessing.getImageSize(imagePath)
    local output
    local err
    if IS_MAC then
        output, err = runAndCapture("/usr/bin/sips -g pixelWidth -g pixelHeight " .. shellQuote(imagePath))
    else
        output, err = runPowerShellScript([[
param([string]$Path)
Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile($Path)
try {
    Write-Output ("pixelWidth: {0}" -f $img.Width)
    Write-Output ("pixelHeight: {0}" -f $img.Height)
}
finally {
    $img.Dispose()
}
]], { imagePath }, true)
    end
    if not output then
        return nil, err
    end

    local width = parseSipsDimension(output, "pixelWidth")
    local height = parseSipsDimension(output, "pixelHeight")
    if not width or not height then
        return nil, "unable to parse image dimensions from sips output"
    end

    return { width = width, height = height }
end

local function cropImage(sourcePath, outputPath, cropRect)
    if IS_MAC then
        local command = table.concat({
            "/usr/bin/sips",
            "-c", tostring(cropRect.height), tostring(cropRect.width),
            "--cropOffset", tostring(cropRect.y), tostring(cropRect.x),
            shellQuote(sourcePath),
            "--out", shellQuote(outputPath),
        }, " ")
        return runCommand(command)
    end

    local script = [[
param([string]$SourcePath, [string]$OutputPath, [int]$X, [int]$Y, [int]$W, [int]$H)
Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Bitmap]::FromFile($SourcePath)
try {
    $dest = New-Object System.Drawing.Bitmap $W, $H
    try {
        $g = [System.Drawing.Graphics]::FromImage($dest)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $srcRect = New-Object System.Drawing.Rectangle $X, $Y, $W, $H
        $dstRect = New-Object System.Drawing.Rectangle 0, 0, $W, $H
        $g.DrawImage($src, $dstRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
        $g.Dispose()
        $dest.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Jpeg)
    }
    finally {
        $dest.Dispose()
    }
}
finally {
    $src.Dispose()
}
]]
    local ok, psErr = runPowerShellScript(script, {
        sourcePath,
        outputPath,
        tostring(cropRect.x),
        tostring(cropRect.y),
        tostring(cropRect.width),
        tostring(cropRect.height),
    }, false)
    if not ok then
        return false, psErr
    end
    return true
end

local function resizeJpeg(sourcePath, outputPath, width, height, quality)
    if IS_MAC then
        local command = table.concat({
            "/usr/bin/sips",
            "-s", "format", "jpeg",
            "-s", "formatOptions", tostring(quality),
            "-z", tostring(height), tostring(width),
            shellQuote(sourcePath),
            "--out", shellQuote(outputPath),
        }, " ")
        return runCommand(command)
    end

    local script = [[
param([string]$SourcePath, [string]$OutputPath, [int]$W, [int]$H, [int]$Quality)
Add-Type -AssemblyName System.Drawing
$src = [System.Drawing.Bitmap]::FromFile($SourcePath)
try {
    $dest = New-Object System.Drawing.Bitmap $W, $H
    try {
        $g = [System.Drawing.Graphics]::FromImage($dest)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $g.DrawImage($src, 0, 0, $W, $H)
        $g.Dispose()

        $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageDecoders() |
            Where-Object { $_.FormatID -eq [System.Drawing.Imaging.ImageFormat]::Jpeg.Guid } |
            Select-Object -First 1
        if ($null -eq $codec) {
            throw "JPEG codec not found"
        }

        $params = New-Object System.Drawing.Imaging.EncoderParameters 1
        $params.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]$Quality)
        $dest.Save($OutputPath, $codec, $params)
    }
    finally {
        $dest.Dispose()
    }
}
finally {
    $src.Dispose()
}
]]
    local ok, psErr = runPowerShellScript(script, {
        sourcePath,
        outputPath,
        tostring(width),
        tostring(height),
        tostring(quality),
    }, false)
    if not ok then
        return false, psErr
    end
    return true
end

local function ensureDirectory(path)
    if LrFileUtils.exists(path) == "directory" then
        return true
    end
    return LrFileUtils.createAllDirectories(path)
end

function ImageProcessing.buildOutputDirectory(renderedPath, baseName, createSubfolder)
    local parent = LrPathUtils.parent(renderedPath)
    if not createSubfolder then
        return parent
    end

    local subfolder = LrPathUtils.child(parent, sanitizeBaseName(baseName) .. "_carousel")
    ensureDirectory(subfolder)
    return subfolder
end

function ImageProcessing.exportTilesForPhoto(options)
    local sourcePath = options.sourcePath
    local layout = options.layout
    local columns = tonumber(options.columns) or 3
    local rows = tonumber(options.rows) or 3
    local aspectKey = options.aspectKey or "4:5"
    local tileSize, sizeErr = determineTargetTileSize(options.tileWidthPx, aspectKey)
    if not tileSize then
        return false, sizeErr
    end

    local quality = clamp(tonumber(options.jpegQuality) or 92, 50, 100)
    local photoName = "photo"
    if options.originalPhoto then
        photoName = options.originalPhoto:getFormattedMetadata("fileName") or "photo"
    end
    photoName = sanitizeBaseName(stripExtension(photoName))

    local outputDir = ImageProcessing.buildOutputDirectory(options.renderedPath, photoName, options.createSubfolder)
    if not ensureDirectory(outputDir) then
        return false, ("could not create output directory: %s"):format(outputDir)
    end

    -- First crop the full target strip once, then slice relative to it.
    -- This avoids coordinate drift against the full source image.
    local stripOutputName = ("%s_c%dx%d_strip.jpg"):format(photoName, columns, rows)
    local stripOutputPath = LrPathUtils.child(outputDir, stripOutputName)
    local stripCrop = layout.crop
    local stripOk, stripErr = cropImage(sourcePath, stripOutputPath, {
        x = stripCrop.x,
        y = stripCrop.y,
        width = stripCrop.width,
        height = stripCrop.height,
    })
    if not stripOk then
        return false, stripErr
    end

    local orderedTiles = TileMath.iterateOrderedTiles(layout, options.reverseColumns)

    local debugLines = {
        ("photo=%s"):format(photoName),
        ("source=%s"):format(sourcePath),
        ("strip=%s"):format(stripOutputPath),
        ("columns=%d"):format(columns),
        ("rows=%d"):format(rows),
        ("aspect=%s"):format(aspectKey),
        ("cropMode=%s"):format(layout.cropMode or "unknown"),
        ("sourceSize=%dx%d"):format(layout.sourceWidth or 0, layout.sourceHeight or 0),
        ("cropRect=x:%d y:%d w:%d h:%d"):format(stripCrop.x or 0, stripCrop.y or 0, stripCrop.width or 0, stripCrop.height or 0),
    }

    for _, tile in ipairs(orderedTiles) do
        local tmpCropPath = LrPathUtils.child(
            LrPathUtils.getStandardFilePath("temp"),
            ("carousel-crop-%d-%d-r%d-c%d.jpg"):format(os.time(), math.random(1000, 999999), tile.row, tile.col)
        )

        local relY = math.max(0, tile.y - stripCrop.y)
        local relX = math.max(0, tile.x - stripCrop.x)
        local cropW = tile.width
        local cropH = tile.height

        -- sips has a cropOffset edge case where 0,0 can behave like center-crop.
        -- Nudge the first tile by one pixel and compensate width to keep seams consistent.
        if IS_MAC and relX == 0 and relY == 0 and columns > 1 then
            relX = 1
            cropW = math.min(stripCrop.width - relX, tile.width + 1)
        end
        debugLines[#debugLines + 1] = ("tile r%d c%d srcRect=x:%d y:%d w:%d h:%d relOffset=y:%d x:%d")
            :format(tile.row, tile.col, tile.x, tile.y, cropW, cropH, relY, relX)
        local cropOk, cropErr = cropImage(stripOutputPath, tmpCropPath, {
            x = relX,
            y = relY,
            width = cropW,
            height = cropH,
        })
        if not cropOk then
            return false, cropErr
        end

        local outputName = ("%s_c%dx%d_r%d_c%d.jpg"):format(photoName, columns, rows, tile.row, tile.col)
        local outputPath = LrPathUtils.child(outputDir, outputName)
        local resizeOk, resizeErr = resizeJpeg(
            tmpCropPath,
            outputPath,
            tileSize.width,
            tileSize.height,
            quality
        )
        LrFileUtils.delete(tmpCropPath)
        if not resizeOk then
            return false, resizeErr
        end
    end

    local debugOutputName = ("%s_c%dx%d_layout.txt"):format(photoName, columns, rows)
    local debugOutputPath = LrPathUtils.child(outputDir, debugOutputName)
    local wroteDebug, debugErr = writeTextFile(debugOutputPath, table.concat(debugLines, "\n") .. "\n")
    if not wroteDebug then
        return false, ("failed writing layout debug file: %s"):format(debugErr or "unknown error")
    end

    return true
end

return ImageProcessing

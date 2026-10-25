local LrApplication = import "LrApplication"
local LrDialogs = import "LrDialogs"
local LrFileUtils = import "LrFileUtils"
local LrPathUtils = import "LrPathUtils"
local LrTasks = import "LrTasks"

local ImageProcessing = require "ImageProcessing"
local TileMath = require "TileMath"

local OverlayPreview = {}

local PREVIEW_MAX_EDGE = 1200
local PREVIEW_FOLDER_NAME = "InstagramCarouselPreview"

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function runCommand(command)
    local code = LrTasks.execute("/bin/zsh -lc " .. shellQuote(command))
    return code == 0
end

local function runAndCapture(command)
    local outputPath = LrPathUtils.child(
        LrPathUtils.getStandardFilePath("temp"),
        ("instagram-carousel-preview-output-%d-%d.txt"):format(os.time(), math.random(1000, 999999))
    )
    local wrapped = command .. " > " .. shellQuote(outputPath) .. " 2>&1"
    local ok = runCommand(wrapped)
    local output = LrFileUtils.readFile(outputPath) or ""
    LrFileUtils.delete(outputPath)
    if not ok then
        return nil, output
    end
    return output
end

local function ensureDirectory(path)
    if LrFileUtils.exists(path) == "directory" then
        return true
    end
    return LrFileUtils.createAllDirectories(path)
end

local function escapeHtml(text)
    local safe = tostring(text or "")
    safe = safe:gsub("&", "&amp;")
    safe = safe:gsub("<", "&lt;")
    safe = safe:gsub(">", "&gt;")
    safe = safe:gsub('"', "&quot;")
    return safe
end

local function getTargetPhotoPath()
    local catalog = LrApplication.activeCatalog()
    local targetPhoto = catalog and catalog:getTargetPhoto()
    if not targetPhoto then
        return nil, nil
    end
    return targetPhoto, targetPhoto:getRawMetadata("path")
end

local function previewPaths()
    local folder = LrPathUtils.child(LrPathUtils.getStandardFilePath("temp"), PREVIEW_FOLDER_NAME)
    ensureDirectory(folder)
    return {
        folder = folder,
        imagePath = LrPathUtils.child(folder, "preview-source.jpg"),
        htmlPath = LrPathUtils.child(folder, "preview-overlay.html"),
    }
end

local function writeBinaryFile(path, data)
    local handle, err = io.open(path, "wb")
    if not handle then
        return false, err
    end
    handle:write(data)
    handle:close()
    return true
end

local function generateEditedPreviewFromLightroom(photo, paths)
    local done = false
    local ok = false
    local errMsg
    local request

    request = photo:requestJpegThumbnail(PREVIEW_MAX_EDGE, PREVIEW_MAX_EDGE, function(jpegData, err)
        if jpegData then
            local wrote, writeErr = writeBinaryFile(paths.imagePath, jpegData)
            if wrote then
                ok = true
            else
                errMsg = writeErr or "failed writing thumbnail data"
            end
        else
            errMsg = err or "thumbnail request failed"
        end
        done = true
        request = nil
    end)

    local timeoutMs = 12000
    local waited = 0
    while not done and waited < timeoutMs do
        LrTasks.sleep(0.05)
        waited = waited + 50
    end

    if not done then
        return false, "Lightroom preview request timed out"
    end
    if ok then
        return true
    end
    return false, errMsg or "Lightroom preview request failed"
end

local function generatePreviewImage(photo, paths)
    local lrPreviewOk, lrPreviewErr = generateEditedPreviewFromLightroom(photo, paths)
    if lrPreviewOk then
        return true, "lightroom_edited_preview"
    end

    local photoPath = photo:getRawMetadata("path")
    if photoPath and LrFileUtils.exists(photoPath) == "file" then
        local sipsCommand = table.concat({
            "/usr/bin/sips",
            "-Z", tostring(PREVIEW_MAX_EDGE),
            shellQuote(photoPath),
            "--out", shellQuote(paths.imagePath),
        }, " ")
        if runCommand(sipsCommand) then
            return true, "original_file_fallback_sips"
        end

        local qlFolder = LrPathUtils.child(paths.folder, ("ql-%d-%d"):format(os.time(), math.random(1000, 999999)))
        ensureDirectory(qlFolder)
        local qlCommand = table.concat({
            "/usr/bin/qlmanage",
            "-t",
            "-s", tostring(PREVIEW_MAX_EDGE),
            "-o", shellQuote(qlFolder),
            shellQuote(photoPath),
        }, " ")
        if runCommand(qlCommand) then
            local listOutput = runAndCapture(
                "for f in " .. shellQuote(qlFolder) .. "/*.png; do if [ -f \"$f\" ]; then echo \"$f\"; break; fi; done"
            )
            local generatedPng = listOutput and listOutput:match("([^\n\r]+)")
            if generatedPng and generatedPng ~= "" then
                local copyOk = runCommand("/bin/cp " .. shellQuote(generatedPng) .. " " .. shellQuote(paths.imagePath))
                if copyOk then
                    return true, "original_file_fallback_qlmanage"
                end
            end
        end
    end

    return false, ("Could not get Lightroom edited preview (%s)."):format(lrPreviewErr or "unknown error")
end

local function writeOverlayHtml(args)
    local rows = args.layout.rows
    local cols = args.layout.columns
    local source = args.layout
    local previewSize = args.previewSize

    local scaleX = previewSize.width / source.sourceWidth
    local scaleY = previewSize.height / source.sourceHeight

    local cropX = source.crop.x * scaleX
    local cropY = source.crop.y * scaleY
    local cropW = source.crop.width * scaleX
    local cropH = source.crop.height * scaleY

    local lines = {}
    lines[#lines + 1] = ([[<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="none" stroke="rgba(255,255,255,0.95)" stroke-width="3" />]])
        :format(cropX, cropY, cropW, cropH)

    for col = 1, cols - 1 do
        local x = cropX + (cropW * col / cols)
        lines[#lines + 1] = ([[<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="rgba(255,255,255,0.65)" stroke-width="2" />]])
            :format(x, cropY, x, cropY + cropH)
    end
    for row = 1, rows - 1 do
        local y = cropY + (cropH * row / rows)
        lines[#lines + 1] = ([[<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="rgba(255,255,255,0.65)" stroke-width="2" />]])
            :format(cropX, y, cropX + cropW, y)
    end

    local html = table.concat({
        "<!DOCTYPE html>",
        "<html><head><meta charset=\"utf-8\" />",
        "<title>Instagram Carousel Overlay Preview</title>",
        "<style>",
        "body{margin:0;background:#1f1f1f;color:#fff;font-family:-apple-system,Helvetica,Arial,sans-serif;}",
        ".wrap{display:flex;justify-content:center;align-items:center;min-height:100vh;padding:20px;box-sizing:border-box;}",
        ".frame{position:relative;display:inline-block;box-shadow:0 12px 35px rgba(0,0,0,.5);}",
        ".frame img{display:block;max-width:100%;height:auto;}",
        ".meta{position:fixed;left:16px;top:16px;background:rgba(0,0,0,.45);padding:10px 12px;border-radius:8px;font-size:12px;line-height:1.4;}",
        "</style></head><body>",
        ("<div class=\"meta\">Columns: %d | Rows: %d | Ratio: %s<br/>Crop: %dx%d @ (%d,%d)</div>")
            :format(cols, rows, escapeHtml(args.aspectKey), source.crop.width, source.crop.height, source.crop.x, source.crop.y),
        "<div class=\"wrap\"><div class=\"frame\">",
        ("<img src=\"%s\" width=\"%d\" height=\"%d\" alt=\"Preview\" />"):format(
            escapeHtml(LrPathUtils.leafName(args.previewImagePath)),
            previewSize.width,
            previewSize.height
        ),
        ("<svg width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\" style=\"position:absolute;left:0;top:0;\">")
            :format(previewSize.width, previewSize.height, previewSize.width, previewSize.height),
        table.concat(lines, "\n"),
        "</svg></div></div></body></html>",
    }, "\n")

    local handle, err = io.open(args.htmlPath, "w")
    if not handle then
        return false, err
    end
    handle:write(html)
    handle:close()
    return true
end

function OverlayPreview.refreshPreview(propertyTable)
    local photo, photoPath = getTargetPhotoPath()
    if not photo or not photoPath or LrFileUtils.exists(photoPath) ~= "file" then
        propertyTable.carouselPreviewStatus = "No target photo selected in Lightroom."
        propertyTable.carouselPreviewHtmlPath = nil
        return false, "missing target photo path"
    end

    local paths = previewPaths()
    local previewOk, previewSourceOrErr = generatePreviewImage(photo, paths)
    if not previewOk then
        propertyTable.carouselPreviewStatus = "Failed generating downscaled preview."
        return false, previewSourceOrErr or "preview generation failed"
    end

    local previewSize, previewErr = ImageProcessing.getImageSize(paths.imagePath)
    if not previewSize then
        propertyTable.carouselPreviewStatus = "Failed reading preview dimensions."
        return false, previewErr
    end

    local sourceSize = previewSize

    local columns = tonumber(propertyTable.carouselColumns) or 3
    local aspectKey = propertyTable.carouselAspect or "4:5"
    local layout, layoutErr = TileMath.computeLayout(sourceSize.width, sourceSize.height, columns, aspectKey, {
        useExistingCropFirst = propertyTable.carouselCropMode == "existing_first",
    })
    if not layout then
        propertyTable.carouselPreviewStatus = "Failed computing tile overlay geometry."
        return false, layoutErr
    end

    local wrote, writeErr = writeOverlayHtml({
        layout = layout,
        aspectKey = aspectKey,
        previewImagePath = paths.imagePath,
        htmlPath = paths.htmlPath,
        previewSize = previewSize,
    })
    if not wrote then
        propertyTable.carouselPreviewStatus = "Failed writing overlay preview HTML."
        return false, writeErr or "could not write preview html"
    end

    propertyTable.carouselPreviewImagePath = paths.imagePath
    propertyTable.carouselPreviewHtmlPath = paths.htmlPath
    propertyTable.carouselPreviewStatus = ("Overlay preview ready (%dx%d, mode: %s, source: %s)")
        :format(sourceSize.width, sourceSize.height, layout.cropMode, previewSourceOrErr)
    return true
end

function OverlayPreview.openPreview(propertyTable)
    local htmlPath = propertyTable.carouselPreviewHtmlPath
    if not htmlPath or LrFileUtils.exists(htmlPath) ~= "file" then
        local ok = OverlayPreview.refreshPreview(propertyTable)
        if not ok then
            LrDialogs.message("Instagram Carousel Export", "Could not create overlay preview for current photo.", "warning")
            return
        end
        htmlPath = propertyTable.carouselPreviewHtmlPath
    end

    LrTasks.startAsyncTask(function()
        LrTasks.execute("/usr/bin/open " .. shellQuote(htmlPath))
    end)
end

return OverlayPreview

local LrLogger = import "LrLogger"
local LrFileUtils = import "LrFileUtils"
local LrTasks = import "LrTasks"

local ExportDialogSections = require "ExportDialogSections"
local License = require "License"
local TileMath = require "TileMath"
local ImageProcessing = require "ImageProcessing"

local logger = LrLogger("InstagramCarouselExport")
logger:enable("print")

local ExportServiceProvider = {}

ExportServiceProvider.exportPresetFields = {
    { key = "carouselColumns", default = 3 },
    { key = "carouselAspect", default = "4:5" },
    { key = "carouselPreset", default = "custom" },
    { key = "carouselCropMode", default = "existing_first" },
    { key = "carouselTileWidthPx", default = 1080 },
    { key = "carouselJpegQuality", default = 92 },
    { key = "carouselCreateSubfolder", default = true },
    { key = "carouselReverseColumns", default = false },
}

ExportServiceProvider.hideSections = {
    "video",
}

function ExportServiceProvider.startDialog(propertyTable)
    ExportDialogSections.startDialog(propertyTable)
end

function ExportServiceProvider.sectionsForTopOfDialog(f, propertyTable)
    return ExportDialogSections.sectionsForTopOfDialog(f, propertyTable)
end

function ExportServiceProvider.processRenderedPhotos(functionContext, exportContext)
    local props = exportContext.propertyTable
    local function getProp(name)
        if props[name] ~= nil then
            return props[name]
        end
        return props["LR_" .. name]
    end

    for _, rendition in exportContext:renditions({ stopIfCanceled = true }) do
        local success, renderedPathOrMessage = rendition:waitForRender()
        local photo = rendition.photo

        if success then
            local sourcePath = renderedPathOrMessage
            local imageSize, sizeErr = ImageProcessing.getImageSize(sourcePath)

            if not imageSize then
                logger:error(("Could not get dimensions for %s: %s"):format(sourcePath, sizeErr or "unknown error"))
            else
                local requestedColumns = License.clampColumns(getProp("carouselColumns"))
                local aspectKey = License.clampAspect(getProp("carouselAspect"))
                if tonumber(getProp("carouselColumns")) ~= requestedColumns
                    or tostring(getProp("carouselAspect") or "") ~= aspectKey then
                    logger:error(
                        ("Clamped export to Free limits: %d slides, %s. Buy a full licence for 3:4 and 4–5 slides.")
                            :format(requestedColumns, aspectKey)
                    )
                end

                local layout, layoutErr = TileMath.computeLayout(
                    imageSize.width,
                    imageSize.height,
                    requestedColumns,
                    aspectKey,
                    {
                        useExistingCropFirst = getProp("carouselCropMode") == "existing_first",
                    }
                )

                if not layout then
                    logger:error(("Could not compute layout for %s: %s"):format(sourcePath, layoutErr or "unknown error"))
                else
                    local ok, processErr = ImageProcessing.exportTilesForPhoto({
                        sourcePath = sourcePath,
                        originalPhoto = photo,
                        renderedPath = sourcePath,
                        layout = layout,
                        columns = requestedColumns,
                        rows = layout.rows,
                        aspectKey = aspectKey,
                        tileWidthPx = tonumber(getProp("carouselTileWidthPx")),
                        jpegQuality = tonumber(getProp("carouselJpegQuality")),
                        createSubfolder = getProp("carouselCreateSubfolder"),
                        reverseColumns = getProp("carouselReverseColumns"),
                    })

                    if not ok then
                        logger:error(("Tile export failed for %s: %s"):format(sourcePath, processErr or "unknown error"))
                    else
                        -- Keep output folder clean: the rendered source file is only an intermediate for tiling.
                        if LrFileUtils.exists(sourcePath) == "file" then
                            LrFileUtils.delete(sourcePath)
                        end
                    end
                end
            end
        else
            logger:error(("Render failed for %s: %s"):format(photo:getFormattedMetadata("fileName"), renderedPathOrMessage))
        end
    end
end

LrTasks.startAsyncTask(function()
    logger:trace("Instagram Carousel Export provider loaded")
end)

return ExportServiceProvider

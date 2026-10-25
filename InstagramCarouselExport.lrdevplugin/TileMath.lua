local TileMath = {}

local RATIO_BY_KEY = {
    ["3:4"] = 3 / 4,
    ["4:5"] = 4 / 5,
}

local DEFAULT_ROWS = 1
local DEFAULT_ASPECT_TOLERANCE = 0.01

local function round(value)
    return math.floor(value + 0.5)
end

local function clampColumns(columns)
    if columns < 2 then
        return 2
    end
    if columns > 5 then
        return 5
    end
    return columns
end

function TileMath.parseAspectRatio(aspectKey)
    local ratio = RATIO_BY_KEY[aspectKey]
    if not ratio then
        return nil, ("Unsupported aspect ratio key: %s"):format(tostring(aspectKey))
    end
    return ratio
end

function TileMath.computeLayout(sourceWidth, sourceHeight, columns, aspectKey, options)
    if not sourceWidth or not sourceHeight or sourceWidth <= 0 or sourceHeight <= 0 then
        return nil, "source dimensions must be positive"
    end

    options = options or {}
    local parsedColumns = clampColumns(tonumber(columns) or 3)
    local tileAspect, ratioErr = TileMath.parseAspectRatio(aspectKey or "4:5")
    if not tileAspect then
        return nil, ratioErr
    end

    local rows = DEFAULT_ROWS
    local overallAspect = (parsedColumns * tileAspect) / rows
    local sourceAspect = sourceWidth / sourceHeight

    local cropWidth
    local cropHeight
    local cropMode = "center_crop"
    local tolerance = tonumber(options.aspectTolerance) or DEFAULT_ASPECT_TOLERANCE
    local useExistingFirst = options.useExistingCropFirst == true

    if useExistingFirst and math.abs(sourceAspect - overallAspect) <= tolerance then
        cropWidth = sourceWidth
        cropHeight = sourceHeight
        cropMode = "existing_crop_full_frame"
    else
        if sourceAspect > overallAspect then
            cropHeight = sourceHeight
            cropWidth = cropHeight * overallAspect
        else
            cropWidth = sourceWidth
            cropHeight = cropWidth / overallAspect
        end
    end

    local cropX = (sourceWidth - cropWidth) / 2
    local cropY = (sourceHeight - cropHeight) / 2

    local tileWidth = cropWidth / parsedColumns
    local tileHeight = cropHeight / rows

    local tiles = {}
    for row = 1, rows do
        for col = 1, parsedColumns do
            local left = cropX + (col - 1) * tileWidth
            local top = cropY + (row - 1) * tileHeight
            local right = (col == parsedColumns) and (cropX + cropWidth) or (left + tileWidth)
            local bottom = (row == rows) and (cropY + cropHeight) or (top + tileHeight)

            local x = round(left)
            local y = round(top)
            local w = math.max(1, round(right) - x)
            local h = math.max(1, round(bottom) - y)

            tiles[#tiles + 1] = {
                row = row,
                col = col,
                x = x,
                y = y,
                width = w,
                height = h,
            }
        end
    end

    return {
        rows = rows,
        columns = parsedColumns,
        tileAspect = tileAspect,
        overallAspect = overallAspect,
        cropMode = cropMode,
        sourceWidth = sourceWidth,
        sourceHeight = sourceHeight,
        crop = {
            x = round(cropX),
            y = round(cropY),
            width = round(cropWidth),
            height = round(cropHeight),
        },
        tiles = tiles,
    }
end

function TileMath.iterateOrderedTiles(layout, reverseColumns)
    local ordered = {}
    local columns = layout.columns
    for row = 1, layout.rows do
        if reverseColumns then
            for col = columns, 1, -1 do
                ordered[#ordered + 1] = layout.tiles[(row - 1) * columns + col]
            end
        else
            for col = 1, columns do
                ordered[#ordered + 1] = layout.tiles[(row - 1) * columns + col]
            end
        end
    end
    return ordered
end

return TileMath

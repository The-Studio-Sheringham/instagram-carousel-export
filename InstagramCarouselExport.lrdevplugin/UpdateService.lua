local LrDialogs = import "LrDialogs"
local LrFileUtils = import "LrFileUtils"
local LrHttp = import "LrHttp"
local LrPathUtils = import "LrPathUtils"
local LrTasks = import "LrTasks"

local UpdateService = {}

-- Host this JSON on GitHub (raw URL on main). Update when the repo owner/name changes.
local MANIFEST_URL = "https://raw.githubusercontent.com/The-Studio-Sheringham/instagram-carousel-export/main/update/version.json"

local PLUGIN_LUA_FILES = {
    "Info.lua",
    "ExportServiceProvider.lua",
    "ExportDialogSections.lua",
    "ImageProcessing.lua",
    "TileMath.lua",
    "MenuCropRatioHelper.lua",
    "UpdateService.lua",
    "MenuCheckForUpdates.lua",
    "License.lua",
    "CropRatioHelper.lua",
    "CreateCarouselPresets.lua",
    "OverlayPreview.lua",
    "README.md",
}

local function detectWindows()
    local appData = tostring(LrPathUtils.getStandardFilePath("appData") or "")
    if appData:match("^%a:[/\\]") then
        return true
    end
    return appData:find("\\", 1, true) ~= nil
end

local IS_WINDOWS = detectWindows()

local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function windowsQuote(value)
    return '"' .. tostring(value):gsub('"', '""') .. '"'
end

local function runCommand(command)
    local wrapped
    if IS_WINDOWS then
        wrapped = command
    else
        wrapped = "/bin/zsh -lc " .. shellQuote(command)
    end
    return LrTasks.execute(wrapped) == 0
end

local function tempPath(prefix, extension)
    return LrPathUtils.child(
        LrPathUtils.getStandardFilePath("temp"),
        ("%s-%d-%d%s"):format(prefix, os.time(), math.random(1000, 999999), extension or "")
    )
end

local function ensureDirectory(path)
    if LrFileUtils.exists(path) == "directory" then
        return true
    end
    return LrFileUtils.createAllDirectories(path)
end

local function writeBinaryFile(path, data)
    local handle, err = io.open(path, "wb")
    if not handle then
        return false, err or "could not open file"
    end
    handle:write(data)
    handle:close()
    return true
end

local function readJsonString(body, key)
    return body:match('"' .. key .. '"%s*:%s*"([^"]*)"')
end

local function readJsonNumber(body, key)
    return tonumber(body:match('"' .. key .. '"%s*:%s*(%d+)'))
end

local function parseManifest(body)
    if not body or body == "" then
        return nil, "Empty update manifest."
    end

    local version = readJsonString(body, "version")
    local downloadUrl = readJsonString(body, "downloadUrl")
    local notes = readJsonString(body, "notes") or ""
    local channel = readJsonString(body, "channel") or "free"
    local build = readJsonNumber(body, "build")

    if not version or not downloadUrl or not build then
        return nil, "Update manifest is missing version, build, or downloadUrl."
    end

    return {
        version = version,
        build = build,
        downloadUrl = downloadUrl,
        notes = notes,
        channel = channel,
    }
end

local function parseVersionFromInfoLua()
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

local function currentVersion()
    -- Lightroom does not always expose _PLUGIN.version to Lua scripts (shows as 0.0.0.0).
    -- Prefer reading VERSION from Info.lua next to the running plug-in.
    local fromInfo = parseVersionFromInfoLua()
    if fromInfo and (fromInfo.build > 0 or fromInfo.major > 0) then
        return fromInfo
    end

    local v = (_PLUGIN and _PLUGIN.version) or {}
    if type(v) == "string" then
        local major, minor, revision, build = v:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
        if not major then
            major, minor, revision = v:match("^(%d+)%.(%d+)%.(%d+)$")
        end
        return {
            major = tonumber(major) or 0,
            minor = tonumber(minor) or 0,
            revision = tonumber(revision) or 0,
            build = tonumber(build) or 0,
        }
    end

    return {
        major = tonumber(v.major) or 0,
        minor = tonumber(v.minor) or 0,
        revision = tonumber(v.revision) or 0,
        build = tonumber(v.build) or 0,
    }
end

local function versionLabel(v)
    return ("%d.%d.%d.%d"):format(v.major or 0, v.minor or 0, v.revision or 0, v.build or 0)
end

local function isNewer(remoteBuild, localBuild)
    return (tonumber(remoteBuild) or 0) > (tonumber(localBuild) or 0)
end

local function pluginRoot()
    if _PLUGIN and _PLUGIN.path then
        return _PLUGIN.path
    end
    return nil
end

local function findPayloadRoot(extractDir)
    if LrFileUtils.exists(LrPathUtils.child(extractDir, "Info.lua")) == "file" then
        return extractDir
    end

    for child in LrFileUtils.directoryEntries(extractDir) do
        local name = LrPathUtils.leafName(child)
        if name ~= "." and name ~= ".." then
            if LrFileUtils.exists(child) == "directory" then
                if LrFileUtils.exists(LrPathUtils.child(child, "Info.lua")) == "file" then
                    return child
                end
            end
        end
    end

    return nil
end

local function unzipArchive(zipPath, destDir)
    ensureDirectory(destDir)
    if IS_WINDOWS then
        local script = table.concat({
            "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command",
            windowsQuote(
                ("Expand-Archive -LiteralPath %s -DestinationPath %s -Force"):format(
                    windowsQuote(zipPath),
                    windowsQuote(destDir)
                )
            ),
        }, " ")
        return runCommand(script)
    end

    return runCommand(("/usr/bin/unzip -o %s -d %s"):format(shellQuote(zipPath), shellQuote(destDir)))
end

local function copyUpdateFiles(sourceRoot, destRoot)
    local copied = 0
    for _, name in ipairs(PLUGIN_LUA_FILES) do
        local src = LrPathUtils.child(sourceRoot, name)
        if LrFileUtils.exists(src) == "file" then
            local dest = LrPathUtils.child(destRoot, name)
            if LrFileUtils.exists(dest) == "file" then
                LrFileUtils.delete(dest)
            end
            local ok = LrFileUtils.copy(src, dest)
            if not ok then
                return false, ("Failed to copy %s"):format(name)
            end
            copied = copied + 1
        end
    end

    if copied == 0 then
        return false, "Update package did not contain any plugin files."
    end
    if LrFileUtils.exists(LrPathUtils.child(destRoot, "Info.lua")) ~= "file" then
        return false, "Update package is missing Info.lua."
    end
    return true
end

local function fetchManifest()
    local body, headers = LrHttp.get(MANIFEST_URL)
    if not body then
        return nil, "Could not reach the update server. Check your internet connection."
    end

    local status = headers and tonumber(headers.status)
    if status and (status < 200 or status >= 300) then
        return nil, ("Update server returned HTTP %d."):format(status)
    end

    return parseManifest(body)
end

local function downloadUpdate(downloadUrl)
    local body, headers = LrHttp.get(downloadUrl)
    if not body or body == "" then
        return nil, "Could not download the update package."
    end

    local status = headers and tonumber(headers.status)
    if status and (status < 200 or status >= 300) then
        return nil, ("Download failed (HTTP %d)."):format(status)
    end

    local contentType = tostring((headers and (headers["Content-Type"] or headers["content-type"])) or "")
    if contentType:find("text/html", 1, true) then
        return nil, "Download URL returned a web page instead of a zip. Check the GitHub release asset URL."
    end

    local zipPath = tempPath("instagram-carousel-update", ".zip")
    local wrote, writeErr = writeBinaryFile(zipPath, body)
    if not wrote then
        return nil, ("Could not save update zip: %s"):format(writeErr or "unknown")
    end
    return zipPath
end

local function installFromZip(zipPath)
    local root = pluginRoot()
    if not root then
        return false, "Could not locate the installed plugin folder."
    end

    local extractDir = tempPath("instagram-carousel-extract", "")
    ensureDirectory(extractDir)

    if not unzipArchive(zipPath, extractDir) then
        return false, "Could not unzip the update package."
    end

    local payload = findPayloadRoot(extractDir)
    if not payload then
        return false, "Zip did not contain a valid plugin (Info.lua missing)."
    end

    local ok, err = copyUpdateFiles(payload, root)
    LrFileUtils.delete(zipPath)
    -- Best-effort temp cleanup; ignore failures.
    pcall(function()
        for filePath in LrFileUtils.recursiveFiles(extractDir) do
            LrFileUtils.delete(filePath)
        end
    end)

    return ok, err
end

function UpdateService.getManifestUrl()
    return MANIFEST_URL
end

function UpdateService.checkForUpdate(options)
    options = options or {}
    local silentIfCurrent = options.silentIfCurrent == true

    local localVersion = currentVersion()
    local remote, err = fetchManifest()
    if not remote then
        LrDialogs.message("Check for Updates", err or "Update check failed.", "warning")
        return false
    end

    if not isNewer(remote.build, localVersion.build) then
        if not silentIfCurrent then
            LrDialogs.message(
                "Check for Updates",
                ("You're up to date.\n\nInstalled: %s\nLatest: %s (%s)")
                    :format(versionLabel(localVersion), remote.version, remote.channel),
                "info"
            )
        end
        return false
    end

    local notes = remote.notes
    if notes == "" then
        notes = "Bug fixes and improvements."
    end

    local choice = LrDialogs.confirm(
        "Update Available",
        ("A new version is available.\n\nInstalled: %s\nLatest: %s (build %d, %s)\n\n%s\n\nInstall now? Lightroom will need a plug-in reload afterwards.")
            :format(versionLabel(localVersion), remote.version, remote.build, remote.channel, notes),
        "Install Update",
        "Not Now"
    )

    if choice ~= "ok" then
        return false
    end

    local zipPath, downloadErr = downloadUpdate(remote.downloadUrl)
    if not zipPath then
        LrDialogs.message("Update Failed", downloadErr or "Download failed.", "critical")
        return false
    end

    local installed, installErr = installFromZip(zipPath)
    if not installed then
        LrDialogs.message("Update Failed", installErr or "Could not install update.", "critical")
        return false
    end

    LrDialogs.message(
        "Update Installed",
        "The new files are in place.\n\nFinish the update:\n1) File > Plug-in Manager...\n2) Select Instagram Carousel Export\n3) Click Reload Plug-in\n   (or restart Lightroom)\n\nThen you're on the new version.",
        "info"
    )
    return true
end

function UpdateService.runCheckFromUi()
    LrTasks.startAsyncTask(function()
        UpdateService.checkForUpdate({ silentIfCurrent = false })
    end)
end

return UpdateService

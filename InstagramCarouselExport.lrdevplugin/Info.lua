return {
    LrSdkVersion = 13.0,
    LrSdkMinimumVersion = 6.0,
    LrToolkitIdentifier = "com.garethgabriel.instagramcarousel",
    LrPluginName = "Instagram Carousel Export",

    LrExportServiceProvider = {
        title = "Instagram Carousel Export",
        file = "ExportServiceProvider.lua",
    },
    LrLibraryMenuItems = {
        {
            title = "Instagram Carousel Crop Ratio Helper...",
            file = "MenuCropRatioHelper.lua",
        },
        {
            title = "Check for Instagram Carousel Updates...",
            file = "MenuCheckForUpdates.lua",
        },
    },
    LrExportMenuItems = {
        {
            title = "Instagram Carousel Crop Ratio Helper...",
            file = "MenuCropRatioHelper.lua",
        },
        {
            title = "Check for Instagram Carousel Updates...",
            file = "MenuCheckForUpdates.lua",
        },
    },
    VERSION = { major = 1, minor = 0, revision = 1, build = 25 },
}

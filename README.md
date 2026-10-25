# Instagram Carousel Export

Lightroom Classic export plug-in that splits one photo into Instagram carousel tiles.

## Install

1. Download the latest `.lrplugin.zip` from [Releases](https://github.com/The-Studio-Sheringham/instagram-carousel-export/releases).
2. Unzip, then in Lightroom Classic: **File > Plug-in Manager > Add**.
3. Export with **Instagram Carousel Export**, or use **Plug-in Extras > Instagram Carousel Crop Ratio Helper...**.

## In-app updates

**Check for updates** (Export dialog, Crop Ratio Helper, or Plug-in Extras) reads:

`update/version.json`

If a newer `build` is listed, it downloads the release zip, installs into the plug-in folder, then asks you to **Reload Plug-in** in Plug-in Manager.

## Shipping a new version

1. Bump `VERSION` in `InstagramCarouselExport.lrdevplugin/Info.lua` (increase `build`).
2. Update `update/version.json` (`version`, `build`, `downloadUrl`, `notes`).
3. Commit and push to `main`.
4. Create the release zip (folder must contain `Info.lua`):

```bash
./scripts/package-release.sh 1.0.0
```

5. Create a GitHub Release tagged `v1.0.0` and upload `InstagramCarouselExport.lrplugin.zip`.
6. Confirm `downloadUrl` in `update/version.json` matches that asset URL, then push if needed.

## Repo layout

- `InstagramCarouselExport.lrdevplugin/` — plug-in source (rename to `.lrplugin` for release if you prefer)
- `update/version.json` — update manifest for in-app checks
- `scripts/package-release.sh` — builds the release zip

## Support

- https://garethgabriel.com
- https://thestudiosheringham.com
- support@thestudiosheringham.com

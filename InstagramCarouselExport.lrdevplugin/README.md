# Instagram Carousel Export (Lightroom Classic)

This Lightroom Classic export plugin splits each exported image into carousel-ready tiles.

## Features

- Variable columns: Free `2–3`, Pro `2–5`
- Fixed rows: `1` (single-row carousel strip)
- Tile ratios: `3:4` portrait or `4:5` portrait
- Presets: `IG Carousel x2..x5` for both `3:4` and `4:5`
- Crop mode: use existing Lightroom crop first, with center-crop fallback
- Deterministic tile naming: `photo_c{cols}x1_r{row}_c{col}.jpg`
- In-app **Check for updates** (downloads + installs, then reload in Plug-in Manager)
- In-app support + links: website and email buttons in Export + Crop Ratio Helper

## Updates (GitHub)

1. Publish a GitHub Release zip of the `.lrplugin` folder.
2. Update `update/version-free.json` (and `version-paid.json` for Pro) with the new `build`, `version`, and `downloadUrl`.
3. Point `UpdateService.lua` `MANIFEST_URL` at the raw JSON on GitHub.
4. Users click **Check for updates** → Install → **Plug-in Manager > Reload Plug-in**.

## Compatibility

- Lightroom Classic on macOS Intel: supported
- Lightroom Classic on macOS Apple Silicon (M chips): supported
- Lightroom Classic on Windows: supported in this build (uses PowerShell + .NET `System.Drawing` for crop/resize)
- Lightroom (cloud app, non-Classic): Adobe does not expose the same export plug-in SDK used here

## Install

1. Copy `InstagramCarouselExport.lrdevplugin` to a stable folder on disk.
2. In Lightroom Classic, open **File > Plug-in Manager...**
3. Click **Add**, select `InstagramCarouselExport.lrdevplugin`, then enable it.
4. Open **File > Export...** and choose **Instagram Carousel Export** settings section.

## Export Workflow

1. Select one or more photos in Lightroom.
2. Open **Export** dialog.
3. In **Instagram Carousel** section:
   - Choose a `Preset` (or keep `Custom`)
   - Choose `Carousel slides` (`2-5`)
   - Choose `Post ratio` (`3:4` or `4:5`)
   - Choose `Crop source mode`:
     - `Use existing Lightroom crop first (fallback to center crop)`
     - `Always center crop`
   - Optionally set:
     - `Tile width (px)` (default `1080`)
     - `JPEG quality` (default `92`)
     - `Create per-photo subfolder`
     - `Reverse slide order (for posting)`
   - If pre-cropping in Develop, use the shown **Suggested Develop Crop ratio** helper and click `Copy Ratio` or `Copy Decimal`.
4. Export. The plugin renders each selected photo and writes all tiles.

## Pre-Export Crop Ratio Helper

- Open **Library > Plug-in Extras > Instagram Carousel Crop Ratio Helper...**
- Pick columns (`2-5`) and tile ratio (`3:4` or `4:5`)
- Click `Copy Ratio` or `Copy Decimal`, then use that value in Develop crop before opening Export

## Auto-Create Export Presets

- Open **Instagram Carousel Crop Ratio Helper...** from Plug-in Extras
- Click **Create Export Presets**
- The plugin writes the standard `IG Carousel x2..x5` presets for both `3:4` and `4:5` into Lightroom's **Instagram Carousel Export** preset folder
- Re-open Export dialog if the left preset list does not refresh immediately

## Output Naming

For a source image named `sunset.jpg` at `4` columns:

- `sunset_c4x1_r1_c1.jpg`
- `sunset_c4x1_r1_c2.jpg`
- ...
- `sunset_c4x1_r1_c4.jpg`

## Validation and Test Checklist

Run the checks below after loading the plugin:

- Columns
  - [ ] `2` exports exactly `2` tiles
  - [ ] `3` exports exactly `3` tiles
  - [ ] `4` exports exactly `4` tiles
  - [ ] `5` exports exactly `5` tiles
- Aspect ratios
  - [ ] `3:4` tile dimensions match width:height `3:4`
  - [ ] `4:5` tile dimensions match width:height `4:5`
- Geometry
  - [ ] Tile ordering is consistent (left-to-right unless reverse order enabled)
- Stability
  - [ ] Plugin appears in Export dialog without runtime errors
  - [ ] Multiple selected photos export successfully in one run

## Credits

- Built by Gareth: https://garethgabriel.com
- At The Studio Sheringham: https://thestudiosheringham.com
- Support: support@thestudiosheringham.com

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

## Free vs full licence

| | Free | Full licence |
|---|---|---|
| Slides | 2–3 | 2–5 |
| Ratios | 4:5 only | 3:4 + 4:5 |
| Presets | Free set only | Full pack |
| UI | Buy me a coffee + Buy full licence | No upsell buttons |

- Free build: `License.forcePro = false` (default in source)
- Paid zip: `./scripts/package-release.sh 1.0.1 paid` sets `forcePro = true`
- Or unlock free install with key `ICE-PRO-UNLOCK` (temporary test key)

## Shipping a new version

1. Bump `VERSION` in `InstagramCarouselExport.lrdevplugin/Info.lua` (increase `build`).
2. Update `update/version.json` (`version`, `build`, `downloadUrl`, `notes`).
3. Commit and push to `main`.
4. Build zips:

```bash
./scripts/package-release.sh 1.0.1 free
./scripts/package-release.sh 1.0.1 paid
```

5. Create a GitHub Release tagged `v1.0.1` and upload the zip(s).
6. Point free users’ `downloadUrl` at the free asset.

## Repo layout

- `InstagramCarouselExport.lrdevplugin/` — plug-in source (rename to `.lrplugin` for release if you prefer)
- `update/version.json` — update manifest for in-app checks
- `scripts/package-release.sh` — builds the release zip

## Support

- https://garethgabriel.com
- https://thestudiosheringham.com
- support@thestudiosheringham.com

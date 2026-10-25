#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: ./scripts/package-release.sh 1.0.0"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/InstagramCarouselExport.lrdevplugin"
STAGE="$ROOT/dist/InstagramCarouselExport.lrplugin"
OUT_DIR="$ROOT/dist"
ZIP_NAME="InstagramCarouselExport.lrplugin.zip"

rm -rf "$STAGE"
mkdir -p "$STAGE" "$OUT_DIR"

rsync -a --exclude '.DS_Store' "$SRC/" "$STAGE/"

(
  cd "$OUT_DIR"
  rm -f "$ZIP_NAME"
  # Zip the .lrplugin folder so unzip produces InstagramCarouselExport.lrplugin/Info.lua
  zip -r "$ZIP_NAME" "InstagramCarouselExport.lrplugin" -x "*.DS_Store"
)

echo "Created $OUT_DIR/$ZIP_NAME"
echo "Upload this asset to GitHub Release v${VERSION}"
echo "Then set downloadUrl to:"
echo "https://github.com/The-Studio-Sheringham/instagram-carousel-export/releases/download/v${VERSION}/${ZIP_NAME}"

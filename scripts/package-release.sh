#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
EDITION="${2:-free}"

if [[ -z "$VERSION" ]]; then
  echo "Usage: ./scripts/package-release.sh 1.0.1 [free|paid]"
  exit 1
fi

if [[ "$EDITION" != "free" && "$EDITION" != "paid" ]]; then
  echo "Edition must be free or paid"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/InstagramCarouselExport.lrdevplugin"
STAGE="$ROOT/dist/InstagramCarouselExport.lrplugin"
OUT_DIR="$ROOT/dist"
ZIP_NAME="InstagramCarouselExport-${EDITION}.lrplugin.zip"

rm -rf "$STAGE"
mkdir -p "$STAGE" "$OUT_DIR"

rsync -a --exclude '.DS_Store' "$SRC/" "$STAGE/"

if [[ "$EDITION" == "paid" ]]; then
  # Paid zip ships fully unlocked (no upsell buttons).
  python3 - "$STAGE/License.lua" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
text = path.read_text()
if "License.forcePro = false" not in text:
    raise SystemExit("Could not find License.forcePro = false to flip for paid build")
path.write_text(text.replace("License.forcePro = false", "License.forcePro = true", 1))
print("Set License.forcePro = true for paid build")
PY
fi

(
  cd "$OUT_DIR"
  rm -f "$ZIP_NAME"
  zip -r "$ZIP_NAME" "InstagramCarouselExport.lrplugin" -x "*.DS_Store"
)

echo "Created $OUT_DIR/$ZIP_NAME ($EDITION)"
echo "Upload this asset to GitHub Release v${VERSION}"
echo "Suggested downloadUrl:"
echo "https://github.com/The-Studio-Sheringham/instagram-carousel-export/releases/download/v${VERSION}/${ZIP_NAME}"

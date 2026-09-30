#!/usr/bin/env bash
# Builds Resources/AppIcon.icns from a single 1024x1024 PNG master.
# Usage: scripts/make_icns.sh path/to/icon-1024.png
set -euo pipefail

SRC="${1:?usage: make_icns.sh <1024x1024 png>}"
[ -f "$SRC" ] || { echo "source not found: $SRC" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Resources/AppIcon.icns"
SET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$SET"

# Each base point size needs an @1x and @2x rendition.
for sz in 16 32 128 256 512; do
    sips -z "$sz" "$sz"            "$SRC" --out "$SET/icon_${sz}x${sz}.png"    >/dev/null
    sips -z "$((sz*2))" "$((sz*2))" "$SRC" --out "$SET/icon_${sz}x${sz}@2x.png" >/dev/null
done

iconutil -c icns "$SET" -o "$OUT"
echo "Wrote $OUT"
echo "Now re-run scripts/build_app.sh to bundle it."

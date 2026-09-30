#!/usr/bin/env bash
# Builds "URL Router.app" from the Swift package and registers it with Launch Services.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
APP="$ROOT/URL Router.app"
EXE="URLRouter"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN="$ROOT/.build/$CONFIG/$EXE"
[ -f "$BIN" ] || { echo "build product not found at $BIN" >&2; exit 1; }

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXE"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# App icon (optional): generate with scripts/make_icns.sh from a 1024x1024 PNG.
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "==> ad-hoc codesign"
codesign --force --sign - "$APP"

echo "==> registering with Launch Services"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$APP"

echo
echo "Built: $APP"
echo "Test routing:   open '$APP' --args 'https://github.com'"
echo "Dry-run a rule: '$APP/Contents/MacOS/$EXE' --dry-run 'https://github.com'"
echo "Edit rules:     open '$APP'"
echo "Then set it as the default browser from the app, or in System Settings → Desktop & Dock."

#!/bin/sh
# Installs the latest Tray release:
#   curl -fsSL https://raw.githubusercontent.com/lrjulia/tray/main/install.sh | sh
set -e

REPO="lrjulia/tray"
URL="https://github.com/$REPO/releases/latest/download/Tray.zip"

if [ "$(uname)" != "Darwin" ]; then
  echo "Tray only runs on macOS." >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Tray…"
curl -fsSL "$URL" -o "$TMP/Tray.zip"
ditto -x -k "$TMP/Tray.zip" "$TMP"

DEST="/Applications"
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

pkill -x Tray 2>/dev/null || true
rm -rf "$DEST/Tray.app"
mv "$TMP/Tray.app" "$DEST/"
# Builds that aren't notarized yet would otherwise be blocked by Gatekeeper.
xattr -dr com.apple.quarantine "$DEST/Tray.app" 2>/dev/null || true

echo "Installed in $DEST. Opening Tray — press ⌘⇧V to show it."
open "$DEST/Tray.app"

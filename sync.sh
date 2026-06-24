#!/bin/bash
# Sync extensions/les/ into the app bundle and optionally restart the app

APP="Live Enhancement Suite Custom"
BUNDLE=$(mdfind "kMDItemCFBundleIdentifier == 'org.hammerspoon.Hammerspoon'" 2>/dev/null | grep "DerivedData" | head -1)
if [ -z "$BUNDLE" ]; then
  # Fallback: find via running process
  BUNDLE=$(ps -axo args | grep -v grep | grep "$APP" | grep -o '/.*\.app' | head -1)
fi
if [ -z "$BUNDLE" ]; then
  echo "Error: cannot locate app bundle" >&2
  exit 1
fi

DEST="$BUNDLE/Contents/Resources/extensions/hs/les"
SRC="$(cd "$(dirname "$0")" && pwd)/extensions/les"

if [ ! -d "$DEST" ]; then
  echo "Error: destination not found: $DEST" >&2
  exit 1
fi

cp -R "$SRC/." "$DEST/"
echo "Synced → $BUNDLE"
echo "LES メニューから「再読み込み」を実行してください"

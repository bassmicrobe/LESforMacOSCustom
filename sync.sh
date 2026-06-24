#!/bin/bash
# Sync extensions/les/ into the running app bundle, then prompt for a reload.
# Robust bundle detection: gather candidate .app bundles (running process first,
# then Spotlight), and pick the first one that actually contains the LES
# extension directory — rather than blindly taking the first "DerivedData" hit.
set -u

APP="Live Enhancement Suite Custom"
SRC="$(cd "$(dirname "$0")" && pwd)/extensions/les"

if [ ! -d "$SRC" ]; then
  echo "Error: source not found: $SRC" >&2
  exit 1
fi

candidates=()

# 1) Running Hammerspoon / LES process executable -> its .app bundle (most reliable).
#    `comm=` yields the full executable path; strip /Contents/MacOS/<bin> to get the .app.
while IFS= read -r p; do
  [ -n "$p" ] && candidates+=("$p")
done < <(ps -axo comm= 2>/dev/null \
  | grep -iE "Hammerspoon|${APP}" \
  | sed -E 's#^(.*\.app)/Contents/MacOS/[^/]*$#\1#' \
  | grep '\.app$')

# 2) Spotlight matches for the Hammerspoon bundle id (all of them).
while IFS= read -r p; do
  [ -n "$p" ] && candidates+=("$p")
done < <(mdfind "kMDItemCFBundleIdentifier == 'org.hammerspoon.Hammerspoon'" 2>/dev/null)

# Pick the first candidate that actually contains the LES extension directory.
DEST=""
BUNDLE=""
for b in "${candidates[@]}"; do
  d="$b/Contents/Resources/extensions/hs/les"
  if [ -d "$d" ]; then
    DEST="$d"
    BUNDLE="$b"
    break
  fi
done

if [ -z "$DEST" ]; then
  echo "Error: could not locate an app bundle containing extensions/hs/les" >&2
  echo "Checked ${#candidates[@]} candidate bundle(s)." >&2
  echo "Is Hammerspoon (${APP}) running?" >&2
  exit 1
fi

cp -R "$SRC/." "$DEST/"
echo "Synced → $BUNDLE"
echo "LES メニューから「再読み込み」を実行してください"

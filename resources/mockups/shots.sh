#!/usr/bin/env bash
# Renders each scene of layout.html to docs/public/mockups/<scene>.jpg and copies the page there, for the docs.
# Usage (repo root): resources/mockups/shots.sh   (needs Google Chrome)
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 resources/mockups/build.py
out=docs/public/mockups
mkdir -p "$out"
cp resources/mockups/layout.html "$out/layout.html"
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for scene in $(grep -o "data-s='[A-Z0-9]*'" resources/mockups/layout.html | cut -d"'" -f2); do
    profile=$(mktemp -d)
    size=1204,564; [[ $scene == I || $scene == J ]] && size=1228,310
    "$chrome" --headless=new --user-data-dir="$profile" --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
        --window-size=$size --screenshot="$profile/shot.png" \
        "file://$PWD/resources/mockups/layout.html?scene=$scene&bare=1" >/dev/null 2>&1
    sips -s format jpeg -s formatOptions 82 "$profile/shot.png" --out "$out/$scene.jpg" >/dev/null
    rm -rf "$profile"
done
ls "$out"

#!/bin/bash
# Installs or updates Radio from the latest GitHub release.
# curl leaves no quarantine flag, so macOS opens the unnotarized app without the "can't verify" block.
set -euo pipefail

url=https://github.com/eggplantdev/radio-bar/releases/latest/download/Radio.zip
dest=/Applications
[[ -w $dest ]] || dest=$HOME/Applications
mkdir -p "$dest"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "Pobieram Radio…"
curl -fsSL "$url" -o "$tmp/Radio.zip"
ditto -x -k "$tmp/Radio.zip" "$tmp"

osascript -e 'quit app id "pl.local.radio"' 2>/dev/null || true
while pgrep -xq Radio; do sleep 0.2; done
rm -rf "$dest/Radio.app"
ditto "$tmp/Radio.app" "$dest/Radio.app"
open "$dest/Radio.app"
echo "Gotowe: $dest/Radio.app — ikonka jest na pasku menu."

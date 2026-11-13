#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"

mode=release
[[ "${1:-}" == --debug ]] && mode=debug

if [[ $mode == debug ]]; then
  app=build/Radio-debug.app
  flags=(-D DEBUGHOOK)
  sources=(src/main.swift src/debughook.swift)
else
  app=build/Radio.app
  flags=()
  sources=(src/main.swift)
fi

rm -rf "$app" build/arch
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build/arch
if [[ $mode == debug ]]; then
  swiftc -O $flags $sources -o "$app/Contents/MacOS/Radio"
else
  for arch in arm64 x86_64; do
    swiftc -O -target $arch-apple-macos13 $sources -o build/arch/Radio-$arch
  done
  lipo -create build/arch/Radio-* -output "$app/Contents/MacOS/Radio"
fi
cp resources/Info.plist "$app/Contents/"
cp resources/AppIcon.icns resources/logo-*.png "$app/Contents/Resources/"
[[ $mode == debug ]] && plutil -replace CFBundleIdentifier -string pl.local.radio.debug "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "built $app"

if [[ "${1:-}" == --zip ]]; then
  version=$(plutil -extract CFBundleShortVersionString raw resources/Info.plist)
  mkdir -p dist
  rm -f dist/Radio-$version.zip
  ditto -c -k --keepParent "$app" dist/Radio-$version.zip
  echo "packed dist/Radio-$version.zip"
fi

if [[ "${1:-}" == --install ]]; then
  osascript -e 'quit app id "pl.local.radio"' || true
  while pgrep -f "$HOME/Applications/Radio.app" >/dev/null; do sleep 0.2; done
  rm -rf ~/Applications/Radio.app
  ditto "$app" ~/Applications/Radio.app
  open ~/Applications/Radio.app || { sleep 2; open ~/Applications/Radio.app; }
  echo "installed ~/Applications/Radio.app"
fi

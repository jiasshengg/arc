#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
swift scripts/generate-dmg-background.swift
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/Arc.app/Contents/Info.plist)
output="$PWD/dist/Arc-$version-macOS-$(uname -m).dmg"
work=$(mktemp -d "$PWD/.build/dmg/package.XXXXXX")
mount="$work/mount"
mounted=false
cleanup() {
  if [[ "$mounted" == true ]]; then
    if ! hdiutil detach "$mount" -quiet; then
      echo "Could not detach $mount; keeping temporary files in $work." >&2
      return
    fi
  fi
  rm -rf "$work"
}
trap cleanup EXIT
mkdir -p "$work/staging/.background"
ditto dist/Arc.app "$work/staging/Arc.app"
ln -s /Applications "$work/staging/Applications"
cp .build/dmg/background.tiff "$work/staging/.background/"
hdiutil create -quiet -volname Arc -srcfolder "$work/staging" -format UDRW "$work/writable.dmg"
hdiutil attach -quiet -nobrowse -mountpoint "$mount" "$work/writable.dmg"
mounted=true

# Finder writes portable background aliases and icon positions to .DS_Store.
# macOS may request Automation access to Finder on the first build.
osascript - "$mount" <<'APPLESCRIPT'
on run argv
  set imagePath to POSIX file (item 1 of argv) as text
  tell application "Finder"
    set imageFolder to folder imagePath
    open imageFolder
    tell container window of imageFolder
      set current view to icon view
      set toolbar visible to false
      set statusbar visible to false
      set bounds to {160, 160, 820, 608}
    end tell
    set viewOptions to icon view options of container window of imageFolder
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.tiff" of imageFolder
    set position of item "Arc.app" of imageFolder to {190, 230}
    set position of item "Applications" of imageFolder to {470, 230}
    close container window of imageFolder
    open imageFolder
    update imageFolder without registering applications
    delay 2
    close container window of imageFolder
  end tell
end run
APPLESCRIPT
sync
test -s "$mount/.DS_Store"
codesign --verify --deep --strict "$mount/Arc.app"
hdiutil detach -quiet "$mount"
mounted=false
hdiutil convert -quiet "$work/writable.dmg" -format UDZO -o "$work/Arc.dmg"
mv "$work/Arc.dmg" "$output"
echo "Built $output"
shasum -a 256 "$output"

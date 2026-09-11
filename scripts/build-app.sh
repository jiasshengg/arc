#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-debug}"
if [[ "$configuration" != debug && "$configuration" != release ]]; then
  echo "Usage: $0 [debug|release]" >&2
  exit 1
fi
swift build -c "$configuration"
bin_path="$(swift build -c "$configuration" --show-bin-path)"
app="$PWD/dist/Arc.app"
framework="$app/Contents/Frameworks/MediaRemoteAdapter.framework"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$framework/Versions/A/Resources"
cp "$bin_path/Arc" "$app/Contents/MacOS/Arc"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl "$app/Contents/Resources/"
cp Vendor/mediaremote-adapter/LICENSE "$app/Contents/Resources/MediaRemoteAdapter-LICENSE"
cp LICENSE "$app/Contents/Resources/Arc-LICENSE"
# Match the app architecture. Build on Intel or Apple Silicon without Homebrew dependencies.
xcrun clang -dynamiclib -fobjc-arc -fvisibility=default -mmacosx-version-min=14.0 \
  -I Vendor/mediaremote-adapter/include -I Vendor/mediaremote-adapter/src \
  Vendor/mediaremote-adapter/src/adapter/*.m Vendor/mediaremote-adapter/src/private/*.m \
  Vendor/mediaremote-adapter/src/utility/*.m \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
  -o "$framework/Versions/A/MediaRemoteAdapter"
cat > "$framework/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
<key>CFBundleIdentifier</key><string>org.arc-island.MediaRemoteAdapter</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
ln -sfn A "$framework/Versions/Current"
ln -sfn Versions/Current/MediaRemoteAdapter "$framework/MediaRemoteAdapter"
ln -sfn Versions/Current/Resources "$framework/Resources"
codesign --force --sign - "$framework"
codesign --force --sign - "$app"
echo "Built $app"

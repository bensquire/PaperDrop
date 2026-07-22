#!/bin/zsh
# Build PaperDrop.app from the SwiftPM executable.
#
# Env overrides (used by CI):
#   VERSION           marketing version (default 0.1.0)
#   CODESIGN_IDENTITY signing identity ("-" for ad-hoc; default: local
#                     Developer ID)
set -e
cd "$(dirname "$0")"

VERSION="${VERSION:-0.1.0}"
IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: BENJAMIN RICHARD SOUIRE (SZHK3JVH6J)}"

swift build -c release -Xswiftc -Osize
APP=PaperDrop.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp .build/release/PaperDrop $APP/Contents/MacOS/
strip -rSTx $APP/Contents/MacOS/PaperDrop
cp icon/PaperDrop.icns $APP/Contents/Resources/
cat > $APP/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>PaperDrop</string>
  <key>CFBundleIdentifier</key><string>com.bensquire.paperdrop</string>
  <key>CFBundleExecutable</key><string>PaperDrop</string>
  <key>CFBundleIconFile</key><string>PaperDrop</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
codesign --force --options runtime --timestamp --sign "$IDENTITY" $APP
echo "built and signed $PWD/$APP (v$VERSION)"

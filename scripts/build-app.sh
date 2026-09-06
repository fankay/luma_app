#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CLANG_MODULE_CACHE_PATH=/tmp/luma-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/luma-module-cache swift build --disable-sandbox --cache-path /tmp/luma-cache -c release --scratch-path /tmp/luma-release
bash scripts/build-icon.sh
mkdir -p build/Luma.app/Contents/MacOS build/Luma.app/Contents/Resources
cp Assets/AppIcon.icns build/Luma.app/Contents/Resources/AppIcon.icns
cp /tmp/luma-release/release/Luma build/Luma.app/Contents/MacOS/Luma
cat > build/Luma.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Luma</string>
<key>CFBundleIdentifier</key><string>studio.luma.image-tools</string>
<key>CFBundleName</key><string>Luma</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - build/Luma.app

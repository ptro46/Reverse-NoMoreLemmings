#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/build/Lemmings Mac.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mkdir -p work/ModuleCache
xcrun swiftc -module-cache-path "$PWD/work/ModuleCache" -O -swift-version 5 -target arm64-apple-macosx13.0 Sources/*.swift -framework AppKit -framework AVFoundation -framework ImageIO -o "$APP/Contents/MacOS/LemmingsMac"
/usr/bin/rsync -a --delete --exclude 'raw' --exclude 'decoded' --exclude 'music/*.wav' Assets/ "$APP/Contents/Resources/Assets/"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LemmingsMac</string>
<key>CFBundleIdentifier</key><string>local.ptro.lemmingsmac</string>
<key>CFBundleName</key><string>Lemmings Mac</string>
<key>CFBundleDisplayName</key><string>Lemmings Mac</string>
<key>CFBundleShortVersionString</key><string>0.1.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
printf 'Application : %s\n' "$APP"

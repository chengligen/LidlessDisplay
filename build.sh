#!/bin/zsh
set -eu
cd "${0:A:h}"
STAGING=$(mktemp -d /tmp/lidless-build.XXXXXX)
APP="$STAGING/LidlessDisplay.app"
mkdir -p "$APP/Contents/MacOS"
clang -fmodules -fmodules-cache-path="$STAGING/cache" -framework Foundation -framework CoreGraphics -framework IOKit EDIDOverride.m -o "$APP/Contents/MacOS/EDIDOverride"
codesign --force --sign - "$APP/Contents/MacOS/EDIDOverride"
if [[ -d EDID ]]; then
    mkdir -p "$APP/Contents/Resources/EDID"
    for profile in EDID/*.bin; do
        cat "$profile" > "$APP/Contents/Resources/EDID/${profile:t}"
    done
fi
xcrun swiftc -O -module-cache-path /tmp/lidless-swift-cache -framework AppKit -framework CoreGraphics -framework IOKit LidlessDisplay.swift -o "$APP/Contents/MacOS/LidlessDisplay"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LidlessDisplay</string>
<key>CFBundleIdentifier</key><string>cn.os-o.LidlessDisplay</string>
<key>CFBundleName</key><string>LidlessDisplay</string>
<key>CFBundleDisplayName</key><string>开盖外屏</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p build
ditto -c -k --norsrc --keepParent "$APP" build/LidlessDisplay.zip
ditto --norsrc "$APP" build/LidlessDisplay.app
echo "$PWD/build/LidlessDisplay.app"

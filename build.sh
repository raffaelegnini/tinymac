#!/bin/bash
# Builds TinyMac.app and TinyMacPlus.app (release, universal when possible) into ./dist,
# signs them ad hoc and zips them for a release.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=1.1.1
SHORT=1.1.1

swift build -c release --arch arm64 --arch x86_64 2>/dev/null || swift build -c release
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path 2>/dev/null || swift build -c release --show-bin-path)"

# make_app <executable> <display name> <bundle id> <icon variant>
make_app() {
    local exe=$1 name=$2 id=$3 variant=$4
    local app="dist/$exe.app"
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp "$BIN_DIR/$exe" "$app/Contents/MacOS/$exe"

    local iconset
    iconset="$(mktemp -d)/$exe.iconset"
    swift scripts/make_icon.swift "$iconset" "$variant"
    iconutil -c icns "$iconset" -o "$app/Contents/Resources/$exe.icns"

    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$name</string>
    <key>CFBundleDisplayName</key><string>$name</string>
    <key>CFBundleExecutable</key><string>$exe</string>
    <key>CFBundleIdentifier</key><string>$id</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$SHORT</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleIconFile</key><string>$exe</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>TinyTask Recording</string>
            <key>CFBundleTypeExtensions</key><array><string>rec</string></array>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Default</string>
        </dict>
    </array>
</dict>
</plist>
PLIST

    codesign --force --deep --sign - "$app"
    rm -f "dist/$exe-$VERSION-macOS.zip"
    ditto -c -k --keepParent "$app" "dist/$exe-$VERSION-macOS.zip"
    echo "Built $(pwd)/$app"
}

make_app TinyMac "TinyMac" io.github.tinymac classic
make_app TinyMacPlus "TinyMac Plus" io.github.tinymac.plus plus
shasum -a 256 dist/*-$VERSION-macOS.zip

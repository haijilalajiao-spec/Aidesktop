#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="AI 工作台"
BUNDLE="dist/${APP_NAME}.app"

if [[ ! -f AppIcon.icns ]]; then
    echo "▸ 生成应用图标…"
    swift make-icon.swift AppIcon.iconset
    iconutil -c icns AppIcon.iconset -o AppIcon.icns
    rm -r AppIcon.iconset
fi

echo "▸ 编译…"
swift build -c release

echo "▸ 打包 ${BUNDLE}…"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp .build/release/AIWorkbench "$BUNDLE/Contents/MacOS/AIWorkbench"
cp AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>AI 工作台</string>
    <key>CFBundleDisplayName</key>
    <string>AI 工作台</string>
    <key>CFBundleIdentifier</key>
    <string>com.mac004.aiworkbench</string>
    <key>CFBundleExecutable</key>
    <string>AIWorkbench</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSHumanReadableCopyright</key>
    <string>Local build</string>
</dict>
</plist>
PLIST

echo "▸ 签名…"
codesign --force --sign "${WORKBENCH_SIGN_IDENTITY:--}" "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"

echo "✅ 完成：$(pwd)/$BUNDLE"

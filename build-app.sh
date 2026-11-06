#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$HOME/Applications/Invis.app"
CONTENTS="$APP_PATH/Contents"
VERSION="$(<"$PROJECT_DIR/VERSION")"

cd "$PROJECT_DIR"
killall Invis 2>/dev/null || true
killall Инвиз 2>/dev/null || true
sleep 1
swift build -c release
rm -rf "$APP_PATH"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp ".build/release/Invis" "$CONTENTS/MacOS/Invis"
cp VERSION "$CONTENTS/Resources/VERSION"
cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Invis</string>
    <key>CFBundleIdentifier</key><string>ru.macboss.inviz</string>
    <key>CFBundleName</key><string>Invis</string>
    <key>CFBundleDisplayName</key><string>Invis</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
codesign --force --deep --sign - "$APP_PATH"
touch "$APP_PATH"
open "$APP_PATH"
echo "Приложение собрано и запущено: $APP_PATH"

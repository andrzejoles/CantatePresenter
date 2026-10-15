#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "=== Budowanie CantatePresenter (Apple Silicon arm64 Native) ==="
swift build -c release

APP_NAME="CantatePresenter.app"
APP_DIR="$DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "=== Tworzenie pakietu aplikacji $APP_NAME ==="
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp "$DIR/.build/release/CantatePresenter" "$MACOS_DIR/CantatePresenter"
chmod +x "$MACOS_DIR/CantatePresenter"

if [ -f "$DIR/Resources/AppIcon.icns" ]; then
    cp "$DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>pl</string>
    <key>CFBundleExecutable</key>
    <string>CantatePresenter</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.cantate.presenter</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>CantatePresenter</string>
    <key>CFBundleDisplayName</key>
    <string>CantatePresenter — Prezenter Pieśni &amp; Słowa</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Andrzej Oles. Opracowano we współpracy z Claude (Anthropic).</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Aplikacja wymaga dostępu do mikrofonu, aby umożliwić dyktowanie tekstu nowej pieśni oraz wyszukiwanie głosowe.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Rozpoznawanie mowy jest używane do dyktowania tekstów pieśni oraz wyszukiwania utworów głosem.</string>
</dict>
</plist>
EOF

# Klient OAuth Google (W3): plik JSON pobrany z Google Cloud Console, poza repozytorium (.gitignore).
GOOGLE_CLIENT_JSON="${GOOGLE_OAUTH_CLIENT_JSON:-$DIR/google-oauth-client.json}"
if [ -f "$GOOGLE_CLIENT_JSON" ]; then
    CLIENT_ID=$(/usr/bin/plutil -extract installed.client_id raw -o - "$GOOGLE_CLIENT_JSON")
    CLIENT_SECRET=$(/usr/bin/plutil -extract installed.client_secret raw -o - "$GOOGLE_CLIENT_JSON")
    /usr/libexec/PlistBuddy -c "Add :CantateGoogleClientID string $CLIENT_ID" "$CONTENTS_DIR/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :CantateGoogleClientSecret string $CLIENT_SECRET" "$CONTENTS_DIR/Info.plist"
    echo "=== Logowanie Google: klient OAuth wbudowany ==="
else
    echo "=== Logowanie Google: brak $GOOGLE_CLIENT_JSON, przycisk logowania będzie nieaktywny ==="
fi

echo "=== Podpisywanie aplikacji (ad-hoc codesign) ==="
codesign --force --deep -s - "$APP_DIR" || true

echo "=== Gotowe! Aplikacja została pomyślnie utworzona: $APP_DIR ==="

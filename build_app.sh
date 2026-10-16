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

# Tłumaczenia interfejsu (String Catalog, S10): paczka zasobów pakietu obok ikony w Contents/Resources.
BIN_PATH="$(swift build -c release --show-bin-path)"
RESOURCE_BUNDLE="$BIN_PATH/CantatePresenter_CantatePresenterCore.bundle"
if [ ! -d "$RESOURCE_BUNDLE" ]; then
    echo "BŁĄD: brak $RESOURCE_BUNDLE (tłumaczenia interfejsu)" >&2
    exit 1
fi
cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"

# Sparkle (automatyczne aktualizacje): framework w Contents/Frameworks i ścieżka wyszukiwania dla programu.
SPARKLE_FRAMEWORK="$BIN_PATH/Sparkle.framework"
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
    echo "BŁĄD: brak $SPARKLE_FRAMEWORK (swift package resolve)" >&2
    exit 1
fi
mkdir -p "$CONTENTS_DIR/Frameworks"
ditto "$SPARKLE_FRAMEWORK" "$CONTENTS_DIR/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/CantatePresenter"

# Instrukcja obsługi (Pomoc → Otwórz plik INSTRUKCJA.md), S11
cp "$DIR/INSTRUKCJA.md" "$RESOURCES_DIR/INSTRUKCJA.md"

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
    <key>CFBundleLocalizations</key>
    <array>
        <string>pl</string>
        <string>en</string>
        <string>de</string>
        <string>es</string>
        <string>uk</string>
    </array>
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
    <key>SUFeedURL</key>
    <string>https://github.com/andrzejoles/CantatePresenter/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>Y7sGGsyUgjpM7QIHCdupCJPvYJ7mfsiwZ6pLPOTltwI=</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUScheduledCheckInterval</key>
    <integer>86400</integer>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Pilot ze smartfona łączy się z tym Macem w sieci lokalnej, żeby przełączać slajdy.</string>
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

# Wersja z historii gita (scripts/version.sh: PR i commity od ostatniego PR), numer kompilacji = liczba commitów
VERSION="$("$DIR/scripts/version.sh")"
BUILD_NUMBER="$(git -C "$DIR" rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"

# Przykładowe dane dewelopera (N9) nie mogą trafić do aplikacji ani instalatora.
LEAKED="$(find "$APP_DIR" \( -name "*.mufl" -o -name "*.muf" -o -name "songs.json" -o -name "plans.json" -o -name "settings.json" \) -print)"
if [ -n "$LEAKED" ]; then
    echo "BŁĄD: w pakiecie aplikacji są dane dewelopera:" >&2
    echo "$LEAKED" >&2
    exit 1
fi

# Podpis: Developer ID z Hardened Runtime, gdy podano CANTATE_SIGN_IDENTITY (np. "Developer ID Application: Imię
# Nazwisko (TEAMID)"; potrzebne do notaryzacji, docs/RELEASE.md), inaczej ad-hoc jak dotąd.
# Bez `|| true`: nieudany podpis ma przerwać budowanie. Bez odradzanego `--deep`: zagnieżdżone pakiety od środka.
SIGN_IDENTITY="${CANTATE_SIGN_IDENTITY:-}"
if [ -n "$SIGN_IDENTITY" ]; then
    echo "=== Podpisywanie aplikacji: $SIGN_IDENTITY (Hardened Runtime) ==="
    SIGN_ARGS=(--force --options runtime --timestamp --sign "$SIGN_IDENTITY")
    # Podpis ad-hoc ("-") z Hardened Runtime służy do sprawdzenia tej ścieżki bez certyfikatu: bez znacznika czasu.
    if [ "$SIGN_IDENTITY" = "-" ]; then SIGN_ARGS=(--force --options runtime --sign -); fi
    if [ -d "$CONTENTS_DIR/Frameworks" ]; then
        find "$CONTENTS_DIR/Frameworks" -depth \( -name "*.xpc" -o -name "*.app" -o -name "Autoupdate" -o -name "*.framework" \) -print0 |
            while IFS= read -r -d '' nested; do codesign "${SIGN_ARGS[@]}" "$nested"; done
    fi
    codesign "${SIGN_ARGS[@]}" --entitlements "$DIR/Resources/CantatePresenter.entitlements" "$APP_DIR"
else
    echo "=== Podpisywanie aplikacji (ad-hoc codesign) ==="
    if [ -d "$CONTENTS_DIR/Frameworks" ]; then
        find "$CONTENTS_DIR/Frameworks" -depth \( -name "*.xpc" -o -name "*.app" -o -name "Autoupdate" -o -name "*.framework" \) -print0 |
            while IFS= read -r -d '' nested; do codesign --force --sign - "$nested"; done
    fi
    codesign --force --sign - "$APP_DIR"
fi
codesign --verify --strict "$APP_DIR"

echo "=== Gotowe! Aplikacja została pomyślnie utworzona: $APP_DIR ==="

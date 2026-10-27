#!/usr/bin/env bash
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "=== Budowanie CantatePresenter (Apple Silicon arm64 Native) ==="
# Domyślny system budowania SwiftPM (swiftbuild) wpisuje do LC_BUILD_VERSION wersję SDK równą minimalnej (14.0),
# więc AppKit/SwiftUI działałyby w trybie zgodności ze starym SDK (R5-02). Wersję SDK podajemy linkerowi wprost.
MIN_MACOS="14.0"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
swift build -c release -Xlinker -platform_version -Xlinker macos -Xlinker "$MIN_MACOS" -Xlinker "$SDK_VERSION"

APP_NAME="CantatePresenter.app"
APP_DIR="$DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "=== Tworzenie pakietu aplikacji $APP_NAME ==="
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

BIN_PATH="$(swift build -c release --show-bin-path)"
cp "$BIN_PATH/CantatePresenter" "$MACOS_DIR/CantatePresenter"
chmod +x "$MACOS_DIR/CantatePresenter"

# Tłumaczenia interfejsu (String Catalog, S10): paczka zasobów pakietu obok ikony w Contents/Resources.
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

# Ścieżki wyszukiwania bibliotek (R7-01): SwiftPM i sterownik dopisują @loader_path i bezwzględną ścieżkę
# do narzędzi Xcode. Podpis ad-hoc wyłącza kontrolę bibliotek, więc Sparkle podłożony w nieistniejącym
# na zwykłym Macu katalogu Xcode zostałby wczytany przed tym z pakietu. Zostają tylko /usr/lib/swift
# (chroniony przez SIP) i Frameworks w pakiecie.
SWIFT_RUNTIME_RPATH="/usr/lib/swift"
BUNDLE_FRAMEWORKS_RPATH="@executable_path/../Frameworks"
ALLOWED_RPATHS="$(printf '%s\n' "$SWIFT_RUNTIME_RPATH" "$BUNDLE_FRAMEWORKS_RPATH")"
list_rpaths() {
    otool -l "$1" | awk '$1 == "cmd" && $2 == "LC_RPATH" { getline; getline; print $2 }'
}
while IFS= read -r rpath; do
    if [ -n "$rpath" ] && ! grep -qxF -- "$rpath" <<< "$ALLOWED_RPATHS"; then
        install_name_tool -delete_rpath "$rpath" "$MACOS_DIR/CantatePresenter"
    fi
done <<< "$(list_rpaths "$MACOS_DIR/CantatePresenter")"
if ! list_rpaths "$MACOS_DIR/CantatePresenter" | grep -qxF "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/CantatePresenter"
fi

# Instrukcja obsługi (Pomoc → Otwórz plik INSTRUKCJA.md), S11
cp "$DIR/INSTRUKCJA.md" "$RESOURCES_DIR/INSTRUKCJA.md"
# Licencja MIT w pakiecie aplikacji
cp "$DIR/LICENSE" "$RESOURCES_DIR/LICENSE"

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
    <string>© 2026 Andrzej Oles</string>
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
    <key>SURequireSignedFeed</key>
    <true/>
    <key>SUVerifyUpdateBeforeExtraction</key>
    <true/>
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

# Opisy uprawnień i nazwa w języku systemu (R5-04); domyślny polski jest też w Info.plist.
write_infoplist_strings() {
    mkdir -p "$RESOURCES_DIR/$1.lproj"
    cat > "$RESOURCES_DIR/$1.lproj/InfoPlist.strings"
}
write_infoplist_strings pl << 'STRINGS'
"CFBundleDisplayName" = "CantatePresenter — Prezenter Pieśni & Słowa";
"NSMicrophoneUsageDescription" = "Aplikacja wymaga dostępu do mikrofonu, aby umożliwić dyktowanie tekstu nowej pieśni oraz wyszukiwanie głosowe.";
"NSSpeechRecognitionUsageDescription" = "Rozpoznawanie mowy jest używane do dyktowania tekstów pieśni oraz wyszukiwania utworów głosem.";
"NSLocalNetworkUsageDescription" = "Pilot ze smartfona łączy się z tym Macem w sieci lokalnej, żeby przełączać slajdy.";
STRINGS
write_infoplist_strings en << 'STRINGS'
"CFBundleDisplayName" = "CantatePresenter — Songs & Word Presenter";
"NSMicrophoneUsageDescription" = "The app needs access to the microphone so you can dictate the lyrics of a new song and search by voice.";
"NSSpeechRecognitionUsageDescription" = "Speech recognition is used to dictate song lyrics and to search for songs by voice.";
"NSLocalNetworkUsageDescription" = "The smartphone remote connects to this Mac over the local network to switch slides.";
STRINGS
write_infoplist_strings de << 'STRINGS'
"CFBundleDisplayName" = "CantatePresenter — Präsentation von Liedern & Wort";
"NSMicrophoneUsageDescription" = "Die App benötigt Zugriff auf das Mikrofon, damit du den Text eines neuen Liedes diktieren und per Sprache suchen kannst.";
"NSSpeechRecognitionUsageDescription" = "Die Spracherkennung wird verwendet, um Liedtexte zu diktieren und Lieder per Sprache zu suchen.";
"NSLocalNetworkUsageDescription" = "Die Smartphone-Fernbedienung verbindet sich über das lokale Netzwerk mit diesem Mac, um Folien umzuschalten.";
STRINGS
write_infoplist_strings es << 'STRINGS'
"CFBundleDisplayName" = "CantatePresenter — Presentador de Canciones y Palabra";
"NSMicrophoneUsageDescription" = "La aplicación necesita acceso al micrófono para que puedas dictar la letra de una canción nueva y buscar por voz.";
"NSSpeechRecognitionUsageDescription" = "El reconocimiento de voz se usa para dictar letras de canciones y buscar canciones por voz.";
"NSLocalNetworkUsageDescription" = "El control remoto desde el móvil se conecta a este Mac por la red local para cambiar las diapositivas.";
STRINGS
write_infoplist_strings uk << 'STRINGS'
"CFBundleDisplayName" = "CantatePresenter — Презентер пісень і Слова";
"NSMicrophoneUsageDescription" = "Програмі потрібен доступ до мікрофона, щоб ви могли диктувати текст нової пісні та шукати голосом.";
"NSSpeechRecognitionUsageDescription" = "Розпізнавання мовлення використовується для диктування текстів пісень і пошуку пісень голосом.";
"NSLocalNetworkUsageDescription" = "Пульт на смартфоні підключається до цього Mac у локальній мережі, щоб перемикати слайди.";
STRINGS
for strings in "$RESOURCES_DIR"/*.lproj/InfoPlist.strings; do
    /usr/bin/plutil -lint -s "$strings" || { echo "BŁĄD: niepoprawny $strings" >&2; exit 1; }
done

# Identyfikator paczki zasobów SwiftPM bierze się z nazwy katalogu repozytorium (R5-08); ustalamy go.
RESOURCE_PLIST="$RESOURCES_DIR/CantatePresenter_CantatePresenterCore.bundle/Contents/Info.plist"
if [ -f "$RESOURCE_PLIST" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.cantate.presenter.core-resources" "$RESOURCE_PLIST"
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

# Podpis zawsze z Hardened Runtime (R3-01): bez niego dyld przyjmuje DYLD_INSERT_LIBRARIES, a wstrzyknięty kod
# dostaje tokeny Google z Pęku kluczy i zgodę na mikrofon. Domyślnie ad-hoc ("-", decyzja właściciela: bez konta
# Apple Developer), z CANTATE_SIGN_IDENTITY="Developer ID Application: Imię Nazwisko (TEAMID)" do notaryzacji
# (docs/RELEASE.md). Uprawnienia: Resources/CantatePresenter.entitlements (mikrofon).
# Bez `|| true`: nieudany podpis ma przerwać budowanie. Bez odradzanego `--deep`: zagnieżdżone pakiety od środka.
SIGN_IDENTITY="${CANTATE_SIGN_IDENTITY:--}"
ENTITLEMENTS="$DIR/Resources/CantatePresenter.entitlements"
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "=== Podpisywanie aplikacji (ad-hoc, Hardened Runtime) ==="
    SIGN_ARGS=(--force --options runtime --sign -)
    # Podpis ad-hoc nie ma identyfikatora zespołu, więc kontrola bibliotek Hardened Runtime odrzuciłaby
    # Sparkle.framework z pakietu (dyld: Library not loaded). Tylko to uprawnienie, bez
    # allow-dyld-environment-variables: zmienne DYLD_* nadal są ignorowane.
    ENTITLEMENTS="$(mktemp -t cantate-entitlements)"
    trap 'rm -f "$ENTITLEMENTS"' EXIT
    cp "$DIR/Resources/CantatePresenter.entitlements" "$ENTITLEMENTS"
    /usr/libexec/PlistBuddy -c "Add :com.apple.security.cs.disable-library-validation bool true" "$ENTITLEMENTS"
else
    echo "=== Podpisywanie aplikacji: $SIGN_IDENTITY (Hardened Runtime) ==="
    SIGN_ARGS=(--force --options runtime --timestamp --sign "$SIGN_IDENTITY")
fi
if [ -d "$CONTENTS_DIR/Frameworks" ]; then
    find "$CONTENTS_DIR/Frameworks" -depth ! -type l \( -name "*.xpc" -o -name "*.app" -o -name "Autoupdate" -o -name "*.framework" \) -print0 |
        while IFS= read -r -d '' nested; do codesign "${SIGN_ARGS[@]}" "$nested"; done
fi
codesign "${SIGN_ARGS[@]}" --entitlements "$ENTITLEMENTS" "$APP_DIR"
codesign --verify --strict "$APP_DIR"
SIGNATURE_INFO="$(codesign -dv "$APP_DIR" 2>&1)"
[[ "$SIGNATURE_INFO" =~ flags=[^[:space:]]*runtime ]] || { echo "BŁĄD: podpis bez Hardened Runtime" >&2; exit 1; }

# Kontrole gotowego programu: tylko dozwolone ścieżki bibliotek (R7-01) i prawdziwa wersja SDK (R5-02).
FINAL_RPATHS="$(list_rpaths "$MACOS_DIR/CantatePresenter" | sort)"
if [ "$FINAL_RPATHS" != "$(sort <<< "$ALLOWED_RPATHS")" ]; then
    echo "BŁĄD: niedozwolone LC_RPATH w programie:" >&2
    echo "$FINAL_RPATHS" >&2
    exit 1
fi
BUILD_VERSION="$(otool -l "$MACOS_DIR/CantatePresenter" | awk '$1 == "cmd" && $2 == "LC_BUILD_VERSION" { found = 1 } found && $1 == "minos" { minos = $2 } found && $1 == "sdk" { print minos, $2; exit }')"
if [ "$BUILD_VERSION" != "$MIN_MACOS $SDK_VERSION" ]; then
    echo "BŁĄD: LC_BUILD_VERSION (minos sdk) = '$BUILD_VERSION', oczekiwano '$MIN_MACOS $SDK_VERSION'" >&2
    exit 1
fi

echo "=== Gotowe! Aplikacja została pomyślnie utworzona: $APP_DIR ==="

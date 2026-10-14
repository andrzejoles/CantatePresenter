#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

VERSION="1.0.0"
APP_NAME="CantatePresenter.app"
DIST_DIR="$DIR/dist"

echo "=========================================================="
echo "   CANTATEPRESENTER — KREATOR INSTALATORA MACOS (ARM64)   "
echo "=========================================================="

# 1. Zbuduj aplikację
echo ""
echo "[1/4] Budowanie aplikacji CantatePresenter..."
./build_app.sh

mkdir -p "$DIST_DIR"

# 2. Tworzenie instalatora PKG (Apple Package Installer)
echo ""
echo "[2/4] Generowanie instalatora Apple PKG (kreator instalacji do /Applications)..."
PKG_OUTPUT="$DIST_DIR/CantatePresenter-$VERSION.pkg"
pkgbuild --component "$DIR/$APP_NAME" \
         --install-location /Applications \
         --identifier com.cantate.presenter \
         --version "$VERSION" \
         "$PKG_OUTPUT"
cp "$PKG_OUTPUT" "$DIST_DIR/CantatePresenter-Installer.pkg"
echo "  -> Utworzono: $PKG_OUTPUT"

# 3. Tworzenie instalatora DMG (Apple Disk Image - Drag & Drop)
echo ""
echo "[3/4] Przygotowywanie obrazu dysku DMG..."
DMG_OUTPUT="$DIST_DIR/CantatePresenter-$VERSION.dmg"
STAGING_DIR="/tmp/cantate_dmg_staging_$$"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# Kopiowanie aplikacji
cp -R "$DIR/$APP_NAME" "$STAGING_DIR/"

# Skrót do folderu Programy
ln -s /Applications "$STAGING_DIR/Przeciągnij do Programy (Applications)"

# Instrukcja instalacji wewnątrz DMG
cat << 'EOF' > "$STAGING_DIR/INSTRUKCJA_INSTALACJI.txt"
======================================================
  CantatePresenter — Prezenter Pieśni i Słowa (macOS)
======================================================

SZYBKA INSTALACJA:
1. Przeciągnij ikonę "CantatePresenter" do folderu "Przeciągnij do Programy (Applications)".
2. Program zostanie skopiowany do folderu /Applications na Twoim Macu.
3. Uruchom program z Launchpada, folderu Programy lub przez Spotlight (Cmd + Spacja).

ALTERNATYWNIE:
Możesz po prostu dwukrotnie kliknąć CantatePresenter bezpośrednio w tym oknie
— aplikacja sama zapyta, czy chcesz przenieść ją automatycznie do folderu Programy!
======================================================
EOF

# Ikona woluminu DMG
if [ -f "$DIR/Resources/AppIcon.icns" ]; then
    cp "$DIR/Resources/AppIcon.icns" "$STAGING_DIR/.VolumeIcon.icns"
    if command -v SetFile &> /dev/null; then
        SetFile -a C "$STAGING_DIR" || true
    fi
fi

# Generowanie skompresowanego DMG (UDZO)
hdiutil create -volname "CantatePresenter" \
               -srcfolder "$STAGING_DIR" \
               -ov \
               -format UDZO \
               "$DMG_OUTPUT"

rm -rf "$STAGING_DIR"
cp "$DMG_OUTPUT" "$DIST_DIR/CantatePresenter.dmg"
echo "  -> Utworzono: $DMG_OUTPUT"

# 4. Podsumowanie i sumy kontrolne
echo ""
echo "[4/4] Weryfikacja instalatorów..."
echo "=========================================================="
echo "Gotowe! Wygenerowane pakiety instalacyjne w folderze dist/:"
echo ""
ls -lh "$DIST_DIR"
echo "=========================================================="
echo "Sumy kontrolne SHA256:"
shasum -a 256 "$DMG_OUTPUT" "$PKG_OUTPUT"
echo "=========================================================="
echo "Instalatory są gotowe do dystrybucji i instalacji!"

#!/usr/bin/env bash
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

VERSION="$("$DIR/scripts/version.sh")"
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
# Podpis instalatora: CANTATE_INSTALLER_IDENTITY="Developer ID Installer: … (TEAMID)" (docs/RELEASE.md).
PKG_SIGN=()
if [ -n "${CANTATE_INSTALLER_IDENTITY:-}" ]; then PKG_SIGN=(--sign "$CANTATE_INSTALLER_IDENTITY" --timestamp); fi
# Katalogi tymczasowe z mktemp (R3-14), sprzątane także po błędzie.
PKG_ROOT="$(mktemp -d)"
STAGING_DIR="$(mktemp -d)"
COMPONENT_PLIST="$PKG_ROOT.plist"
trap 'rm -rf "$PKG_ROOT" "$COMPONENT_PLIST" "$STAGING_DIR"' EXIT
# mktemp tworzy katalogi 700; korzeń pakietu i obrazu dysku ma mieć zwykłe uprawnienia.
chmod 755 "$PKG_ROOT" "$STAGING_DIR"
# Pakiet nieprzenoszalny (R3-11): Instalator zawsze kładzie aplikację w /Applications, zamiast „uaktualniać”
# kopię z tym samym identyfikatorem znalezioną gdzie indziej (np. w Pobranych).
ditto "$DIR/$APP_NAME" "$PKG_ROOT/$APP_NAME"
pkgbuild --analyze --root "$PKG_ROOT" "$COMPONENT_PLIST" >/dev/null
/usr/bin/plutil -replace 0.BundleIsRelocatable -bool NO "$COMPONENT_PLIST"
pkgbuild --root "$PKG_ROOT" \
         --component-plist "$COMPONENT_PLIST" \
         --install-location /Applications \
         --identifier com.cantate.presenter \
         --version "$VERSION" \
         ${PKG_SIGN[@]+"${PKG_SIGN[@]}"} \
         "$PKG_OUTPUT"
echo "  -> Utworzono: $PKG_OUTPUT"

# 3. Tworzenie instalatora DMG (Apple Disk Image - Drag & Drop)
echo ""
echo "[3/4] Przygotowywanie obrazu dysku DMG..."
DMG_OUTPUT="$DIST_DIR/CantatePresenter-$VERSION.dmg"
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

if [ -n "${CANTATE_SIGN_IDENTITY:-}" ] && [ "$CANTATE_SIGN_IDENTITY" != "-" ]; then
    codesign --force --timestamp --sign "$CANTATE_SIGN_IDENTITY" "$DMG_OUTPUT"
fi
# Notaryzacja, gdy jest profil notarytool (bez niej Gatekeeper ostrzega przy pierwszym uruchomieniu).
if [ -n "${CANTATE_NOTARY_PROFILE:-}" ]; then
    "$DIR/scripts/notarize.sh" "$DMG_OUTPUT" "$PKG_OUTPUT"
fi
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

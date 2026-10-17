#!/usr/bin/env bash
# Wydanie: instalatory, archiwum dla Sparkle, appcast.xml podpisany kluczem EdDSA i SZKIC wydania na GitHubie.
# Publikacja po sprawdzeniu szkicu: gh release edit vX.Y.Z --draft=false (docs/RELEASE.md).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || { echo "Wydanie tylko z gałęzi main" >&2; exit 1; }
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "Najpierw zatwierdź zmiany" >&2; exit 1; }

VERSION="$(scripts/version.sh)"
TAG="v$VERSION"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "Wydanie $TAG już istnieje" >&2
    exit 1
fi

RELEASE_DIR="$ROOT/dist/release-$VERSION"
# Pliki innych wersji osobno: generate_appcast czyta wszystkie archiwa z $RELEASE_DIR.
OTHER_DIR="$RELEASE_DIR/other"
rm -rf "$RELEASE_DIR"
mkdir -p "$OTHER_DIR"

# Windows: instalator i ZIP z CI dla tego samego commita (zadanie „windows” w .github/workflows/ci.yml).
SHA="$(git rev-parse HEAD)"
git fetch -q origin main
[ "$(git rev-parse origin/main)" = "$SHA" ] || { echo "Najpierw zsynchronizuj main z GitHubem (git pull / git push)" >&2; exit 1; }
RUN_ID="$(gh run list --workflow ci.yml --commit "$SHA" --event push --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
[ -n "$RUN_ID" ] || { echo "Brak przebiegu CI dla $SHA na GitHubie" >&2; exit 1; }
echo "Czekam na CI ($RUN_ID)..."
gh run watch "$RUN_ID" --exit-status >/dev/null || { echo "CI dla $SHA nie przeszło" >&2; exit 1; }
gh run download "$RUN_ID" -n CantatePresenter-Windows-x64 -D "$OTHER_DIR"
WINDOWS_ZIP="$OTHER_DIR/CantatePresenter-Windows-x64-$VERSION.zip"
[ -f "$WINDOWS_ZIP" ] || { echo "Brak $WINDOWS_ZIP w artefaktach CI" >&2; exit 1; }
gh run download "$RUN_ID" -n CantatePresenter-Windows-x64-Setup -D "$OTHER_DIR"
WINDOWS_SETUP="$OTHER_DIR/CantatePresenter-Windows-x64-Setup-$VERSION.exe"
[ -f "$WINDOWS_SETUP" ] || { echo "Brak $WINDOWS_SETUP w artefaktach CI" >&2; exit 1; }

# Web: katalog web/ z tego commita i plik VERSION (serwer bez gita czyta wersję z niego, web/README.md).
WEB_TMP="$(mktemp -d)"
trap 'rm -rf "$WEB_TMP"' EXIT
git archive HEAD web | tar -x -C "$WEB_TMP"
echo "$VERSION" > "$WEB_TMP/web/VERSION"
WEB_ZIP="$OTHER_DIR/CantatePresenter-Web-$VERSION.zip"
(cd "$WEB_TMP" && zip -qr -X "$WEB_ZIP" web)

./build_installer.sh
ditto -c -k --sequesterRsrc --keepParent CantatePresenter.app "$RELEASE_DIR/CantatePresenter-$VERSION.zip"

# appcast.xml z tym wydaniem; aplikacja czyta go z releases/latest/download/appcast.xml.
scripts/sparkle_tools.sh generate_appcast \
    --download-url-prefix "https://github.com/andrzejoles/CantatePresenter/releases/download/$TAG/" \
    --link "https://github.com/andrzejoles/CantatePresenter/releases/tag/$TAG" \
    "$RELEASE_DIR"

PREVIOUS="$(git describe --tags --abbrev=0 2>/dev/null || true)"
{
    echo "CantatePresenter $VERSION"
    echo
    # Zmiany wchodzą na main przez scalenia PR: tytuł PR jest w treści commita scalającego.
    git log --first-parent --format='%s%n%b' ${PREVIOUS:+"$PREVIOUS..HEAD"} \
        | awk '/^Merge pull request #[0-9]+ from /{n=$4; next} n!="" && NF{print "- " $0 " (" n ")"; n=""}' | head -40 || true
    cat <<NOTES

## macOS (14+, Apple Silicon)
Pobierz \`CantatePresenter-$VERSION.dmg\` i przeciągnij aplikację do Aplikacji. Przy pierwszym uruchomieniu: Ustawienia systemowe → Prywatność i ochrona → „Otwórz mimo to”. Zainstalowane kopie zaktualizują się same.

## Windows 10/11 (x64)
Uruchom \`CantatePresenter-Windows-x64-Setup-$VERSION.exe\` (instalacja dla bieżącego użytkownika, bez uprawnień administratora; skrót w menu Start). Aplikacja nie jest podpisana, więc SmartScreen pokaże ostrzeżenie: „Więcej informacji” → „Uruchom mimo to”. Nowa wersja instaluje się tym samym instalatorem na miejscu starej. Bez instalacji: rozpakuj \`CantatePresenter-Windows-x64-$VERSION.zip\` i uruchom \`CantatePresenter.exe\`. Dane w \`%APPDATA%\\CantatePresenter\` (zostają po odinstalowaniu), ten sam format i kopie zapasowe co macOS.

## Web (serwer prywatny)
\`CantatePresenter-Web-$VERSION.zip\` zawiera katalog \`web/\` z plikiem \`VERSION\`. Instalacja i konta: \`web/README.md\`. Aktualizacja: podmień katalog \`web/\`, dane serwera zostają.

Pliki \`CantatePresenter-$VERSION.zip\` i \`appcast.xml\` służą automatycznym aktualizacjom macOS.
NOTES
} > "$RELEASE_DIR/notes.md"

git tag "$TAG"
git push origin "$TAG"
gh release create "$TAG" --draft --title "CantatePresenter $VERSION" --notes-file "$RELEASE_DIR/notes.md" \
    "$RELEASE_DIR/CantatePresenter-$VERSION.zip" "$RELEASE_DIR/appcast.xml" \
    "dist/CantatePresenter-$VERSION.dmg" "dist/CantatePresenter-$VERSION.pkg" \
    "$WINDOWS_SETUP" "$WINDOWS_ZIP" "$WEB_ZIP"
echo "Szkic wydania $TAG gotowy. Sprawdź go na GitHubie i opublikuj: gh release edit $TAG --draft=false"

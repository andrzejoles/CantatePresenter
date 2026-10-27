#!/usr/bin/env bash
# Wydanie: instalatory, archiwum dla Sparkle, appcast.xml podpisany kluczem EdDSA i SZKIC wydania na GitHubie.
# Publikacja po sprawdzeniu szkicu: gh release edit vX.Y.Z --draft=false (docs/RELEASE.md).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || { echo "Wydanie tylko z gałęzi main" >&2; exit 1; }
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "Najpierw zatwierdź zmiany" >&2; exit 1; }
# Nieśledzone pliki w źródłach i skryptach weszłyby do wydania, choć CI ich nie sprawdzało (R3-10).
# Pliki z .gitignore (np. google-oauth-client.json) nie są tu wypisywane.
UNTRACKED="$(git status --porcelain --untracked-files=all -- Sources Tests Package.swift Package.resolved Resources \
    build_app.sh build_installer.sh scripts INSTRUKCJA.md LICENSE)"
[ -z "$UNTRACKED" ] || { printf 'Nieśledzone pliki, które trafiłyby do wydania:\n%s\n' "$UNTRACKED" >&2; exit 1; }

VERSION="$(scripts/version.sh)"
TAG="v$VERSION"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "Wydanie $TAG już istnieje" >&2
    exit 1
fi

RELEASE_DIR="$ROOT/dist/release-$VERSION"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# Wydanie tylko z commita, który jest na GitHubie i przeszedł CI.
SHA="$(git rev-parse HEAD)"
git fetch -q origin main
[ "$(git rev-parse origin/main)" = "$SHA" ] || { echo "Najpierw zsynchronizuj main z GitHubem (git pull / git push)" >&2; exit 1; }
RUN_ID="$(gh run list --workflow ci.yml --commit "$SHA" --event push --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
[ -n "$RUN_ID" ] || { echo "Brak przebiegu CI dla $SHA na GitHubie" >&2; exit 1; }
echo "Czekam na CI ($RUN_ID)..."
gh run watch "$RUN_ID" --exit-status >/dev/null || { echo "CI dla $SHA nie przeszło" >&2; exit 1; }

./build_installer.sh
ditto -c -k --sequesterRsrc --keepParent CantatePresenter.app "$RELEASE_DIR/CantatePresenter-$VERSION.zip"

# Lista zmian: tytuły scalonych PR od poprzedniego wydania (pierwszy niepusty wiersz opisu commita scalającego,
# a bez opisu temat ostatniego commita gałęzi PR), najwyżej 40.
PREVIOUS="$(git describe --tags --abbrev=0 2>/dev/null || true)"
changelog() {
    local count=0 sha number title
    for sha in $(git log --first-parent --merges --grep='^Merge pull request #' --format=%H ${PREVIOUS:+"$PREVIOUS..HEAD"}); do
        [ "$count" -lt 40 ] || break
        number="$(git log -1 --format=%s "$sha" | awk '{print $4}')"
        title="$(git log -1 --format=%b "$sha" | awk 'NF{print; exit}')"
        [ -n "$title" ] || title="$(git log -1 --format=%s "$sha^2")"
        echo "- $title ($number)"
        count=$((count + 1))
    done
}
CHANGES="$(changelog)"

# Opis zmian w oknie aktualizacji Sparkle (R1-03): plik o nazwie archiwum, wbudowany w appcast.xml.
{
    echo "## CantatePresenter $VERSION"
    echo
    echo "$CHANGES"
} > "$RELEASE_DIR/CantatePresenter-$VERSION.md"

# appcast.xml z tym wydaniem; aplikacja czyta go z releases/latest/download/appcast.xml.
# Aplikacja wymaga podpisanego kanału (SURequireSignedFeed, R3-09), więc generate_appcast podpisuje też appcast.xml.
scripts/sparkle_tools.sh generate_appcast \
    --download-url-prefix "https://github.com/andrzejoles/CantatePresenter/releases/download/$TAG/" \
    --link "https://github.com/andrzejoles/CantatePresenter/releases/tag/$TAG" \
    --embed-release-notes \
    "$RELEASE_DIR"

{
    echo "CantatePresenter $VERSION"
    echo
    echo "$CHANGES"
    cat <<NOTES

## macOS (14+, Apple Silicon)
Pobierz \`CantatePresenter-$VERSION.dmg\` i przeciągnij aplikację do Aplikacji. Przy pierwszym uruchomieniu: Ustawienia systemowe → Prywatność i ochrona → „Otwórz mimo to”. Zainstalowane kopie zaktualizują się same.

Pliki \`CantatePresenter-$VERSION.zip\` i \`appcast.xml\` służą automatycznym aktualizacjom macOS.

## Bezpieczeństwo
Poprawki bezpieczeństwa trafiają tylko do najnowszego wydania. Podatności zgłaszaj prywatnie: Security → Report a vulnerability (https://github.com/andrzejoles/CantatePresenter/security/advisories/new). Zasady: \`SECURITY.md\`.

## Licencja
Licencja MIT, plik \`LICENSE\` w repozytorium i w wydaniu. Biblioteka Sparkle (aktualizacje) ma własną licencję: \`LICENSE-Sparkle.txt\` w wydaniu i w aplikacji. Teksty pieśni nie są objęte licencją programu.
NOTES
} > "$RELEASE_DIR/notes.md"

# Licencja Sparkle z gotowej aplikacji (build_app.sh przerywa budowanie bez niej, R9-02). Kopiowana po
# generate_appcast, żeby narzędzie widziało w katalogu tylko archiwum i opis zmian.
SPARKLE_LICENSE="$ROOT/CantatePresenter.app/Contents/Resources/LICENSE-Sparkle.txt"
[ -f "$SPARKLE_LICENSE" ] || { echo "Brak $SPARKLE_LICENSE (licencja Sparkle)" >&2; exit 1; }
cp "$SPARKLE_LICENSE" "$RELEASE_DIR/LICENSE-Sparkle.txt"

git tag "$TAG"
git push origin "$TAG"
# Nieudane utworzenie wydania nie może zostawić znacznika, bo ponowne uruchomienie zatrzymałoby się na nim (R1-08).
if ! gh release create "$TAG" --draft --title "CantatePresenter $VERSION" --notes-file "$RELEASE_DIR/notes.md" \
    "$RELEASE_DIR/CantatePresenter-$VERSION.zip" "$RELEASE_DIR/appcast.xml" "$ROOT/LICENSE" "$RELEASE_DIR/LICENSE-Sparkle.txt" \
    "dist/CantatePresenter-$VERSION.dmg" "dist/CantatePresenter-$VERSION.pkg"; then
    echo "Nie udało się utworzyć wydania $TAG; usuwam znacznik" >&2
    git push --delete origin "$TAG" || echo "Usuń znacznik na GitHubie ręcznie: git push --delete origin $TAG" >&2
    git tag -d "$TAG"
    exit 1
fi
echo "Szkic wydania $TAG gotowy. Sprawdź go na GitHubie i opublikuj: gh release edit $TAG --draft=false"

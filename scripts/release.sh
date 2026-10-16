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

./build_installer.sh
RELEASE_DIR="$ROOT/dist/release-$VERSION"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
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
    git log --first-parent --format='- %s' ${PREVIOUS:+"$PREVIOUS..HEAD"} | grep -v '^- Merge' | head -40 || true
} > "$RELEASE_DIR/notes.md"

git tag "$TAG"
git push origin "$TAG"
gh release create "$TAG" --draft --title "CantatePresenter $VERSION" --notes-file "$RELEASE_DIR/notes.md" \
    "$RELEASE_DIR/CantatePresenter-$VERSION.zip" "$RELEASE_DIR/appcast.xml" \
    "dist/CantatePresenter-$VERSION.dmg" "dist/CantatePresenter-$VERSION.pkg"
echo "Szkic wydania $TAG gotowy. Sprawdź go na GitHubie i opublikuj: gh release edit $TAG --draft=false"

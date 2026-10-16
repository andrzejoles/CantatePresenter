#!/usr/bin/env bash
# Notaryzacja w Apple i przypięcie biletu (staple) do pliku .dmg, .pkg albo .zip / .app.
# Wymaga konta Apple Developer i profilu zapisanego raz poleceniem (docs/RELEASE.md):
#   xcrun notarytool store-credentials cantate-notary --apple-id ADRES --team-id TEAMID --password HASŁO_APLIKACJI
# Użycie: CANTATE_NOTARY_PROFILE=cantate-notary scripts/notarize.sh dist/CantatePresenter-1.9.0.dmg
set -euo pipefail
PROFILE="${CANTATE_NOTARY_PROFILE:?Ustaw CANTATE_NOTARY_PROFILE (nazwa profilu z notarytool store-credentials)}"
for FILE in "$@"; do
    echo "=== Notaryzacja: $FILE ==="
    if [ -d "$FILE" ]; then
        # Aplikację wysyła się jako ZIP, a bilet przypina do samej aplikacji.
        ZIP="$(mktemp -d)/$(basename "$FILE").zip"
        ditto -c -k --keepParent "$FILE" "$ZIP"
        xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
    else
        xcrun notarytool submit "$FILE" --keychain-profile "$PROFILE" --wait
    fi
    xcrun stapler staple "$FILE"
    xcrun stapler validate "$FILE"
done

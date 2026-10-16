#!/usr/bin/env bash
# Kopiuje katalog tłumaczeń z aplikacji macOS do wersji webowej (ten sam plik, te same klucze).
# Test WebTranslationsSyncTests sprawdza, że kopia jest aktualna.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cp "$ROOT/Sources/CantatePresenterCore/Resources/Localizable.xcstrings" "$ROOT/web/i18n/Localizable.xcstrings"
echo "Zsynchronizowano web/i18n/Localizable.xcstrings"

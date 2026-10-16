#!/usr/bin/env bash
# Numer wersji z liczby commitów (decyzja właściciela 2026-10-16), format GŁÓWNY.ŚRODKOWY.OSTATNI:
# co 10 commitów +1 w ostatnim członie (0–9), co 100 commitów +1 w środkowym (0–99),
# co 10 000 commitów +1 w głównym (od 1). Przykłady: 91 → 1.0.9, 100 → 1.1.0, 10 000 → 2.0.0.
# Ta sama reguła jest w web/server/appversion.py (test pilnuje zgodności).
# Bez gita (np. kopia samego katalogu web/ na serwerze) używany jest zapisany plik VERSION.
#
# Użycie: scripts/version.sh            wypisuje wersję
#         scripts/version.sh --write    zapisuje ją też do pliku VERSION w katalogu głównym
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if COUNT="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null)"; then
    BUMPS=$((COUNT / 10))
    VERSION="$((1 + BUMPS / 1000)).$(((BUMPS / 10) % 100)).$((BUMPS % 10))"
elif [ -f "$ROOT/VERSION" ]; then
    VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
elif [ -f "$ROOT/web/VERSION" ]; then
    VERSION="$(tr -d '[:space:]' < "$ROOT/web/VERSION")"
else
    VERSION="dev"
fi

if [ "${1:-}" = "--write" ]; then
    echo "$VERSION" > "$ROOT/VERSION"
fi
echo "$VERSION"

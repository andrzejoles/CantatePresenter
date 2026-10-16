#!/usr/bin/env bash
# Numer wersji z historii gita (decyzja właściciela 2026-10-16), format GŁÓWNY.ŚRODKOWY.OSTATNI:
# - OSTATNI: liczba commitów od ostatniego scalonego PR (0 zaraz po scaleniu),
# - ŚRODKOWY: liczba scalonych PR, jedna cyfra 0–9,
# - GŁÓWNY: od 1, rośnie, gdy środkowy przeskakuje z 9 na 0 (co 10 PR).
# Scalony PR = commit „Merge pull request #…” w historii pierwszego rodzica (tak scala GitHub).
# Przykłady: 8 PR i 0 commitów → 1.8.0; 8 PR i 3 commity → 1.8.3; 10 PR → 2.0.0.
# Ta sama reguła jest w web/server/appversion.py (test pilnuje zgodności).
# Bez gita (np. kopia samego katalogu web/ na serwerze) używany jest zapisany plik VERSION.
#
# Użycie: scripts/version.sh            wypisuje wersję
#         scripts/version.sh --write    zapisuje ją też do pliku VERSION w katalogu głównym
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if git -C "$ROOT" rev-parse --verify -q HEAD >/dev/null 2>&1; then
    MERGES="$(git -C "$ROOT" log --first-parent --merges --grep='^Merge pull request #' --format=%H HEAD)"
    PRS="$(printf '%s' "$MERGES" | grep -c . || true)"
    # Pierwsza linia bez potoku do head (przy pipefail head potrafi przerwać printf sygnałem SIGPIPE).
    LAST="${MERGES%%$'\n'*}"
    if [ -n "$LAST" ]; then
        COMMITS="$(git -C "$ROOT" rev-list --count --first-parent "$LAST..HEAD")"
    else
        COMMITS="$(git -C "$ROOT" rev-list --count --first-parent HEAD)"
    fi
    VERSION="$((1 + PRS / 10)).$((PRS % 10)).$COMMITS"
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

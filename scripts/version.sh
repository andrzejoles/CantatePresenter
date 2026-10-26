#!/usr/bin/env bash
# Numer wersji z historii gita (decyzja właściciela 2026-10-16), format GŁÓWNY.ŚRODKOWY.OSTATNI:
# - OSTATNI: liczba commitów od ostatniego scalonego PR (0 zaraz po scaleniu),
# - ŚRODKOWY: liczba scalonych PR, jedna cyfra 0–9,
# - GŁÓWNY: od 1, rośnie, gdy środkowy przeskakuje z 9 na 0 (co 10 PR).
# Scalony PR = commit „Merge pull request #…” w historii pierwszego rodzica (tak scala GitHub).
# Przykłady: 8 PR i 0 commitów → 1.8.0; 8 PR i 3 commity → 1.8.3; 10 PR → 2.0.0.
# Bez gita (np. kopia źródeł z archiwum GitHuba) wersja to „dev”.
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
else
    VERSION="dev"
fi
echo "$VERSION"

#!/usr/bin/env bash
# Przepisanie historii gita (decyzja właściciela 2026-10-16): usunięcie prywatnego eksportu Holyrics
# 2026-10-14_16-19-00.mufl i adresu e-mail ze wszystkich dawnych wersji plików, na wszystkich gałęziach i tagach.
#
# Skrypt pracuje na świeżym klonie z GitHuba w dist/rewrite-<data>/, a nie w tym katalogu:
#   scripts/rewrite_history.sh          próba: przepisuje klon i sprawdza wynik, niczego nie wysyła
#   scripts/rewrite_history.sh --push   to samo, potem force-push wszystkich gałęzi i tagów (gdy nie ma otwartych PR)
#
# Przed wysłaniem tworzy pełną kopię dist/history-backup-<data>.bundle (odtworzenie: git clone PLIK.bundle).
# Po wysłaniu ten katalog roboczy trzeba zsynchronizować (polecenia na końcu) albo sklonować repozytorium od nowa.
# Plik .mufl zostaje na dysku (nieśledzony, w .gitignore), więc testy na prawdziwym eksporcie nadal działają lokalnie.
# GitHub przechowuje stare commity także w odnośnikach PR (refs/pull/*); żeby zniknęły i stamtąd,
# trzeba poprosić GitHub Support o usunięcie danych z pamięci podręcznej repozytorium.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE="${REWRITE_REMOTE:-$(git -C "$ROOT" remote get-url origin)}"
MUFL="2026-10-14_16-19-00.mufl"
# Usuwany adres: z parametru REWRITE_EMAIL albo z `git config user.email` (nie jest zapisany w repozytorium).
EMAIL="${REWRITE_EMAIL:-$(git -C "$ROOT" config user.email)}"
[ -n "$EMAIL" ] || { echo "Podaj adres: REWRITE_EMAIL=adres scripts/rewrite_history.sh" >&2; exit 1; }
PUSH="${1:-}"
STAMP="$(date +%Y-%m-%d_%H-%M-%S)"
WORK="$ROOT/dist/rewrite-$STAMP"

if [ "$PUSH" = "--push" ] && [ -z "${REWRITE_REMOTE:-}" ]; then
    OPEN="$(gh pr list --state open --json number --jq length)"
    [ "$OPEN" = "0" ] || { echo "Są otwarte PR ($OPEN). Scal je albo zamknij przed przepisaniem historii." >&2; exit 1; }
fi

mkdir -p "$ROOT/dist"
git clone -q "$REMOTE" "$WORK"
cd "$WORK"
git bundle create "$ROOT/dist/history-backup-$STAMP.bundle" --all >/dev/null 2>&1
echo "Kopia całej historii z GitHuba: dist/history-backup-$STAMP.bundle"

# Lokalna gałąź dla każdej gałęzi z GitHuba, żeby przepisać wszystkie.
for branch in $(git for-each-ref --format='%(refname:strip=3)' refs/remotes/origin | grep -v '^HEAD$'); do
    git show-ref -q --verify "refs/heads/$branch" || git branch -q "$branch" "origin/$branch"
done
REFS=()
while IFS= read -r ref; do REFS+=("$ref"); done < <(git for-each-ref --format='%(refname)' refs/heads refs/tags)

export MUFL EMAIL
FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch --force \
    --index-filter 'git rm -q --cached --ignore-unmatch "$MUFL"' \
    --tree-filter 'grep -rlF --exclude-dir=.git "$EMAIL" . 2>/dev/null | while IFS= read -r f; do perl -pi -e "s/\\Q\$ENV{EMAIL}\\E//g" "$f"; done; true' \
    --tag-name-filter cat -- "${REFS[@]}" >/dev/null

git for-each-ref --format='%(refname)' refs/original | xargs -n 1 git update-ref -d
git remote remove origin
git reflog expire --expire=now --all
git gc -q --prune=now

echo "=== Sprawdzenie ==="
FOUND_FILE="$(git log --all --oneline -- "$MUFL" | wc -l | tr -d ' ')"
FOUND_EMAIL=0
for commit in $(git rev-list --all); do
    if git grep -q -F "$EMAIL" "$commit" -- 2>/dev/null; then FOUND_EMAIL=$((FOUND_EMAIL + 1)); fi
done
echo "Commity z plikiem $MUFL: $FOUND_FILE, commity z adresem e-mail: $FOUND_EMAIL, gałęzie i tagi: ${#REFS[@]}"
[ "$FOUND_FILE" = "0" ] && [ "$FOUND_EMAIL" = "0" ] || { echo "Coś zostało; nic nie wysyłam." >&2; exit 1; }

git checkout -q main
if ! grep -qxF "/$MUFL" .gitignore; then
    printf '\n# Prywatny eksport Holyrics (usunięty z historii 2026-10-16); tylko lokalnie do testów\n/%s\n' "$MUFL" >> .gitignore
    git add .gitignore
    git -c user.name="$(git -C "$ROOT" config user.name)" -c user.email="$(git -C "$ROOT" config user.email)" \
        commit -q -m "chore: keep the private Holyrics export out of the repository"
fi

if [ "$PUSH" != "--push" ]; then
    echo "Próba zakończona w $WORK; niczego nie wysłano. Wysłanie: scripts/rewrite_history.sh --push"
    exit 0
fi
git remote add origin "$REMOTE"
for ref in "${REFS[@]}"; do git push -q --force origin "$ref:$ref"; done
echo "Wysłano przepisaną historię (${#REFS[@]} gałęzi i tagów)."
echo "Synchronizacja tego katalogu roboczego (plik .mufl zostaje na dysku):"
echo "  git fetch --all --prune && git checkout main && git reset --keep origin/main"
echo "Stare lokalne gałęzie usuń poleceniem git branch -D NAZWA albo sklonuj repozytorium od nowa."

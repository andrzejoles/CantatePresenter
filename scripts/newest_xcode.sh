#!/usr/bin/env bash
# Najnowszy stabilny Xcode w katalogu (domyślnie /Applications) dla CI (R1-04, R9-01).
# Obraz runnera GitHuba daje betom i kandydatom wydania zwykłe dowiązania z numerem wersji
# (Xcode_26.5.app → Xcode_26.5_beta_2.app, Xcode_26.6.app → Xcode_26.6_Release_Candidate_2.app),
# więc nazwy są sprawdzane po rozwiązaniu dowiązań. Pomijane: beta, Release_Candidate, RC.
# Użycie: scripts/newest_xcode.sh [katalog]; scripts/newest_xcode.sh --self-test sprawdza wybór na makiecie.
set -euo pipefail

newest_xcode() {
    local dir="$1" app
    for app in "$dir"/Xcode*.app; do
        [ -e "$app" ] || continue
        realpath "$app"
    done | grep -viE '(beta|release[_ -]?candidate|[_ -]rc[0-9_ ]*\.app$)' | sort -uV | tail -1
}

self_test() {
    local mock
    mock="$(mktemp -d -t cantate-xcode-mock)"
    trap 'rm -rf "$mock"' RETURN
    # Układ jak na obrazie macos-26 w okresie przed wydaniem (przegląd R9-01).
    mkdir "$mock/Xcode_26.3.app" "$mock/Xcode_26.4.1.app" "$mock/Xcode_26.5_beta_2.app" \
        "$mock/Xcode_26.6_Release_Candidate_2.app" "$mock/Xcode-beta.app" "$mock/Xcode_27.0_RC.app"
    ln -s Xcode_26.4.1.app "$mock/Xcode_26.4.app"
    ln -s Xcode_26.5_beta_2.app "$mock/Xcode_26.5.app"
    ln -s Xcode_26.6_Release_Candidate_2.app "$mock/Xcode_26.6.app"
    ln -s Xcode_26.4.1.app "$mock/Xcode.app"
    local picked expected
    picked="$(newest_xcode "$mock")"
    expected="$(realpath "$mock/Xcode_26.4.1.app")"
    [ "$picked" = "$expected" ] || { echo "Wybrano $picked, oczekiwano $expected" >&2; return 1; }
    # Po wydaniu: stabilny 26.6 w osobnym katalogu wygrywa z 26.4.1.
    rm "$mock/Xcode_26.6.app"
    mkdir "$mock/Xcode_26.6.app"
    picked="$(newest_xcode "$mock")"
    expected="$(realpath "$mock/Xcode_26.6.app")"
    [ "$picked" = "$expected" ] || { echo "Wybrano $picked, oczekiwano $expected" >&2; return 1; }
    echo "newest_xcode: OK"
}

if [ "${1:-}" = "--self-test" ]; then
    self_test
    exit
fi
XCODE="$(newest_xcode "${1:-/Applications}")"
[ -n "$XCODE" ] || { echo "Brak stabilnego Xcode w ${1:-/Applications}" >&2; exit 1; }
echo "$XCODE"

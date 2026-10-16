#!/usr/bin/env bash
# Narzędzia Sparkle z pobranego pakietu (generate_keys, sign_update, generate_appcast) z kontem klucza
# „cantate-presenter” w Pęku kluczy. Przykład: scripts/sparkle_tools.sh generate_keys -x kopia-klucza.txt
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="${1:?Podaj narzędzie: generate_keys, sign_update albo generate_appcast}"
shift
BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
[ -x "$BIN/$TOOL" ] || (cd "$ROOT" && swift package resolve >/dev/null)
exec "$BIN/$TOOL" --account cantate-presenter "$@"

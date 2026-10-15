#!/usr/bin/env bash
# Testy wersji webowej w Chrome bez okna (bez Node.js i bez zależności).
# web/tools/serve.py serwuje web/, shared/ i VERSION; strona testów wysyła wynik do serwera,
# a ten zapisuje go do pliku. Czekamy na plik w zwykłym czasie (wirtualny czas Chrome psuje strumienie).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
PORT="${PORT:-$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')}"
WORK="$(mktemp -d)"
RESULT="$WORK/result.json"
TIMEOUT="${TIMEOUT:-90}"

python3 -I "$ROOT/web/tools/serve.py" "$PORT" "$RESULT" >/dev/null 2>&1 &
SERVER=$!
CHROME_PID=""
cleanup() {
  local status=$?
  if [ -n "$CHROME_PID" ]; then
    kill "$CHROME_PID" 2>/dev/null || true
    wait "$CHROME_PID" 2>/dev/null || true
  fi
  kill "$SERVER" 2>/dev/null || true
  wait "$SERVER" 2>/dev/null || true
  # Chrome może jeszcze chwilę pisać do profilu; błąd sprzątania nie zmienia wyniku testów.
  rm -rf "$WORK" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT
for _ in $(seq 1 100); do curl -s -o /dev/null "http://127.0.0.1:$PORT/VERSION" && break; sleep 0.1; done

"$CHROME" --headless=new --disable-gpu --no-first-run --no-default-browser-check --user-data-dir="$WORK/profile" \
  "http://127.0.0.1:$PORT/web/tests/index.html" >/dev/null 2>&1 &
CHROME_PID=$!

for _ in $(seq 1 $((TIMEOUT * 10))); do [ -s "$RESULT" ] && break; sleep 0.1; done

python3 -I - "$RESULT" <<'PY'
import json, sys
try:
    result = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    print("Testy się nie wykonały (brak wyniku w czasie)")
    sys.exit(1)
for failure in result["failures"]:
    print("✘", failure["name"])
    print("   ", failure["error"].replace("\n", "\n    "))
print(f"{'✔' if result['failed'] == 0 else '✘'} Testy web: {result['passed']} zaliczone, {result['failed']} nieudane")
sys.exit(1 if result["failed"] else 0)
PY

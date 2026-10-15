#!/usr/bin/env bash
# Testy wersji webowej w Chrome bez okna (bez Node.js i bez zależności).
# Serwer statyczny (web/tools/serve.py) udostępnia web/, shared/ i VERSION, bo testy czytają shared/fixtures.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
PORT="${PORT:-$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')}"
PROFILE="$(mktemp -d)"

python3 -I "$ROOT/web/tools/serve.py" "$PORT" >/dev/null 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null; rm -rf "$PROFILE"' EXIT
for _ in $(seq 1 100); do curl -s -o /dev/null "http://127.0.0.1:$PORT/VERSION" && break; sleep 0.1; done

DOM="$("$CHROME" --headless=new --disable-gpu --no-first-run --user-data-dir="$PROFILE" \
  --virtual-time-budget=60000 --dump-dom "http://127.0.0.1:$PORT/web/tests/index.html" 2>/dev/null)"
RESULT="$(printf '%s' "$DOM" | python3 -c 'import sys,re,html; m=re.search(r"<pre id=\"result\">(.*?)</pre>", sys.stdin.read(), re.S); print(html.unescape(m.group(1)) if m else "")')"

python3 - "$RESULT" <<'PY'
import json, sys
raw = sys.argv[1]
try:
    result = json.loads(raw)
except ValueError:
    print("Testy się nie wykonały:", raw[:500] or "(brak wyniku)")
    sys.exit(1)
for failure in result["failures"]:
    print("✘", failure["name"])
    print("   ", failure["error"].replace("\n", "\n    "))
print(f"{'✔' if result['failed'] == 0 else '✘'} Testy web: {result['passed']} zaliczone, {result['failed']} nieudane")
sys.exit(1 if result["failed"] else 0)
PY

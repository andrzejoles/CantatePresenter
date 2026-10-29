#!/usr/bin/env bash
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

# Zawsze budujemy (przyrostowo), żeby po zmianach w źródłach nie uruchomić starej wersji (R1-08).
./build_app.sh

echo "Uruchamianie CantatePresenter..."
open "$DIR/build.noindex/CantatePresenter.app"

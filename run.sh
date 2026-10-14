#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

if [ ! -d "$DIR/CantatePresenter.app" ]; then
    echo "Pakiet CantatePresenter.app nie istnieje. Budowanie..."
    ./build_app.sh
fi

echo "Uruchamianie CantatePresenter..."
open "$DIR/CantatePresenter.app"

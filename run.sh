#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

if [ ! -d "$DIR/HolyricsMac.app" ]; then
    echo "Pakiet HolyricsMac.app nie istnieje. Budowanie..."
    ./build_app.sh
fi

echo "Uruchamianie Holyrics Mac..."
open "$DIR/HolyricsMac.app"

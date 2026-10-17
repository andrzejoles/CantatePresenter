#!/usr/bin/env python3
"""Eksport wbudowanej bazy chwytów z macOS (GuitarChordsService.populateCuratedChords) do JSON dla Windows.

Uruchom po każdej zmianie bazy w Swift:
    python3 -I windows/tools/export_chords_catalog.py
Zgodność pilnuje test ChordsCatalogTests w windows/tests.
"""
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / "Sources/CantatePresenterCore/Services/GuitarChordsService.swift"
TARGET = ROOT / "windows/src/CantatePresenter.Core/Chords/chords_catalog.json"

PATTERN = re.compile(
    r'add\("(?P<title>[^"]+)",\s*key:\s*"(?P<key>[^"]*)",\s*chords:\s*"""\n(?P<body>.*?)\n(?P<indent>[ \t]*)"""'
    r'(?:,\s*artist:\s*"(?P<artist>[^"]*)")?\)',
    re.S,
)


def main() -> None:
    text = SOURCE.read_text(encoding="utf-8")
    entries = []
    for match in PATTERN.finditer(text):
        indent = match.group("indent")
        lines = [line[len(indent):] if line.startswith(indent) else line.lstrip() for line in match.group("body").split("\n")]
        entries.append({
            "title": match.group("title"),
            "artist": match.group("artist") or "Tradycyjna / Religijna",
            "key": match.group("key"),
            "chords": "\n".join(lines),
        })
    TARGET.write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{len(entries)} pieśni -> {TARGET.relative_to(ROOT)}")


if __name__ == "__main__":
    main()

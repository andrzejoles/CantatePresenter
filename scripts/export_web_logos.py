#!/usr/bin/env python3
"""Eksport logo planszy startowej z wersji macOS (LogoPreset.swift) do web/logos.json.

Wzorcem jest LogoCatalog w Swift; test WebLogosTests sprawdza, że plik jest aktualny.
Uruchom po każdej zmianie logo: python3 -I scripts/export_web_logos.py
"""
import base64
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SWIFT = os.path.join(ROOT, "Sources/CantatePresenterCore/Models/LogoPreset.swift")
END_PNG = os.path.join(ROOT, "Sources/CantatePresenterCore/Resources/end_logo.png")
OUTPUT = os.path.join(ROOT, "web/logos.json")


def main():
    source = open(SWIFT, encoding="utf-8").read()
    end_logo = base64.b64encode(open(END_PNG, "rb").read()).decode()
    pattern = re.compile(r'LogoPreset\(\s*id: "([^"]+)",\s*name: "([^"]+)",.*?svgContent: """\n(.*?)\n\s*"""', re.S)
    logos = []
    for identifier, name, svg in pattern.findall(source):
        # Wcięcie wieloliniowego literału Swift (jak kompilator: według wcięcia zamykającego """).
        lines = svg.split("\n")
        indent = min(len(l) - len(l.lstrip(" ")) for l in lines if l.strip())
        svg = "\n".join(l[indent:] for l in lines)
        svg = svg.replace("\\(ENDLogoAsset.base64PNG)", end_logo)
        logos.append({"id": identifier, "name": name, "svg": svg})
    with open(OUTPUT, "w", encoding="utf-8") as target:
        json.dump(logos, target, ensure_ascii=False, indent=1)
        target.write("\n")
    print(f"Zapisano {len(logos)} logo do web/logos.json")


if __name__ == "__main__":
    main()

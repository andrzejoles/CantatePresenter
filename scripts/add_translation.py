#!/usr/bin/env python3
"""Dodaje tekst interfejsu z tłumaczeniami do Localizable.xcstrings (kolejność kluczy jak w pliku, format jak Xcode).

Uruchomienie: python3 -I scripts/add_translation.py "Polski tekst" "English" "Deutsch" "Español" "Українська"
Usunięcie nieużywanych tekstów: python3 -I scripts/add_translation.py --remove "Polski tekst" ["Inny tekst" ...]
"""
import json, os, sys

PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Sources/CantatePresenterCore/Resources/Localizable.xcstrings")
with open(PATH, encoding="utf-8") as f:
    catalog = json.load(f)
strings = catalog["strings"]

if sys.argv[1:2] == ["--remove"]:
    keys = sys.argv[2:]
    missing = [key for key in keys if key not in strings]
    if not keys or missing:
        sys.exit("Brak w katalogu: " + ", ".join(missing) if missing else "Podaj klucze do usunięcia")
    for key in keys:
        del strings[key]
    message = "usunięto: " + ", ".join(keys)
else:
    key, *values = sys.argv[1:]
    if len(values) != 4:
        sys.exit("Podaj klucz i 4 tłumaczenia: en de es uk")
    strings[key] = {"localizations": {lang: {"stringUnit": {"state": "translated", "value": value}}
                                      for lang, value in zip(["en", "de", "es", "uk"], values)}}
    was_sorted = list(strings)[:-1] == sorted(list(strings)[:-1])
    if was_sorted:
        catalog["strings"] = dict(sorted(strings.items()))
    message = ("dodano (posortowane): " if was_sorted else "dodano na końcu: ") + key

with open(PATH, "w", encoding="utf-8") as f:
    f.write(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
print(message)

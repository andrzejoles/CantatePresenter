#!/usr/bin/env python3
"""Dodaje tekst interfejsu z tłumaczeniami do Localizable.xcstrings (kolejność kluczy jak w pliku, format jak Xcode).

Uruchomienie: python3 -I scripts/add_translation.py "Polski tekst" "English" "Deutsch" "Español" "Українська"
"""
import json, os, sys

PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Sources/CantatePresenterCore/Resources/Localizable.xcstrings")
key, *values = sys.argv[1:]
if len(values) != 4:
    sys.exit("Podaj klucz i 4 tłumaczenia: en de es uk")
with open(PATH, encoding="utf-8") as f:
    catalog = json.load(f)
strings = catalog["strings"]
strings[key] = {"localizations": {lang: {"stringUnit": {"state": "translated", "value": value}}
                                  for lang, value in zip(["en", "de", "es", "uk"], values)}}
was_sorted = list(strings) [:-1] == sorted(list(strings)[:-1])
if was_sorted:
    catalog["strings"] = dict(sorted(strings.items()))
with open(PATH, "w", encoding="utf-8") as f:
    f.write(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
print(("dodano (posortowane): " if was_sorted else "dodano na końcu: ") + key)

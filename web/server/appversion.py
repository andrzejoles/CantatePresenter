"""Wersja aplikacji z liczby commitów, ta sama reguła co scripts/version.sh.

Co 10 commitów +1 w ostatnim członie (0–9), co 100 w środkowym (0–99), co 10 000 w głównym (od 1).
Bez gita (kopia samego katalogu web/ na serwerze): plik VERSION w katalogu głównym albo web/VERSION
(utwórz go poleceniem `scripts/version.sh > web/VERSION` przed kopiowaniem).
"""
import os
import subprocess


def from_count(count: int) -> str:
    bumps = max(0, count) // 10
    return f"{1 + bumps // 1000}.{(bumps // 10) % 100}.{bumps % 10}"


def current(repo_root: str) -> str:
    try:
        result = subprocess.run(["git", "-C", repo_root, "rev-list", "--count", "HEAD"],
                                capture_output=True, text=True, timeout=5)
        if result.returncode == 0 and result.stdout.strip().isdigit():
            return from_count(int(result.stdout.strip()))
    except (OSError, subprocess.SubprocessError):
        pass
    for candidate in (os.path.join(repo_root, "VERSION"), os.path.join(repo_root, "web", "VERSION")):
        try:
            with open(candidate, encoding="utf-8") as source:
                text = source.read().strip()
            if text:
                return text
        except OSError:
            continue
    return "dev"


def module_source(version: str) -> bytes:
    """Treść web/src/version.js podstawiana przez serwery w miejsce pliku z repozytorium."""
    return f'// Wygenerowane przez serwer (web/server/appversion.py).\nexport const APP_VERSION = "{version}";\n'.encode()

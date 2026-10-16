"""Wersja aplikacji z historii gita, ta sama reguła co scripts/version.sh.

GŁÓWNY.ŚRODKOWY.OSTATNI: ostatni = commity od ostatniego scalonego PR, środkowy = liczba scalonych PR
(jedna cyfra 0–9), główny = 1 + co 10 PR. Scalony PR = commit „Merge pull request #…” w historii
pierwszego rodzica. Bez gita (kopia samego katalogu web/ na serwerze): plik VERSION w katalogu głównym
albo web/VERSION (utwórz go poleceniem `scripts/version.sh > web/VERSION` przed kopiowaniem).
"""
import os
import subprocess


def from_counts(pull_requests: int, commits: int) -> str:
    pull_requests = max(0, pull_requests)
    return f"{1 + pull_requests // 10}.{pull_requests % 10}.{max(0, commits)}"


def _git(repo_root: str, *args: str) -> str:
    result = subprocess.run(["git", "-C", repo_root, *args], capture_output=True, text=True, timeout=5)
    if result.returncode != 0:
        raise OSError(result.stderr)
    return result.stdout


def from_git(repo_root: str) -> str:
    merges = _git(repo_root, "log", "--first-parent", "--merges", "--grep=^Merge pull request #", "--format=%H", "HEAD").split()
    if merges:
        commits = int(_git(repo_root, "rev-list", "--count", "--first-parent", f"{merges[0]}..HEAD"))
    else:
        commits = int(_git(repo_root, "rev-list", "--count", "--first-parent", "HEAD"))
    return from_counts(len(merges), commits)


def current(repo_root: str) -> str:
    try:
        return from_git(repo_root)
    except (OSError, ValueError, subprocess.SubprocessError):
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

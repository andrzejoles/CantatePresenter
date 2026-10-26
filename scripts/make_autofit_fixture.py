"""Wzorzec shared/fixtures/autofit.json (python3 -I scripts/make_autofit_fixture.py shared/fixtures/autofit.json): Auto-Fit ze stałym pomiarem (szerokość = liczba znaków × rozmiar × 0,6)."""
import json, math, re, sys

def width(text, size): return len(text) * size * 0.6

def wrapped_height(text, size, w, ls):
    lines = 0
    for paragraph in text.split("\n"):
        words = [x for x in re.split(r"\s+", paragraph) if x]
        lines += 1
        current = ""
        for word in words:
            cand = f"{current} {word}" if current else word
            if current and width(cand, size) > w: lines += 1; current = word
            else: current = cand
    return lines * size * 1.2 + max(0, lines - 1) * size * (ls - 1)

def fit(text, W, H, ls=1.15, margin=0.07, mn=14, mx=260):
    if not text.strip(): return 48
    if W <= 50 or H <= 50: return 24
    uw = max(40, W * (1 - 2 * margin)) * 0.99
    uh = max(40, H * (1 - 2 * margin)) * 0.99
    words = [x for x in re.split(r"\s+", text) if x]
    lo, hi, best = mn, mx, mn
    for _ in range(12):
        mid = (lo + hi) / 2
        if mid < mn: break
        if any(width(x, mid) > uw for x in words): hi = mid; continue
        if wrapped_height(text, mid, uw, ls) <= uh: best = mid; lo = mid
        else: hi = mid
    return max(mn, math.floor(best))

cases = [
    {"name": "Pusty tekst", "text": "  \n ", "width": 1920, "height": 1080, "anyMeasurer": True},
    {"name": "Za mały ekran", "text": "Chwała na wysokości", "width": 40, "height": 400, "anyMeasurer": True},
    {"name": "Krótki wers: ogranicza maksymalny rozmiar", "text": "Amen", "width": 1920, "height": 1080},
    {"name": "Długie słowo: ogranicza szerokość", "text": "Najprzenajświętszego", "width": 1280, "height": 720},
    {"name": "Cztery wersy: ogranicza wysokość", "text": "Idziemy razem przez zielone łąki\nsłońce nad nami świeci jasno\nśpiewamy pieśń o dobrym dniu\nwiatr niesie nasze słowa", "width": 1920, "height": 1080},
    {"name": "Długi wers zawijany", "text": "To jest bardzo długi wers próbnej pieśni, który na pewno nie zmieści się w jednej linii ekranu", "width": 1024, "height": 768},
    {"name": "Pusta linia w środku", "text": "Pierwszy wers\n\nOstatni wers", "width": 1920, "height": 1080},
    {"name": "Większe odstępy i marginesy", "text": "Pan jest pasterzem moim\nniczego mi nie braknie", "width": 1920, "height": 1080, "lineSpacingFactor": 1.6, "marginPercent": 0.15},
    {"name": "Minimalny rozmiar", "text": " ".join(["słowo"] * 400), "width": 800, "height": 600},
]
for c in cases:
    c["expected"] = fit(c["text"], c["width"], c["height"], c.get("lineSpacingFactor", 1.15), c.get("marginPercent", 0.07))
with open(sys.argv[1], "w", encoding="utf-8") as output:
    json.dump({"measure": "Szerokość tekstu = liczba znaków (UTF-16) × rozmiar × 0,6; przypadki z anyMeasurer nie zależą od pomiaru (także AppKit w macOS).", "cases": cases},
              output, ensure_ascii=False, indent=1)
print([c["expected"] for c in cases])

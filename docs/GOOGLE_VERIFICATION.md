# Weryfikacja aplikacji w Google (logowanie do Dysku Google)

Cel: zniesienie limitu 100 użytkowników testowych i ostrzeżenia „Google nie zweryfikował tej aplikacji”.
Aplikacja prosi tylko o zakresy **niewrażliwe** (`drive.file`, `userinfo.email`), więc wystarczy
**weryfikacja marki**: bez audytu bezpieczeństwa i bez filmu. Zwykle trwa 2–3 dni robocze.

## Przygotowane w repozytorium

- Strona domowa: `docs/index.html` → `https://andrzejoles.github.io/CantatePresenter/`
- Polityka prywatności (PL i EN, z zapisem o Limited Use): `docs/privacy.html`
  → `https://andrzejoles.github.io/CantatePresenter/privacy.html`
- Ikona 120×120 px lub większa: `web/icons/icon-512.png`

GitHub Pages publikuje katalog `docs/` z gałęzi `main` (włączone w ustawieniach repozytorium: Settings → Pages).

## Kroki właściciela (konto Google, nie da się ich zrobić z repozytorium)

1. **Weryfikacja domeny** w [Google Search Console](https://search.google.com/search-console): „Dodaj usługę” →
   „Prefiks URL” → `https://andrzejoles.github.io/CantatePresenter/` → metoda „Plik HTML”. Pobrany plik
   `googleXXXX.html` wrzuć do `docs/` (commit na `main`), poczekaj na publikację strony i kliknij „Zweryfikuj”.
2. **Google Cloud Console** → projekt `CantatePresenter` → *Google Auth Platform* (dawniej „Ekran zgody OAuth”):
   - *Branding*: nazwa „CantatePresenter”, logo (`icon-512.png`), e-mail pomocy, strona domowa i polityka prywatności
     z adresów wyżej, domena autoryzowana `andrzejoles.github.io`, e-mail kontaktowy dewelopera.
   - *Data Access*: tylko `.../auth/drive.file` i `.../auth/userinfo.email` (oraz `openid`, jeśli jest dodany).
   - *Audience*: „Opublikuj aplikację” (z trybu testowego do produkcji).
3. *Verification Center* → „Prześlij do weryfikacji”. Uzasadnienie zakresów (można wkleić):
   > CantatePresenter is a free macOS app for churches that projects song lyrics. Users can optionally save backups of
   > their song library to their own Google Drive. drive.file is used only to create and read the backup files the
   > app creates; userinfo.email only to show which account the backups go to. No data is sent to the developer.
4. Odpowiadaj na e-maile od zespołu weryfikacji (przychodzą na e-mail kontaktowy dewelopera).

Po zatwierdzeniu nic nie trzeba zmieniać w aplikacji: ten sam klient OAuth zacznie działać dla wszystkich.

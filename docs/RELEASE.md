# Wydanie wersji macOS

Instrukcja dla właściciela: podpis Developer ID, notaryzacja, automatyczne aktualizacje (Sparkle).
Bez certyfikatu wszystko działa jak dotąd (podpis ad-hoc); kroki z certyfikatem włączają się same,
gdy ustawisz zmienne środowiskowe opisane niżej.

## Numer wersji

Liczony z historii gita (`scripts/version.sh`): `(1 + PR/10).(PR mod 10).(commity od ostatniego scalonego PR)`.
Wydanie robi się zaraz po scaleniu PR, wtedy wersja kończy się na `.0` (np. `1.9.0`). Numer kompilacji
(`CFBundleVersion`) to liczba wszystkich commitów i rośnie z każdym wydaniem, czego wymaga Sparkle.

## 1. Podpis Developer ID (jednorazowo)

1. Konto w [Apple Developer Program](https://developer.apple.com/programs/) (99 USD rocznie).
2. W Xcode: Settings → Accounts → Manage Certificates → „+” → **Developer ID Application** i **Developer ID Installer**.
   Certyfikaty trafią do Pęku kluczy. Sprawdzenie: `security find-identity -v -p codesigning`.
3. Hasło dla aplikacji na [appleid.apple.com](https://appleid.apple.com) (Logowanie i bezpieczeństwo → Hasła do aplikacji),
   potem raz zapisz profil notaryzacji w Pęku kluczy:
   ```bash
   xcrun notarytool store-credentials cantate-notary --apple-id TWÓJ_APPLE_ID --team-id TEAMID --password HASŁO_APLIKACJI
   ```

## 2. Budowanie podpisanych instalatorów

```bash
export CANTATE_SIGN_IDENTITY="Developer ID Application: Imię Nazwisko (TEAMID)"
export CANTATE_INSTALLER_IDENTITY="Developer ID Installer: Imię Nazwisko (TEAMID)"
export CANTATE_NOTARY_PROFILE=cantate-notary
./build_installer.sh
```

`build_app.sh` podpisuje wtedy aplikację z Hardened Runtime i uprawnieniem do mikrofonu
(`Resources/CantatePresenter.entitlements`), najpierw zagnieżdżone części Sparkle. `build_installer.sh` podpisuje
DMG i PKG, wysyła je do notaryzacji (`scripts/notarize.sh`) i przypina bilet. Ścieżkę Hardened Runtime można
sprawdzić bez certyfikatu: `CANTATE_SIGN_IDENTITY=- ./build_app.sh`.

## 3. Automatyczne aktualizacje (Sparkle)

Aplikacja sprawdza raz dziennie plik `appcast.xml` z ostatniego wydania na GitHubie
(`https://github.com/andrzejoles/CantatePresenter/releases/latest/download/appcast.xml`); menu
„Sprawdź uaktualnienia…” robi to od razu. Aktualizacja jest podpisana kluczem EdDSA, więc nikt poza
właścicielem klucza nie podsunie aplikacji innego pliku.

Klucz (jednorazowo, prywatna część zostaje w Pęku kluczy, publiczna jest w `build_app.sh` jako `SUPublicEDKey`):
```bash
scripts/sparkle_tools.sh generate_keys -p         # wypisuje klucz publiczny (klucz już istnieje)
scripts/sparkle_tools.sh generate_keys -x klucz.txt  # kopia zapasowa klucza prywatnego (trzymaj poza repozytorium!)
```
Utrata klucza prywatnego oznacza, że zainstalowane aplikacje nie przyjmą kolejnych aktualizacji
(trzeba będzie raz zainstalować nową wersję ręcznie).

Wydanie (po scaleniu PR na `main`):
```bash
scripts/release.sh            # buduje, podpisuje, tworzy appcast.xml i szkic wydania na GitHubie
gh release edit vX.Y.Z --draft=false   # publikacja po sprawdzeniu szkicu
```

Bez podpisu Developer ID aktualizacje działają, ale macOS przy pierwszym uruchomieniu nowej wersji może pytać
o zgodę (aplikacja nie jest notaryzowana).

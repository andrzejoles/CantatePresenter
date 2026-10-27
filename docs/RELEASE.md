# Wydanie wersji macOS

Instrukcja dla właściciela: podpis Developer ID, notaryzacja, automatyczne aktualizacje (Sparkle).
Bez certyfikatu wszystko działa jak dotąd (podpis ad-hoc); kroki z certyfikatem włączają się same,
gdy ustawisz zmienne środowiskowe opisane niżej.

**Decyzja właściciela (2026-10-16): na razie bez konta Apple Developer** (koszt). Wydania są podpisane ad-hoc
i nienotaryzowane; punkty 1 i 2 czekają, aż konto będzie potrzebne. Co to oznacza w praktyce: patrz
„Wydanie bez Developer ID” na końcu.

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

`build_app.sh` podpisuje wtedy aplikację certyfikatem (ze znacznikiem czasu), najpierw zagnieżdżone części Sparkle.
`build_installer.sh` podpisuje DMG i PKG, wysyła je do notaryzacji (`scripts/notarize.sh`) i przypina bilet.

Hardened Runtime jest włączony przy każdym podpisie, także ad-hoc (R3-01): bez niego inny program uruchomiony
na tym koncie mógłby wstrzyknąć kod przez `DYLD_INSERT_LIBRARIES` i przejąć tokeny Dysku Google z Pęku kluczy
oraz zgodę na mikrofon. Uprawnienia: mikrofon (`Resources/CantatePresenter.entitlements`); przy podpisie ad-hoc
`build_app.sh` dodaje `com.apple.security.cs.disable-library-validation`, bo bez identyfikatora zespołu kontrola
bibliotek odrzuca Sparkle.framework z pakietu. Zmienne `DYLD_*` nadal są ignorowane. `build_app.sh` przerywa
budowanie, jeśli podpis nie ma Hardened Runtime.

Bez kontroli bibliotek dyld wczyta każdą bibliotekę, którą znajdzie w ścieżkach `LC_RPATH` programu. Dlatego
`build_app.sh` usuwa ścieżki dopisane przez SwiftPM (`@loader_path`, bezwzględna ścieżka do narzędzi Xcode, R7-01)
i zostawia tylko `/usr/lib/swift` (chroniony przez SIP) oraz `@executable_path/../Frameworks`; inna lista
przerywa budowanie, podobnie jak biblioteka wczytywana spoza `/System`, `/usr/lib` i Sparkle z pakietu. Ryzyko, które zostaje przy podpisie ad-hoc (decyzja: bez konta Apple Developer): program,
który może zapisywać w pakiecie aplikacji, może podmienić Sparkle.framework i uruchomić swój kod z uprawnieniami
aplikacji (Pęk kluczy, mikrofon). Pakiet przeciągnięty do Programów albo zainstalowany przez „Zainstaluj
w folderze Programy” należy do użytkownika; instalator PKG zapisuje go jako root, co tę drogę zamyka.

`build_app.sh` sprawdza też `LC_BUILD_VERSION`: `minos` równe minimalnej wersji macOS z `Package.swift` (jedyne
źródło, z niego też `LSMinimumSystemVersion`, R9-04) i wersja SDK, z którym zbudowano program (R5-02).
Domyślny system budowania SwiftPM wpisywał tam 14.0, przez co AppKit i SwiftUI działały w trybie zgodności ze
starym SDK (na macOS 26+ bez nowego wyglądu).

## 3. Automatyczne aktualizacje (Sparkle)

Aplikacja sprawdza raz dziennie plik `appcast.xml` z ostatniego wydania na GitHubie
(`https://github.com/andrzejoles/CantatePresenter/releases/latest/download/appcast.xml`); menu
„Sprawdź uaktualnienia…” robi to od razu. Aktualizacja jest podpisana kluczem EdDSA, więc nikt poza
właścicielem klucza nie podsunie aplikacji innego pliku. Podpisany jest też sam `appcast.xml`
(`SURequireSignedFeed`, `SUVerifyUpdateBeforeExtraction`, R3-09): zmieniony na GitHubie kanał (opis, odnośniki,
wersje) jest odrzucany, a archiwum jest sprawdzane przed rozpakowaniem. `generate_appcast` podpisuje kanał sam,
bo wymaga tego `Info.plist` aktualizacji; plik `appcast.xml` po wygenerowaniu nie może być już edytowany ręcznie.
Opis zmian w oknie aktualizacji pochodzi z pliku `CantatePresenter-X.Y.Z.md` (tytuły scalonych PR), który
`scripts/release.sh` zapisuje obok archiwum.

Próba aktualizacji bez klucza właściciela: jednorazowy klucz Ed25519 (CryptoKit) w pliku, dwie kopie aplikacji
z innym `CFBundleIdentifier` (osobne ustawienia) i tym kluczem w `SUPublicEDKey`, kanał z
`generate_appcast --ed-key-file` na lokalnym serwerze i `CANTATE_UPDATE_FEED=http://127.0.0.1:PORT/appcast.xml`
(oraz `CANTATE_DATA_DIR` z kopią danych).

Klucz (jednorazowo, prywatna część zostaje w Pęku kluczy, publiczna jest w `build_app.sh` jako `SUPublicEDKey`):
```bash
scripts/sparkle_tools.sh generate_keys -p         # wypisuje klucz publiczny (klucz już istnieje)
scripts/sparkle_tools.sh generate_keys -x klucz.txt  # kopia zapasowa klucza prywatnego (trzymaj poza repozytorium!)
```
Utrata klucza prywatnego oznacza, że zainstalowane aplikacje nie przyjmą kolejnych aktualizacji
(trzeba będzie raz zainstalować nową wersję ręcznie).

Wydanie (po scaleniu PR na `main`):
```bash
scripts/release.sh            # czeka na zielone CI, DMG + PKG + archiwum Sparkle, appcast.xml, szkic wydania na GitHubie
gh release edit vX.Y.Z --draft=false   # publikacja po sprawdzeniu szkicu
```

## 4. Wydanie bez Developer ID (obecny tryb)

- **Pierwsza instalacja na innym Macu:** pobrany DMG/PKG jest w kwarantannie, a Gatekeeper blokuje aplikację
  („nie można sprawdzić, czy nie zawiera złośliwego oprogramowania”). Po pierwszej próbie otwarcia:
  Ustawienia systemowe → Prywatność i ochrona → „Otwórz mimo to” (od macOS 15 kliknięcie z Ctrl już nie wystarcza).
  Alternatywa w Terminalu: `xattr -dr com.apple.quarantine /Applications/CantatePresenter.app`.
  Instalator PKG bez podpisu Developer ID jest blokowany tak samo; DMG jest prostszy.
- **Aktualizacje Sparkle** działają (sprawdzone lokalnie 2026-10-16, z Hardened Runtime i podpisanym kanałem
  2026-10-26): pobrany plik jest weryfikowany kluczem EdDSA, a aktualizacja instalowana przez Sparkle nie przechodzi
  ponownie przez kwarantannę.
- **Uprawnienia po aktualizacji:** podpis ad-hoc zmienia się z każdą wersją, więc macOS może ponownie zapytać
  o mikrofon (dyktowanie) i o dostęp do Pęku kluczy (tokeny Dysku Google, przycisk „Zawsze pozwalaj”).
- Na tym Macu (aplikacja budowana lokalnie, bez kwarantanny) nic się nie zmienia.

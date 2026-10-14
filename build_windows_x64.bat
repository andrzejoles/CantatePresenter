@echo off
chcp 65001 >nul
echo ====================================================================
echo   Budowanie CantatePresenter dla Windows 11 (Intel / AMD x64)
echo ====================================================================

REM Sprawdzenie czy zainstalowano .NET SDK 8.0 lub nowszy
dotnet --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [BLAD] Nie znaleziono polecenia dotnet.
    echo Zainstaluj .NET 8 SDK ze strony: https://dotnet.microsoft.com/download/dotnet/8.0
    pause
    exit /b 1
)

echo.
echo [1/3] Przywracanie pakietow NuGet (Microsoft.Web.WebView2, System.Text.Json)...
dotnet restore CantatePresenter\CantatePresenter.csproj
if %errorlevel% neq 0 (
    echo [BLAD] Nie udalo sie przywrocic pakietow NuGet.
    pause
    exit /b 1
)

echo.
echo [2/3] Kompilacja wersji Release (x64)...
dotnet build CantatePresenter\CantatePresenter.csproj -c Release -r win-x64 --no-restore
if %errorlevel% neq 0 (
    echo [BLAD] Blad kompilacji.
    pause
    exit /b 1
)

echo.
echo [3/3] Publikowanie pojedynczego pliku wykonywalnego CantatePresenter.exe...
dotnet publish CantatePresenter\CantatePresenter.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o publish\
if %errorlevel% neq 0 (
    echo [BLAD] Blad publikowania.
    pause
    exit /b 1
)

echo.
echo ====================================================================
echo   SUKCES! Gotowa aplikacja znajduje sie w folderze:
echo   publish\CantatePresenter.exe
echo ====================================================================
echo.
pause

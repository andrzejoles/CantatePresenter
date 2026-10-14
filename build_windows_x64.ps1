# CantatePresenter - PowerShell Build Script for Windows 11
Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "  Budowanie CantatePresenter dla Windows 11 (Intel / AMD x64)" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan

# Check dotnet CLI
try {
    $version = dotnet --version
    Write-Host "Znaleziono .NET SDK wersja: $version" -ForegroundColor Green
} catch {
    Write-Error "Nie znaleziono polecenia dotnet. Zainstaluj .NET 8.0 SDK: https://dotnet.microsoft.com/download/dotnet/8.0"
    exit 1
}

Write-Host "`n[1/3] Przywracanie pakietów NuGet..." -ForegroundColor Yellow
dotnet restore CantatePresenter/CantatePresenter.csproj

Write-Host "`n[2/3] Kompilacja Release (win-x64)..." -ForegroundColor Yellow
dotnet build CantatePresenter/CantatePresenter.csproj -c Release -r win-x64 --no-restore

Write-Host "`n[3/3] Publikowanie pojedynczego pliku wykonywalnego CantatePresenter.exe..." -ForegroundColor Yellow
dotnet publish CantatePresenter/CantatePresenter.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o publish/

Write-Host "`n====================================================================" -ForegroundColor Green
Write-Host "  SUKCES! Gotowa aplikacja znajduje się w folderze publish\" -ForegroundColor Green
Write-Host "  Plik uruchomieniowy: publish\CantatePresenter.exe" -ForegroundColor Green
Write-Host "====================================================================" -ForegroundColor Green

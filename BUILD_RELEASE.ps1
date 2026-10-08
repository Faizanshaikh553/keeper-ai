$ErrorActionPreference = 'Stop'
Write-Host "=== Keeper AI 1.0.12 / code 1004 release build ===" -ForegroundColor Cyan

flutter clean
if ($LASTEXITCODE -ne 0) { throw "flutter clean failed" }

flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }

flutter analyze
if ($LASTEXITCODE -ne 0) { throw "flutter analyze failed" }

flutter build appbundle --release
if ($LASTEXITCODE -ne 0) { throw "flutter build appbundle --release failed" }

$src = "build\app\outputs\bundle\release\app-release.aab"
$dst = "build\app\outputs\bundle\release\keeper-ai-1.0.12-1004.aab"
if (!(Test-Path $src)) { throw "AAB was not created: $src" }
Copy-Item $src $dst -Force
Write-Host "`nSUCCESS: $dst" -ForegroundColor Green
Write-Host "Upload this AAB to Google Play Console. Version code = 1004." -ForegroundColor Green

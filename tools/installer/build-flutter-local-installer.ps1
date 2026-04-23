$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$installerRoot = Join-Path $projectRoot "tools\installer"
$stageRoot = Join-Path $installerRoot "staging\flutter-local"
$outputDir = Join-Path $installerRoot "output"
$flutterRoot = Join-Path $projectRoot "flutter"
$flutterBinCandidates = @(
  "C:\Users\bekzod\Desktop\ataway kassa uchun\.flutter-sdk\flutter\bin\flutter.bat",
  "C:\src\flutter\bin\flutter.bat"
)
$flutterBin = $flutterBinCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
$isccPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
$releaseDir = Join-Path $flutterRoot "build\windows\x64\runner\Release"

if (-not $flutterBin) {
  throw "Flutter SDK topilmadi. Tekshirilgan yo'llar: $($flutterBinCandidates -join ', ')"
}
if (-not (Test-Path $isccPath)) {
  throw "Inno Setup topilmadi: $isccPath"
}

Push-Location $flutterRoot
try {
  & $flutterBin build windows --release --dart-define=API_BASE_URL=http://127.0.0.1:4000/api
} finally {
  Pop-Location
}

if (-not (Test-Path $releaseDir)) {
  throw "Flutter release build topilmadi: $releaseDir"
}

Remove-Item $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot "app"), $outputDir | Out-Null
Copy-Item -Path (Join-Path $releaseDir "*") -Destination (Join-Path $stageRoot "app") -Recurse -Force

& $isccPath "/DStageDir=$stageRoot" "/DOutputDir=$outputDir" (Join-Path $installerRoot "flutter-local.iss")

Write-Host "Flutter installer tayyor:" -ForegroundColor Green
Get-ChildItem $outputDir -Filter "ataway-pos-setup.exe" | Select-Object FullName, Length

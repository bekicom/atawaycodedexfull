$ErrorActionPreference = "Stop"

$candidates = @(
  (Join-Path $PSScriptRoot "..\.flutter-sdk\bin"),
  "C:\src\flutter\bin",
  "C:\flutter\bin",
  "D:\flutter\bin"
)

$flutterBin = $candidates | Where-Object { Test-Path (Join-Path $_ "flutter.bat") } | Select-Object -First 1

if (-not $flutterBin) {
  throw "Flutter SDK topilmadi."
}

$env:PATH = "$flutterBin;$env:PATH"

Set-Location $PSScriptRoot

flutter run -d windows

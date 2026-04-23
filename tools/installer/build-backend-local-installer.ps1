$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$installerRoot = Join-Path $projectRoot "tools\installer"
$stageRoot = Join-Path $installerRoot "staging\backend-local"
$outputDir = Join-Path $installerRoot "output"
$backendRoot = Join-Path $projectRoot "backend"
$nativeRoot = Join-Path $installerRoot "native"
$nodeRoot = "C:\Program Files\nodejs"
$isccPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
$compassUrl = "https://compass.mongodb.com/api/v2/download/latest/compass/stable/windows"
$compassInstallerPath = Join-Path $installerRoot "cache\compass-install.exe"
$nssmCandidates = @(
  "C:\Program Files\FiscalDriveAPI\nssm.exe",
  "C:\Program Files\ATAWAY Local Backend\tools\nssm.exe",
  "C:\Program Files\Odoo 19.0.20260109\nssm\win64\nssm.exe"
)
$nssmPath = $nssmCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

$mongoBinCandidates = @()
$mongoServerRoot = "C:\Program Files\MongoDB\Server"
if (Test-Path $mongoServerRoot) {
  $mongoBinCandidates += Get-ChildItem $mongoServerRoot -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName "bin" }
}
$mongoBinCandidates += @(
  (Join-Path $installerRoot "cache\mongo\bin"),
  (Join-Path $stageRoot "mongo\bin"),
  (Join-Path $installerRoot "staging\backend-local\mongo\bin")
)
$mongoBinRoot = $mongoBinCandidates | Where-Object { Test-Path (Join-Path $_ "mongod.exe") } | Select-Object -First 1
$mongoMongodSource = if ($mongoBinRoot) { Join-Path $mongoBinRoot "mongod.exe" } else { $null }

if (-not (Test-Path $isccPath)) {
  throw "Inno Setup topilmadi: $isccPath"
}
if (-not (Test-Path $nodeRoot)) {
  throw "Node.js topilmadi: $nodeRoot"
}
if (-not $mongoBinRoot) {
  throw "MongoDB bin topilmadi. Tekshirilgan yo'llar: $($mongoBinCandidates -join ', ')"
}
if ((Split-Path -Parent $mongoMongodSource).StartsWith($stageRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  $mongoCacheDir = Join-Path $installerRoot "cache\mongo\bin"
  New-Item -ItemType Directory -Force -Path $mongoCacheDir | Out-Null
  $cachedMongod = Join-Path $mongoCacheDir "mongod.exe"
  Copy-Item -Path $mongoMongodSource -Destination $cachedMongod -Force
  $mongoMongodSource = $cachedMongod
}
if (-not (Test-Path $nssmPath)) {
  throw "NSSM topilmadi. Tekshirilgan yo'llar: $($nssmCandidates -join ', ')"
}

& (Join-Path $nativeRoot "build-control-center.ps1")
$controlCenterExe = Join-Path $nativeRoot "build\ataway-control-center.exe"
if (-not (Test-Path $controlCenterExe)) {
  throw "Control Center build topilmadi: $controlCenterExe"
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $compassInstallerPath) | Out-Null
if (-not (Test-Path $compassInstallerPath)) {
  Write-Host "MongoDB Compass installer yuklanmoqda..." -ForegroundColor Yellow
  $ProgressPreference = "SilentlyContinue"
  Invoke-WebRequest -Uri $compassUrl -OutFile $compassInstallerPath
}
if (-not (Test-Path $compassInstallerPath)) {
  throw "MongoDB Compass installer yuklanmadi: $compassInstallerPath"
}

Remove-Item $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $stageRoot, $outputDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot "backend") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot "node") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot "mongo\bin") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot "tools") | Out-Null

$backendItems = @("src", "package.json", "package-lock.json", "node_modules")
foreach ($item in $backendItems) {
  Copy-Item -Path (Join-Path $backendRoot $item) -Destination (Join-Path $stageRoot "backend") -Recurse -Force
}

$envContent = @"
HOST=0.0.0.0
PORT=4000
MONGO_URI=mongodb://127.0.0.1:27017/uy_dokon_local
JWT_SECRET=uy_dokon_local_secret_2026
DEFAULT_TENANT_SLUG=local
DEFAULT_TENANT_NAME=Local Dokon
ADMIN_USERNAME=admin
ADMIN_PASSWORD=0000
ADMIN_ROLE=admin
STORE_CODE=7909
STORE_NAME=ataway
CENTRAL_API_BASE_URL=https://ataway.richman.uz/api
CENTRAL_SYNC_USERNAME=admin
CENTRAL_SYNC_PASSWORD=0000
TELEGRAM_BOT_TOKEN=
SUPERADMIN_TELEGRAM_IDS=
"@
Set-Content -Path (Join-Path $stageRoot "backend\.env") -Value $envContent -Encoding UTF8
Copy-Item -Path (Join-Path $backendRoot ".env.example") -Destination (Join-Path $stageRoot "backend\.env.example") -Force -ErrorAction SilentlyContinue

Copy-Item -Path (Join-Path $nodeRoot "node.exe") -Destination (Join-Path $stageRoot "node\node.exe") -Force
Copy-Item -Path $mongoMongodSource -Destination (Join-Path $stageRoot "mongo\bin\mongod.exe") -Force
Copy-Item -Path $nssmPath -Destination (Join-Path $stageRoot "tools\nssm.exe") -Force
Copy-Item -Path $controlCenterExe -Destination (Join-Path $stageRoot "tools\ataway-control-center.exe") -Force
Copy-Item -Path $compassInstallerPath -Destination (Join-Path $stageRoot "tools\compass-install.exe") -Force

& $isccPath "/DStageDir=$stageRoot" "/DOutputDir=$outputDir" (Join-Path $installerRoot "backend-local.iss")

Write-Host "Backend installer tayyor:" -ForegroundColor Green
Get-ChildItem $outputDir -Filter "ataway-local-backend-setup.exe" | Select-Object FullName, Length

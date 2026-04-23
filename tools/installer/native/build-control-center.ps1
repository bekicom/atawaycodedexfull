$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$source = Join-Path $scriptRoot "ataway_control_center.cpp"
$outputDir = Join-Path $scriptRoot "build"
$outputExe = Join-Path $outputDir "ataway-control-center.exe"
$objFile = Join-Path $outputDir "ataway_control_center.obj"
$pdbFile = Join-Path $outputDir "ataway_control_center.pdb"

$vsTools = "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\Common7\Tools\VsDevCmd.bat"
if (-not (Test-Path $vsTools)) {
  throw "VsDevCmd.bat topilmadi: $vsTools"
}

New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$cmd = "`"$vsTools`" -arch=x64 && cl /nologo /std:c++17 /EHsc /DUNICODE /D_UNICODE /Fo`"$objFile`" /Fd`"$pdbFile`" /Fe:`"$outputExe`" `"$source`" user32.lib gdi32.lib advapi32.lib shell32.lib ws2_32.lib iphlpapi.lib"
cmd /c $cmd

if (-not (Test-Path $outputExe)) {
  throw "Control Center build bo'lmadi: $outputExe"
}

Get-Item $outputExe | Select-Object FullName, Length, LastWriteTime

# Run from the extracted project: powershell -ExecutionPolicy Bypass -File .\setup.ps1
# Requires Flutter already installed and on PATH.
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$backupPath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $backupPath | Out-Null
$protectedItems = @("lib", "test", "pubspec.yaml", "analysis_options.yaml")
try {
    foreach ($item in $protectedItems) { Copy-Item $item $backupPath -Recurse }
    & flutter create --project-name med_ai --platforms=android,ios,web .
    if ($LASTEXITCODE -ne 0) { throw "Flutter project generation failed. Check flutter doctor and retry." }
} finally {
    foreach ($item in $protectedItems) {
        $saved = Join-Path $backupPath $item
        if (Test-Path $saved) {
            if (Test-Path $item) { Remove-Item $item -Recurse -Force }
            Copy-Item $saved . -Recurse
        }
    }
    Remove-Item $backupPath -Recurse -Force
}
& flutter pub get
if ($LASTEXITCODE -ne 0) { throw "Dependency installation failed." }
Write-Host "Ready. Run: flutter analyze; flutter test; flutter run -d chrome"

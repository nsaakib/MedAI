param([string]$Device = 'R58RC2S3KND')
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$health = Invoke-RestMethod 'http://127.0.0.1:8000/health' -TimeoutSec 5
if ($health.version -ne '1.2.0') { throw 'This is an older backend. Restart START_BACKEND.ps1 after installing the update.' }
if ($health.status -ne 'ok') { throw 'Start the backend in a separate terminal first.' }
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
if (!(Test-Path $adb)) { $adb = (Get-Command adb -ErrorAction Stop).Source }
& $adb -s $Device reverse tcp:18000 tcp:8000
if ($LASTEXITCODE -ne 0) { throw 'USB mapping failed. Reconnect, unlock the phone and allow USB debugging.' }
& flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'Flutter dependencies failed.' }
& flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'Resolve analyzer errors before building.' }
& flutter run -d $Device --dart-define=API_BASE_URL=http://127.0.0.1:18000

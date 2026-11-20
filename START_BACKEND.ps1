$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "backend")
if (!(Test-Path ".venv\Scripts\python.exe")) { py -3.11 -m venv .venv; if ($LASTEXITCODE -ne 0) { py -3.12 -m venv .venv } }
if (!(Test-Path ".venv\Scripts\python.exe")) { throw "Install Python 3.11 or 3.12 first." }
& .\.venv\Scripts\python.exe -m pip install -r requirements.txt
if ($LASTEXITCODE -ne 0) { throw "Dependency installation failed." }
& .\.venv\Scripts\python.exe -m app.manage init
if ($LASTEXITCODE -ne 0) { throw "Setup failed." }
& .\.venv\Scripts\python.exe -m uvicorn app.server:app --host 0.0.0.0 --port 8000

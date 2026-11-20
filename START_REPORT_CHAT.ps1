$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (!(Test-Path '.\START_BACKEND.ps1')) { throw 'Install this script in your existing Med.ai project.' }
if ([string]::IsNullOrWhiteSpace($env:GROQ_API_KEY)) {
    Write-Host 'Create your own API key at https://console.groq.com/keys. Stay on the Free plan for testing.'
    $secret = Read-Host 'Paste your Groq API key (hidden)' -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
    try { $env:GROQ_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer).Trim() }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer); $secret.Dispose() }
}
if ([string]::IsNullOrWhiteSpace($env:GROQ_API_KEY)) { throw 'No API key entered.' }
if ([string]::IsNullOrWhiteSpace($env:MEDAI_CHAT_MODEL)) { $env:MEDAI_CHAT_MODEL = 'openai/gpt-oss-20b' }
if (Test-Path 'C:\Program Files\Tesseract-OCR\tesseract.exe') {
    $env:Path = "C:\Program Files\Tesseract-OCR;$env:Path"
}
$env:MEDAI_OCR_ENABLED = 'true'
Write-Host 'Starting reports + AI chat. Keep this terminal open. The key is not written to your project.'
& '.\START_BACKEND.ps1'

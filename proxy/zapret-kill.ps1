$ErrorActionPreference = 'SilentlyContinue'
Get-Process winws | Stop-Process -Force
Start-Sleep -Milliseconds 500

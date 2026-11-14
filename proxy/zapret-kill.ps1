Get-Process winws | ForEach-Object { & taskkill.exe /PID $_.Id /T /F *> $null }

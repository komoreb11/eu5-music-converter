@echo off
for /f %%i in ('powershell -Command "Get-Date -UFormat %%s"') do set TS=%%i
rem -f: an HTTP error must not overwrite the cached script with an error page (offline launch keeps working)
curl -sfL -o "%TEMP%\eu4snd.ps1.tmp" "https://raw.githubusercontent.com/komoreb11/eu5-music-converter/main/EU4_Soundtrack_Setup.ps1?t=%TS%" && move /y "%TEMP%\eu4snd.ps1.tmp" "%TEMP%\eu4snd.ps1" >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\eu4snd.ps1"
if %ERRORLEVEL% NEQ 0 exit /b
start "" %*

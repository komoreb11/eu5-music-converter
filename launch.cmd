@echo off
for /f %%i in ('powershell -Command "Get-Date -UFormat %%s"') do set TS=%%i
curl -sL -o "%TEMP%\eu4snd.ps1" "https://raw.githubusercontent.com/komoreb11/eu5-music-converter/main/EU4_Soundtrack_Setup.ps1?t=%TS%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\eu4snd.ps1"
if %ERRORLEVEL% NEQ 0 exit /b
start "" %*

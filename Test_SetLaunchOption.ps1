$EU5_APPID = "3450310"
$LAUNCH_CMD = 'cmd /c "curl -sL -o %TEMP%\eu4launch.cmd https://raw.githubusercontent.com/komoreb11/eu5-music-converter/main/launch.cmd & call %TEMP%\eu4launch.cmd %command%"'

function Set-SteamLaunchOption {
    param([string]$AppId, [string]$Command)

    # Find Steam path from registry
    $steamPath = $null
    try { $steamPath = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -EA Stop).SteamPath -replace '/','\' } catch {}
    if (-not $steamPath) {
        try { $steamPath = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -EA Stop).InstallPath } catch {}
    }
    if (-not $steamPath -or -not (Test-Path $steamPath)) {
        Write-Host "[!] Steam not found" -ForegroundColor Yellow; return $false
    }

    $userdata = "$steamPath\userdata"
    if (-not (Test-Path $userdata)) { Write-Host "[!] Steam userdata not found" -ForegroundColor Yellow; return $false }

    # Find localconfig.vdf files
    $configs = Get-ChildItem "$userdata\*\config\localconfig.vdf" -EA SilentlyContinue
    if (-not $configs) { Write-Host "[!] No localconfig.vdf found" -ForegroundColor Yellow; return $false }

    $updated = 0
    foreach ($cfg in $configs) {
        $content = [System.IO.File]::ReadAllText($cfg.FullName, [System.Text.Encoding]::UTF8)

        # Check if EU5 section exists
        if ($content -notmatch [regex]::Escape("`"$AppId`"")) { continue }

        # Check if already set correctly
        if ($content -match [regex]::Escape("`"LaunchOptions`"`t`t`"$Command`"")) {
            Write-Host "[OK] Launch option already set for account $($cfg.Directory.Parent.Name)" -ForegroundColor Green
            $updated++; continue
        }

        # Pattern to find the app section and insert/update LaunchOptions
        # Try to update existing LaunchOptions first
        $appPattern = "(`"$AppId`"`r?`n\s*\{[^}]*?)`"LaunchOptions`"\s+`"[^`"]*`""
        if ($content -match $appPattern) {
            $content = $content -replace $appPattern, "`$1`"LaunchOptions`"`t`t`"$Command`""
        } else {
            # No existing LaunchOptions - insert after the app ID opening brace
            $insertPattern = "(`"$AppId`"`r?`n\s*\{)"
            if ($content -match $insertPattern) {
                $content = $content -replace $insertPattern, "`$1`r`n`t`t`t`t`"LaunchOptions`"`t`t`"$Command`""
            } else {
                Write-Host "[!] Could not find EU5 section in $($cfg.FullName)" -ForegroundColor Yellow
                continue
            }
        }

        [System.IO.File]::WriteAllText($cfg.FullName, $content, [System.Text.Encoding]::UTF8)
        Write-Host "[OK] Launch option set for account $($cfg.Directory.Parent.Name)" -ForegroundColor Green
        $updated++
    }

    if ($updated -eq 0) {
        Write-Host "[!] EU5 not found in any Steam account's config" -ForegroundColor Yellow
        return $false
    }
    return $true
}

Write-Host "Testing Set-SteamLaunchOption..."
$result = Set-SteamLaunchOption -AppId $EU5_APPID -Command $LAUNCH_CMD
if ($result) {
    Write-Host ""
    Write-Host "Restart Steam for the launch option to take effect." -ForegroundColor Cyan
}

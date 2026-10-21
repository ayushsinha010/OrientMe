# Keeps OrientMe's backend (8010) and frontend (3001) running - checks every
# 30s and restarts whichever one isn't listening. Runs hidden; put a shortcut
# to it in the current user's Startup folder so it starts automatically at
# logon - no admin rights needed, unlike Task Scheduler (see
# setup_background_tasks.ps1 for the Task Scheduler variant).
#
# This is a logon-time watchdog, not a true always-on Windows service - it
# only runs while this user is logged in, same honest caveat as the
# Task Scheduler approach would have needed for reboot survival anyway.

# Paths are relative to this script, so the repository can live anywhere.
$root = Split-Path -Parent $PSScriptRoot
$backendDir = Join-Path $root "backend"
$frontendDir = Join-Path $root "frontend"
$logDir = $PSScriptRoot

function Test-PortListening {
    param([int]$Port)
    return $null -ne (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
}

while ($true) {
    if (-not (Test-PortListening -Port 8010)) {
        Start-Process -FilePath "python" -ArgumentList "manage.py runserver 8010" `
            -WorkingDirectory $backendDir -WindowStyle Hidden `
            -RedirectStandardOutput "$logDir\backend.log" -RedirectStandardError "$logDir\backend_err.log"
    }
    if (-not (Test-PortListening -Port 3001)) {
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c npm run dev -- -p 3001" `
            -WorkingDirectory $frontendDir -WindowStyle Hidden `
            -RedirectStandardOutput "$logDir\frontend.log" -RedirectStandardError "$logDir\frontend_err.log"
    }
    Start-Sleep -Seconds 30
}

# One-time setup: registers OrientMe's backend and frontend as Windows
# Scheduled Tasks that start at logon and restart automatically if they
# ever crash - so OrientMe stays available without a terminal window open,
# and comes back on its own after a reboot.
#
# Re-run this script any time to update the registered tasks (it replaces
# them cleanly). To remove them entirely:
#   Unregister-ScheduledTask -TaskName "OrientMe Backend" -Confirm:$false
#   Unregister-ScheduledTask -TaskName "OrientMe Frontend" -Confirm:$false

$scriptsDir = $PSScriptRoot

function Register-OrientMeTask {
    param([string]$Name, [string]$ScriptPath)

    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit ([TimeSpan]::Zero)  # no time limit - this runs forever, not a one-shot job

    Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName $Name -Action $action -Trigger $trigger -Settings $settings `
        -Description "OrientMe - keeps running in the background, restarts on crash or logon" | Out-Null
    Write-Host "Registered task: $Name"
}

Register-OrientMeTask -Name "OrientMe Backend"  -ScriptPath "$scriptsDir\run_backend.ps1"
Register-OrientMeTask -Name "OrientMe Frontend" -ScriptPath "$scriptsDir\run_frontend.ps1"

# Start both right now too, so this takes effect immediately without
# needing to log off/on.
Start-ScheduledTask -TaskName "OrientMe Backend"
Start-ScheduledTask -TaskName "OrientMe Frontend"
Write-Host "Both tasks started."

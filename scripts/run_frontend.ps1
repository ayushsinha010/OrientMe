# Runs the OrientMe Next.js frontend, kept alive by a Windows Scheduled Task
# (see setup_background_tasks.ps1) - restarts automatically on logon or on
# crash, so it survives normal use without a terminal window having to stay
# open.
#
# Paths are relative to this script, so the repository can live anywhere.
$root = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $root "frontend")
npm run dev -- -p 3001 *>> (Join-Path $PSScriptRoot "frontend.log")

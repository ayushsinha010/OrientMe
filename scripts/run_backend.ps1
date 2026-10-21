# Runs the OrientMe Django backend, kept alive by a Windows Scheduled Task
# (see setup_background_tasks.ps1) - restarts automatically on logon or on
# crash, so it survives normal use without a terminal window having to stay
# open.
#
# Paths are relative to this script, so the repository can live anywhere.
# Settings come from the environment / the .env file in the repository root
# (see .env.example).
$root = Split-Path -Parent $PSScriptRoot
Set-Location (Join-Path $root "backend")
python manage.py runserver 8010 *>> (Join-Path $PSScriptRoot "backend.log")

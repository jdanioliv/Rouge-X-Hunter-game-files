# Windows Task Scheduler wrapper (alternative to PM2's scheduler.js).
# Defaults to proposal-only - append -apply to actually write fixes:
#   powershell -File weekly_architect_cleanup.ps1 -apply
# Register with:
#   schtasks /Create /SC WEEKLY /D SUN /ST 03:00 /TN "RougeXHunter-WeeklyCleanup" ^
#     /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"%~dp0weekly_architect_cleanup.ps1\""
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $RepoRoot
node "scripts/routines/weekly_architect_cleanup.js" @args

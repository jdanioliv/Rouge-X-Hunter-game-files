# Windows Task Scheduler wrapper (alternative to PM2's scheduler.js).
# Register with:
#   schtasks /Create /SC DAILY /ST 02:00 /TN "RougeXHunter-NightlyAudit" ^
#     /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"%~dp0nightly_code_audit.ps1\""
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $RepoRoot
node "scripts/routines/nightly_code_audit.js" @args

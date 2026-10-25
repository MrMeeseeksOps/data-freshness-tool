[CmdletBinding()]
param([string]$Root='C:\DataObservability')
. "$PSScriptRoot\..\common.ps1"
try {
    Import-MonitorEnvironment "$Root\config\secrets\monitor.env"
    $release = (Get-Content "$Root\config\current.txt" -Raw).Trim()
    if ($release -notmatch '^[a-zA-Z0-9._-]+$') { throw 'Invalid release pointer.' }
    & "$Root\releases\$release\.venv\Scripts\freshness-monitor.exe" check --all *>> "$Root\logs\evaluator.log"
    exit $LASTEXITCODE
} catch {
    # Do not log exception text; environment and connector details can contain secrets.
    Write-Error 'Evaluator launch failed; inspect protected configuration and release pointer.'
    exit 2
}

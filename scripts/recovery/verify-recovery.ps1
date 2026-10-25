[CmdletBinding()]
param([string]$Root='C:\DataObservability', [string]$GrafanaUrl='http://127.0.0.1:3000')
. "$PSScriptRoot\..\common.ps1"
Import-MonitorEnvironment "$Root\config\secrets\monitor.env"
$release = (Get-Content "$Root\config\current.txt" -Raw).Trim()
if ($release -notmatch '^[a-zA-Z0-9._-]+$') { throw 'Invalid release pointer.' }
Invoke-Native "$Root\releases\$release\.venv\Scripts\freshness-monitor.exe" @('check','--all','--force')
Start-Sleep -Seconds 35
& "$PSScriptRoot\..\deploy\verify-deployment.ps1" -Root $Root -GrafanaUrl $GrafanaUrl
$info = Get-ScheduledTaskInfo DataFreshnessMonitor
Write-Host "Last task result: $($info.LastTaskResult); manually confirm dashboards and notification delivery."

#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$Root='C:\DataObservability')
. "$PSScriptRoot\..\common.ps1"
Assert-Administrator
$target = (Get-Content "$Root\config\previous.txt" -Raw).Trim()
if ($target -notmatch '^[a-zA-Z0-9._-]+$') { throw 'Invalid rollback pointer.' }
$task = Get-ScheduledTask DataFreshnessMonitor -ErrorAction SilentlyContinue
$enabled = $task -and $task.Settings.Enabled
try {
    if ($task) {
        Disable-ScheduledTask DataFreshnessMonitor | Out-Null
        if ((Get-ScheduledTask DataFreshnessMonitor).State -eq 'Running') { throw 'Evaluator is running.' }
    }
    & "$PSScriptRoot\verify-deployment.ps1" -Root $Root -Release $target -ApplicationOnly
    Set-ReleasePointer "$Root\config\current.txt" $target
} finally {
    if ($enabled) { Enable-ScheduledTask DataFreshnessMonitor | Out-Null }
}

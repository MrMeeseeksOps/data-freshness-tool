#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$Root='C:\DataObservability', [Parameter(Mandatory)][string]$ServiceAccount)
. "$PSScriptRoot\..\common.ps1"
Initialize-Root $Root
if (-not $ServiceAccount.EndsWith('$')) { throw 'Use a pre-provisioned domain gMSA (DOMAIN\name$).' }
# gMSA installation and Log on as a batch job must be managed by domain policy.
foreach ($path in 'apps','releases','config') {
    Invoke-Native icacls.exe @("$Root\$path", '/grant:r', "${ServiceAccount}:(OI)(CI)RX")
}
foreach ($path in 'logs','data\textfile') {
    Invoke-Native icacls.exe @("$Root\$path", '/grant:r', "${ServiceAccount}:(OI)(CI)M")
}
$secrets = "$Root\config\secrets"
New-Item -ItemType Directory $secrets -Force | Out-Null
Invoke-Native icacls.exe @($secrets, '/inheritance:r', '/grant:r',
    '*S-1-5-32-544:(OI)(CI)F', '*S-1-5-18:(OI)(CI)F', "${ServiceAccount}:(OI)(CI)RX")
# Stable launcher survives release changes.
Copy-Item "$PSScriptRoot\..\common.ps1" "$Root\apps\common.ps1" -Force
New-Item -ItemType Directory "$Root\apps\run" -Force | Out-Null
Copy-Item "$PSScriptRoot\run-monitor.ps1" "$Root\apps\run\run-monitor.ps1" -Force
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument `
    "-NoProfile -NonInteractive -File `"$Root\apps\run\run-monitor.ps1`" -Root `"$Root`""
$triggers = @(
    (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 15)),
    (New-ScheduledTaskTrigger -AtStartup)
)
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2) -RestartCount 2 -RestartInterval (New-TimeSpan -Minutes 2)
$principal = New-ScheduledTaskPrincipal -UserId $ServiceAccount -LogonType Password -RunLevel Limited
Register-ScheduledTask -TaskName 'DataFreshnessMonitor' -Action $action -Trigger $triggers `
    -Settings $settings -Principal $principal -Force | Out-Null

#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$Root='C:\DataObservability', [Parameter(Mandatory)][string]$Backup)
. "$PSScriptRoot\..\common.ps1"
Assert-Administrator
$Backup = (Resolve-Path $Backup).Path
$manifest = Get-Content "$Backup\manifest.json" -Raw | ConvertFrom-Json
foreach ($item in $manifest) {
    $path = [IO.Path]::GetFullPath((Join-Path $Backup $item.Path))
    if (-not $path.StartsWith("$Backup\", [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe manifest path.' }
    if ((Get-FileHash $path -Algorithm SHA256).Hash -ne $item.Hash) { throw 'Backup integrity failed.' }
}
# Fail rather than overwrite existing persistent state. Use a clean replacement host/root.
if (Test-Path "$Root\data\grafana\grafana.db") { throw 'Existing Grafana data: restore to a clean host.' }
if (Test-Path "$Root\data\prometheus\wal") { throw 'Existing TSDB: restore to a clean host.' }
foreach ($name in 'FreshnessPrometheus','FreshnessGrafana') {
    $service = Get-Service $name -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq 'Running') { throw 'Stop monitoring services before restore.' }
}
$task = Get-ScheduledTask DataFreshnessMonitor -ErrorAction SilentlyContinue
if ($task -and $task.State -eq 'Running') { throw 'Evaluator is running.' }
if ($task) { Disable-ScheduledTask DataFreshnessMonitor | Out-Null }
Initialize-Root $Root
foreach ($path in 'config','data','releases','apps\services') {
    if (Test-Path "$Backup\$path") {
        New-Item -ItemType Directory "$Root\$path" -Force | Out-Null
        & robocopy.exe "$Backup\$path" "$Root\$path" /E /COPY:DAT /R:2 /W:1
        if ($LASTEXITCODE -ge 8) { throw 'Restore copy failed.' }
    }
}
Write-Host 'Restore complete. Reinstall pinned dependencies, restore secrets, configure services, and register the gMSA task before verification.'

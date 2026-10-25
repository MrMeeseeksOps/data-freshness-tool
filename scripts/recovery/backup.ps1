#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$Root='C:\DataObservability', [string]$Destination)
. "$PSScriptRoot\..\common.ps1"
Assert-Administrator
if (-not $Destination) { $Destination = "$Root\backups\$(Get-Date -Format yyyyMMddHHmmss)" }
if (Test-Path $Destination) { throw 'Backup destination must be new.' }
# Offline backup: stop writers for consistent SQLite and TSDB files.
$running = @(Get-Service FreshnessPrometheus,FreshnessGrafana | Where-Object Status -eq Running)
$task = Get-ScheduledTask DataFreshnessMonitor -ErrorAction SilentlyContinue
$enabled = $task -and $task.Settings.Enabled
try {
    if ($task) {
        Disable-ScheduledTask DataFreshnessMonitor | Out-Null
        if ((Get-ScheduledTask DataFreshnessMonitor).State -eq 'Running') { throw 'Wait for evaluator completion.' }
    }
    $running | Stop-Service -Force
    New-Item -ItemType Directory $Destination | Out-Null
    $Destination = (Resolve-Path $Destination).Path
    Invoke-Native icacls.exe @($Destination, '/inheritance:r', '/grant:r',
        '*S-1-5-32-544:(OI)(CI)F', '*S-1-5-18:(OI)(CI)F')
    foreach ($path in 'config','data','releases','apps\services') {
        $target = Join-Path $Destination $path
        New-Item -ItemType Directory $target -Force | Out-Null
        # Never include secrets: restore them through the approved secret provider.
        & robocopy.exe "$Root\$path" $target /E /COPY:DAT /R:2 /W:1 /XD "$Root\config\secrets" /XF *.p8 *.pem *.key
        if ($LASTEXITCODE -ge 8) { throw 'Backup copy failed.' }
    }
    if ($task) { Export-ScheduledTask DataFreshnessMonitor | Set-Content "$Destination\task.xml" }
    Get-CimInstance Win32_Service | Where-Object Name -in @('FreshnessPrometheus','FreshnessGrafana','windows_exporter') |
        Select-Object Name,PathName,StartName,StartMode | ConvertTo-Json | Set-Content "$Destination\services.json"
    $manifest = Get-ChildItem $Destination -File -Recurse | ForEach-Object {
        @{Path=$_.FullName.Substring($Destination.Length).TrimStart('\'); Hash=(Get-FileHash $_.FullName -Algorithm SHA256).Hash}
    }
    ConvertTo-Json -InputObject @($manifest) -Depth 4 | Set-Content "$Destination\manifest.json"
    Write-Host "Backup complete: $Destination. Replicate encrypted to off-host storage."
} finally {
    $running | Start-Service
    if ($enabled) { Enable-ScheduledTask DataFreshnessMonitor | Out-Null }
}

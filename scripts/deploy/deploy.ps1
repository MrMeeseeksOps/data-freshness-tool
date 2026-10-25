#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$Root='C:\DataObservability', [Parameter(Mandatory)][string]$Artifact,
      [Parameter(Mandatory)][string]$Version, [string]$GrafanaUrl='http://127.0.0.1:3000')
. "$PSScriptRoot\..\common.ps1"
Initialize-Root $Root
if ($Version -notmatch '^[a-zA-Z0-9._-]+$') { throw 'Invalid version.' }
$destination = "$Root\releases\$Version"
if (Test-Path $destination) { throw 'Release directories are immutable; use a new version.' }
Start-Transcript "$Root\logs\deploy-$Version.log"
$task = Get-ScheduledTask -TaskName DataFreshnessMonitor -ErrorAction SilentlyContinue
$wasEnabled = $task -and $task.Settings.Enabled
$previous = $null
$switched = $false
try {
    if ($task) {
        Disable-ScheduledTask DataFreshnessMonitor | Out-Null
        if ((Get-ScheduledTask DataFreshnessMonitor).State -eq 'Running') {
            throw 'Wait for the active evaluator to finish before deploying.'
        }
    }
    New-Item -ItemType Directory $destination | Out-Null
    Expand-Archive -Path $Artifact -DestinationPath $destination
    $python = (Get-Content "$Root\config\python.txt" -Raw).Trim()
    Invoke-Native $python @('-m','venv',"$destination\.venv")
    $wheels = @(Get-ChildItem "$destination\wheelhouse\snowflake_freshness_monitor-*.whl")
    if ($wheels.Count -ne 1) { throw 'Artifact must contain exactly one application wheel.' }
    Invoke-Native "$destination\.venv\Scripts\python.exe" @('-m','pip','install','--no-index',
        '--find-links',"$destination\wheelhouse",$wheels[0].FullName)
    Invoke-Native "$destination\.venv\Scripts\python.exe" @('-m','pip','check')
    # Grant the existing task identity access to the new release before activation.
    if ($task) {
        $identity = $task.Principal.UserId
        Invoke-Native icacls.exe @($destination, '/grant:r', "${identity}:(OI)(CI)RX")
    }
    & "$PSScriptRoot\verify-deployment.ps1" -Root $Root -Release $Version -ApplicationOnly
    if (Test-Path "$Root\config\current.txt") {
        $previous = (Get-Content "$Root\config\current.txt" -Raw).Trim()
    }
    Set-ReleasePointer "$Root\config\current.txt" $Version
    $switched = $true
    Import-MonitorEnvironment "$Root\config\secrets\monitor.env"
    Invoke-Native "$destination\.venv\Scripts\freshness-monitor.exe" @('check','--all','--force')
    # Wait for two 30-second scrape opportunities before verifying ingestion.
    $ready = $false
    for ($attempt=0; $attempt -lt 8; $attempt++) {
        try {
            & "$PSScriptRoot\verify-deployment.ps1" -Root $Root -Release $Version -GrafanaUrl $GrafanaUrl
            $ready = $true
            break
        } catch { Start-Sleep -Seconds 10 }
    }
    if (-not $ready) { throw 'Candidate health verification failed.' }
    if ($previous) { Set-ReleasePointer "$Root\config\previous.txt" $previous }
} catch {
    if ($switched -and $previous) { Set-ReleasePointer "$Root\config\current.txt" $previous }
    elseif ($switched) { Remove-Item "$Root\config\current.txt" }
    throw
} finally {
    if ($wasEnabled) { Enable-ScheduledTask DataFreshnessMonitor | Out-Null }
    Stop-Transcript
}

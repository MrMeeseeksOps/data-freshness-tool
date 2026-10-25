[CmdletBinding()]
param([string]$Root='C:\DataObservability', [string]$Release,
      [switch]$ApplicationOnly, [string]$GrafanaUrl='http://127.0.0.1:3000')
. "$PSScriptRoot\..\common.ps1"
Import-MonitorEnvironment "$Root\config\secrets\monitor.env"
if (-not $Release) { $Release = (Get-Content "$Root\config\current.txt" -Raw).Trim() }
if ($Release -notmatch '^[a-zA-Z0-9._-]+$') { throw 'Invalid release.' }
$cli = "$Root\releases\$Release\.venv\Scripts\freshness-monitor.exe"
Invoke-Native $cli @('version')
Invoke-Native $cli @('test-connection')
Invoke-Native $cli @('validate-config')
Invoke-Native $cli @('check','--all','--force','--dry-run')
if (-not $ApplicationOnly) {
    foreach ($service in 'FreshnessPrometheus','FreshnessGrafana','windows_exporter') {
        if ((Get-Service $service).Status -ne 'Running') { throw "Service down: $service" }
    }
    foreach ($url in @('http://127.0.0.1:9090/-/ready', "$GrafanaUrl/api/health",
                       'http://127.0.0.1:9182/metrics')) {
        if ((Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 30).StatusCode -ne 200) {
            throw 'Monitoring endpoint failed.'
        }
    }
    $metrics = "$Root\data\textfile\freshness.prom"
    if (-not (Test-Path $metrics) -or ((Get-Date) - (Get-Item $metrics).LastWriteTime).TotalMinutes -gt 30) {
        throw 'Metrics are missing or older than 30 minutes.'
    }
    $query = [Uri]::EscapeDataString('data_freshness_evaluator_last_success_timestamp_seconds')
    $response = Invoke-RestMethod "http://127.0.0.1:9090/api/v1/query?query=$query"
    if ($response.status -ne 'success' -or $response.data.result.Count -eq 0) {
        throw 'Prometheus has not ingested evaluator metrics.'
    }
    $stamp = [double]$response.data.result[0].value[1]
    if ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $stamp -gt 1800) {
        throw 'Prometheus evaluator heartbeat is stale.'
    }
}
Write-Host 'Deployment verification passed.'

#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$Root='C:\DataObservability', [string]$WinSWVersion='2.12.0',
      [Parameter(Mandatory)][string]$WinSWSha256,
      [string]$GrafanaAddress='127.0.0.1', [string]$GrafanaAllowedSubnet='127.0.0.1')
. "$PSScriptRoot\..\common.ps1"
Initialize-Root $Root
if ($GrafanaAddress -in @('0.0.0.0','::','*')) { throw 'Choose a specific internal address.' }
$wrapper = "$Root\downloads\winsw-$WinSWVersion.exe"
Get-VerifiedDownload "https://github.com/winsw/winsw/releases/download/v$WinSWVersion/WinSW-x64.exe" $wrapper $WinSWSha256
$prometheus = (Get-Content "$Root\config\prometheus.txt" -Raw).Trim()
$grafana = (Get-Content "$Root\config\grafana.txt" -Raw).Trim()
foreach ($path in 'data\prometheus','data\grafana','apps\services') {
    New-Item -ItemType Directory "$Root\$path" -Force | Out-Null
}
@"
[server]
http_addr = $GrafanaAddress
http_port = 3000
[paths]
data = $Root\data\grafana
logs = $Root\logs
provisioning = $Root\config\grafana\provisioning
[users]
allow_sign_up = false
[auth.anonymous]
enabled = false
[analytics]
reporting_enabled = false
check_for_updates = false
"@ | Set-Content "$Root\config\grafana.ini"
# Relocate dashboard provider for configurable roots.
$dashboardPath = ($Root -replace '\\','/') + '/config/grafana/dashboards'
$provider = "$Root\config\grafana\provisioning\dashboards\freshness.yml"
(Get-Content $provider -Raw) -replace 'path: .*', "path: '$dashboardPath'" | Set-Content $provider
$services = @(
    @{Name='FreshnessPrometheus'; Exe="$prometheus\prometheus.exe"; Working=$prometheus;
      Args="--config.file=`"$Root\config\prometheus\prometheus.yml`" --storage.tsdb.path=`"$Root\data\prometheus`" --storage.tsdb.retention.time=30d --web.listen-address=127.0.0.1:9090"},
    @{Name='FreshnessGrafana'; Exe="$grafana\bin\grafana.exe"; Working=$grafana;
      Args="server --homepath=`"$grafana`" --config=`"$Root\config\grafana.ini`""}
)
foreach ($service in $services) {
    $name = $service.Name
    $exe = "$Root\apps\services\$name.exe"
    $existing = Get-Service $name -ErrorAction SilentlyContinue
    if ($existing) { Stop-Service $name -Force }
    Copy-Item $wrapper $exe -Force
    $escapedExe = [Security.SecurityElement]::Escape($service.Exe)
    $escapedArgs = [Security.SecurityElement]::Escape($service.Args)
    $escapedRoot = [Security.SecurityElement]::Escape($Root)
    $escapedWorking = [Security.SecurityElement]::Escape($service.Working)
@"
<service>
 <id>$name</id><name>$name</name><description>Data Observability $name</description>
 <executable>$escapedExe</executable><arguments>$escapedArgs</arguments>
 <workingdirectory>$escapedWorking</workingdirectory>
 <logpath>$escapedRoot\logs</logpath><log mode="roll" />
 <startmode>Automatic</startmode>
 <serviceaccount><username>NT AUTHORITY\LocalService</username></serviceaccount>
 <onfailure action="restart" delay="10 sec" /><resetfailure>1 hour</resetfailure>
</service>
"@ | Set-Content "$Root\apps\services\$name.xml"
    if (-not $existing) { Invoke-Native $exe @('install') }
}
foreach ($path in 'apps','config') {
    Invoke-Native icacls.exe @("$Root\$path", '/grant:r', '*S-1-5-19:(OI)(CI)RX')
}
foreach ($path in 'data\grafana','data\prometheus','logs') {
    Invoke-Native icacls.exe @("$Root\$path", '/grant:r', '*S-1-5-19:(OI)(CI)M')
}
# Secrets receive a separate ACL in register-scheduled-task; LocalService cannot read them.
New-NetFirewallRule -Name 'DataObservability-Grafana' -DisplayName 'Internal Grafana' -Direction Inbound `
    -Protocol TCP -LocalPort 3000 -LocalAddress $GrafanaAddress -RemoteAddress $GrafanaAllowedSubnet `
    -Action Allow -Profile Domain -ErrorAction SilentlyContinue | Out-Null
Set-NetFirewallRule -Name 'DataObservability-Grafana' -LocalAddress $GrafanaAddress -RemoteAddress $GrafanaAllowedSubnet
Start-Service FreshnessPrometheus,FreshnessGrafana

#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$Root='C:\DataObservability',
      [Parameter(Mandatory)][string]$ChecksumsFile,
      [string]$GrafanaAddress='127.0.0.1', [string]$GrafanaAllowedSubnet='127.0.0.1')
. "$PSScriptRoot\..\common.ps1"
Initialize-Root $Root
Start-Transcript "$Root\logs\install-$(Get-Date -Format yyyyMMddHHmmss).log"
try {
    $hashes = Get-Content $ChecksumsFile -Raw | ConvertFrom-Json
    & "$PSScriptRoot\install-python.ps1" -Root $Root -Sha256 $hashes.python
    & "$PSScriptRoot\install-prometheus.ps1" -Root $Root -Sha256 $hashes.prometheus
    & "$PSScriptRoot\install-grafana.ps1" -Root $Root -Sha256 $hashes.grafana
    $source = Resolve-Path "$PSScriptRoot\..\..\config"
    foreach ($name in 'prometheus','grafana','windows-exporter') {
        if (-not (Test-Path "$Root\config\$name")) { Copy-Item "$source\$name" "$Root\config\$name" -Recurse }
    }
    & "$PSScriptRoot\install-windows-exporter.ps1" -Root $Root -Sha256 $hashes.windows_exporter
    & "$PSScriptRoot\configure-services.ps1" -Root $Root -WinSWSha256 $hashes.winsw `
        -GrafanaAddress $GrafanaAddress -GrafanaAllowedSubnet $GrafanaAllowedSubnet
} finally { Stop-Transcript }

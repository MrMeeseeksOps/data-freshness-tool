#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$Root='C:\DataObservability', [string]$Version='3.5.0',
      [Parameter(Mandatory)][string]$Sha256)
. "$PSScriptRoot\..\common.ps1"
Initialize-Root $Root
$zip = "$Root\downloads\prometheus-$Version.zip"
Get-VerifiedDownload "https://github.com/prometheus/prometheus/releases/download/v$Version/prometheus-$Version.windows-amd64.zip" $zip $Sha256
$target = "$Root\apps\prometheus-$Version.windows-amd64"
if (-not (Test-Path "$target\prometheus.exe")) { Expand-Archive $zip "$Root\apps" -Force }
[IO.File]::WriteAllText("$Root\config\prometheus.txt", $target)

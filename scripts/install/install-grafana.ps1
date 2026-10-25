#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$Root='C:\DataObservability', [string]$Version='12.1.0',
      [Parameter(Mandatory)][string]$Sha256)
. "$PSScriptRoot\..\common.ps1"
Initialize-Root $Root
$zip = "$Root\downloads\grafana-$Version.zip"
Get-VerifiedDownload "https://dl.grafana.com/oss/release/grafana-$Version.windows-amd64.zip" $zip $Sha256
$target = "$Root\apps\grafana-$Version"
if (-not (Test-Path "$target\bin\grafana.exe")) {
    $staging = "$Root\downloads\grafana-$Version-expanded"
    Expand-Archive $zip $staging -Force
    $binaries = @(Get-ChildItem $staging -Recurse -Filter grafana.exe | Where-Object { $_.Directory.Name -eq 'bin' })
    if ($binaries.Count -ne 1) { throw 'Unexpected Grafana archive layout.' }
    Move-Item $binaries[0].Directory.Parent.FullName $target
}
if (-not (Test-Path "$target\bin\grafana.exe")) { throw 'Unexpected Grafana archive layout.' }
[IO.File]::WriteAllText("$Root\config\grafana.txt", $target)

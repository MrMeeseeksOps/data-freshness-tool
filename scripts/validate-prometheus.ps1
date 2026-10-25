[CmdletBinding()]
param([string]$Version='3.5.0', [string]$Cache="$env:TEMP\freshness-prometheus-validation")
. "$PSScriptRoot\common.ps1"
New-Item -ItemType Directory $Cache -Force | Out-Null
$base = "https://github.com/prometheus/prometheus/releases/download/v$Version"
$file = "prometheus-$Version.windows-amd64.zip"
$checksums = (Invoke-WebRequest "$base/sha256sums.txt" -UseBasicParsing).Content
$line = @($checksums -split "`n" | Where-Object { $_.Trim().EndsWith($file) })
if ($line.Count -ne 1) { throw 'Vendor checksum not found.' }
$hash = ($line[0].Trim() -split '\s+')[0]
Get-VerifiedDownload "$base/$file" "$Cache\$file" $hash
Expand-Archive "$Cache\$file" $Cache -Force
$tool = "$Cache\prometheus-$Version.windows-amd64\promtool.exe"
Invoke-Native $tool @('check','config',"$PSScriptRoot\..\config\prometheus\prometheus.yml")
Invoke-Native $tool @('test','rules',"$PSScriptRoot\..\tests\prometheus-rules.yml")

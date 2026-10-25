#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$Root='C:\DataObservability', [string]$Version='0.31.3',
      [Parameter(Mandatory)][string]$Sha256)
. "$PSScriptRoot\..\common.ps1"
Initialize-Root $Root
$msi = "$Root\downloads\windows-exporter-$Version.msi"
Get-VerifiedDownload "https://github.com/prometheus-community/windows_exporter/releases/download/v$Version/windows_exporter-$Version-amd64.msi" $msi $Sha256
$installed = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' |
    Where-Object { $_.PSObject.Properties.Name -contains 'DisplayName' -and $_.DisplayName -eq 'windows_exporter' }
if (-not ($installed | Where-Object { $_.DisplayVersion -eq $Version })) {
    $arguments = @('/i', "`"$msi`"", '/qn', '/norestart',
        'ENABLED_COLLECTORS=cpu,memory,logical_disk,os,system,service,textfile',
        'LISTEN_ADDR=127.0.0.1', 'LISTEN_PORT=9182', "TEXTFILE_DIRS=`"$Root\data\textfile`"",
        'ADDLOCAL=ALL', 'REMOVE=FirewallException', '/L*v', "`"$Root\logs\exporter-install.log`"")
    $process = Start-Process msiexec.exe -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -notin @(0,3010)) { throw "Exporter install failed: $($process.ExitCode)" }
}
Invoke-Native sc.exe @('config','windows_exporter','obj=','NT AUTHORITY\LocalService','start=','auto')
Invoke-Native icacls.exe @("$Root\data\textfile", '/grant:r', '*S-1-5-19:(OI)(CI)RX')
Invoke-Native sc.exe @('failure','windows_exporter','reset=','86400','actions=','restart/5000/restart/10000/restart/30000')
Restart-Service windows_exporter

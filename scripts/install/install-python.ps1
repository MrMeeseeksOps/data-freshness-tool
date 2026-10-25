#Requires -RunAsAdministrator
[CmdletBinding()]
param([string]$Root='C:\DataObservability', [string]$Version='3.12.10',
      [Parameter(Mandatory)][string]$Sha256)
. "$PSScriptRoot\..\common.ps1"
Initialize-Root $Root
$installer = "$Root\downloads\python-$Version.exe"
Get-VerifiedDownload "https://www.python.org/ftp/python/$Version/python-$Version-amd64.exe" $installer $Sha256
$signature = Get-AuthenticodeSignature $installer
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Python Software Foundation') {
    throw 'Python installer signature validation failed.'
}
$target = "$Root\apps\python-$Version"
if (-not (Test-Path "$target\python.exe")) {
    $process = Start-Process $installer -ArgumentList @('/quiet','InstallAllUsers=1',
        "TargetDir=`"$target`"",'PrependPath=0','Include_test=0') -Wait -PassThru
    if ($process.ExitCode -notin @(0,3010)) { throw "Python install failed: $($process.ExitCode)" }
}
Invoke-Native "$target\python.exe" @('--version')
[IO.File]::WriteAllText("$Root\config\python.txt", "$target\python.exe")

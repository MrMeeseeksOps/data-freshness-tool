Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]$identity).IsInRole('Administrators')) {
        throw 'Run this script in an elevated PowerShell session.'
    }
}
function Invoke-Native {
    param([string]$File, [string[]]$Arguments)
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$File failed with exit code $LASTEXITCODE" }
}
function Initialize-Root {
    param([string]$Root)
    Assert-Administrator
    foreach ($directory in 'apps','config','data','logs','backups','releases','downloads','data\textfile') {
        New-Item -ItemType Directory -Path (Join-Path $Root $directory) -Force | Out-Null
    }
    # Remove inherited broad access; grant built-in administrators and SYSTEM only.
    Invoke-Native icacls.exe @($Root, '/inheritance:r', '/grant:r',
        '*S-1-5-32-544:(OI)(CI)F', '*S-1-5-18:(OI)(CI)F')
}
function Get-VerifiedDownload {
    param([string]$Url, [string]$Destination, [string]$Sha256)
    if ($Sha256 -notmatch '^[a-fA-F0-9]{64}$') {
        throw 'A trusted vendor SHA256 is required. Obtain it independently before installation.'
    }
    if (-not $Url.StartsWith('https://')) { throw 'Downloads require HTTPS.' }
    if (Test-Path $Destination) {
        if ((Get-FileHash $Destination -Algorithm SHA256).Hash -eq $Sha256) { return }
    }
    Write-Host "Downloading verified dependency: $Url"
    Invoke-WebRequest -Uri $Url -OutFile "$Destination.partial" -UseBasicParsing
    if ((Get-FileHash "$Destination.partial" -Algorithm SHA256).Hash -ne $Sha256) {
        throw "SHA256 mismatch: $Destination.partial"
    }
    Move-Item "$Destination.partial" $Destination -Force
}
function Import-MonitorEnvironment {
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw 'Protected monitor.env is missing.' }
    foreach ($line in Get-Content $Path) {
        if ($line -match '^\s*(#|$)') { continue }
        if ($line -notmatch '^(FRESHNESS_[A-Z_]+)=(.*)$') { throw 'Invalid environment file line.' }
        [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
    }
}
function Set-ReleasePointer {
    param([string]$Path, [string]$Release)
    [IO.File]::WriteAllText("$Path.new", $Release)
    if (Test-Path $Path) { [IO.File]::Replace("$Path.new", $Path, $null) }
    else { [IO.File]::Move("$Path.new", $Path) }
}

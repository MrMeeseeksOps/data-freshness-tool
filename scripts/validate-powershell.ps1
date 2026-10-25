$ErrorActionPreference = 'Stop'
$failures = @()
Get-ChildItem "$PSScriptRoot\..\scripts" -Recurse -Filter *.ps1 | ForEach-Object {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    $failures += $errors
}
if ($failures.Count) { $failures | Format-List; throw 'PowerShell syntax validation failed.' }
Write-Host 'All PowerShell scripts parsed successfully.'

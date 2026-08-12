[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z]:\\')]
    [string]$DataRoot = 'D:\AIData',
    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AIData.Common.psm1') -Force

$fullRoot = Get-AIDataFullPath $DataRoot
$folders = @('Data', 'Cache', 'Temp', 'Tools', 'Reports') | ForEach-Object { Join-Path $fullRoot $_ }

if (-not $Execute) {
    [pscustomobject]@{
        Status = 'AuditOnly'
        DataRoot = $fullRoot
        FoldersToCreate = $folders
        NextStep = "Run again with -Execute after confirming this is a dedicated data-drive folder."
    } | ConvertTo-Json -Depth 3
    exit 0
}

New-AIDataPrivateRoot $fullRoot
foreach ($folder in $folders) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }

[pscustomobject]@{
    Status = 'Initialized'
    DataRoot = $fullRoot
    Folders = $folders
    Note = 'No application data was moved. Run Invoke-AIDataProfileMove.ps1 for one closed tool at a time.'
} | ConvertTo-Json -Depth 3

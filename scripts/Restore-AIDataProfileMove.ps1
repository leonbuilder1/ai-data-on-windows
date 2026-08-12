[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ReceiptPath,
    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AIData.Common.psm1') -Force

if (-not (Test-Path -LiteralPath $ReceiptPath -PathType Leaf)) { throw "Receipt does not exist: $ReceiptPath" }
$receipt = Get-Content -LiteralPath $ReceiptPath -Raw | ConvertFrom-Json
if ($receipt.Schema -ne 1 -or $receipt.Status -ne 'AwaitingValidation') { throw 'Receipt is not an active move receipt.' }

if (-not $Execute) {
    [pscustomobject]@{ Status = 'AuditOnly'; Tool = $receipt.Tool; Entries = $receipt.Entries; NextStep = 'Close the tool, then add -Execute to restore the C profile path. D data is retained.' } | ConvertTo-Json -Depth 6
    exit 0
}

Assert-AIDataNoProfileProcess -SourcePaths @($receipt.Entries | ForEach-Object { $_.Source; $_.Destination })
$rollbackEntries = @($receipt.Entries)
[Array]::Reverse($rollbackEntries)
foreach ($entry in $rollbackEntries) {
    if (-not (Test-AIDataJunction -Source $entry.Source -Destination $entry.Destination)) { throw "Expected D junction is not healthy: $($entry.Source)" }
    if (-not (Test-Path -LiteralPath $entry.PreMove -PathType Container)) { throw "C pre-move directory is missing: $($entry.PreMove)" }
    Remove-AIDataJunctionOnly $entry.Source
    Rename-Item -LiteralPath $entry.PreMove -NewName (Split-Path -Leaf $entry.Source)
}
foreach ($property in $receipt.OriginalUserEnvironment.PSObject.Properties) {
    Set-AIDataUserEnvironment -Name $property.Name -Value $property.Value.Value
}
[pscustomobject]@{ Status = 'RolledBack'; Receipt = $ReceiptPath; Note = 'The D copy remains intact and was not deleted.' } | ConvertTo-Json -Depth 4

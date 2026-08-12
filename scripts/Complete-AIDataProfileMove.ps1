[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ReceiptPath,
    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AIData.Common.psm1') -Force

function Remove-AIDataTreeNoFollow([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Pre-move tree contains a reparse point; stop for review: $Path" }
    foreach ($child in @(Get-ChildItem -LiteralPath $Path -Force)) {
        if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Pre-move tree contains a reparse point; stop for review: $($child.FullName)" }
        if ($child.PSIsContainer) { Remove-AIDataTreeNoFollow $child.FullName } else { [IO.File]::Delete($child.FullName) }
    }
    [IO.Directory]::Delete($Path, $false)
}

if (-not (Test-Path -LiteralPath $ReceiptPath -PathType Leaf)) { throw "Receipt does not exist: $ReceiptPath" }
$receipt = Get-Content -LiteralPath $ReceiptPath -Raw | ConvertFrom-Json
if ($receipt.Schema -ne 1 -or $receipt.Status -ne 'AwaitingValidation') { throw 'Receipt is not an active move receipt.' }
foreach ($entry in $receipt.Entries) {
    if (-not (Test-AIDataJunction -Source $entry.Source -Destination $entry.Destination)) { throw "Expected D junction is not healthy: $($entry.Source)" }
    if (-not (Test-Path -LiteralPath $entry.PreMove -PathType Container)) { throw "C pre-move directory is missing: $($entry.PreMove)" }
}

if (-not $Execute) {
    [pscustomobject]@{ Status = 'AuditOnly'; Tool = $receipt.Tool; PreMoveDirectories = @($receipt.Entries | ForEach-Object PreMove); NextStep = 'Run only after manual application acceptance; add -Execute to permanently remove these C pre-move directories.' } | ConvertTo-Json -Depth 6
    exit 0
}

Assert-AIDataNoProfileProcess -SourcePaths @($receipt.Entries | ForEach-Object { $_.Source; $_.Destination })
foreach ($entry in $receipt.Entries) { Remove-AIDataTreeNoFollow $entry.PreMove }
$completionPath = Join-Path (Split-Path -Parent $ReceiptPath) 'cleanup-complete.json'
[pscustomobject]@{ Status = 'CleanupCompleted'; SourceReceipt = $ReceiptPath; CompletedAt = (Get-Date).ToString('o'); Removed = @($receipt.Entries | ForEach-Object PreMove) } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $completionPath -Encoding utf8NoBOM
Get-Content -LiteralPath $completionPath -Raw

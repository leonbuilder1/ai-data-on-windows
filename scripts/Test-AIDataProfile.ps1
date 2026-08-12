[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Codex', 'ClaudeCode', 'Cursor')]
    [string]$Tool,

    [ValidatePattern('^[A-Za-z]:\\')]
    [string]$DataRoot = 'D:\AIData',

    [string]$ReceiptPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AIData.Common.psm1') -Force

$root = Get-AIDataFullPath $DataRoot
if ($ReceiptPath) {
    if (-not (Test-Path -LiteralPath $ReceiptPath -PathType Leaf)) { throw "Receipt does not exist: $ReceiptPath" }
    $receipt = Get-Content -LiteralPath $ReceiptPath -Raw | ConvertFrom-Json
    if ($receipt.Schema -ne 1 -or $receipt.Status -ne 'AwaitingValidation' -or $receipt.Tool -ne $Tool) {
        throw 'Receipt is not an active receipt for the selected tool.'
    }
    if ((Get-AIDataFullPath $receipt.DataRoot) -ine $root) { throw 'Receipt data root does not match -DataRoot.' }
    $entries = @($receipt.Entries)
    $environment = [ordered]@{}
    foreach ($property in $receipt.AppliedUserEnvironment.PSObject.Properties) { $environment[$property.Name] = [string]$property.Value }
} else {
    $profile = Get-AIDataProfile -Tool $Tool -DataRoot $root
    $entries = @($profile.Entries)
    $environment = $profile.Environment
}
$checks = [Collections.Generic.List[object]]::new()
foreach ($entry in $entries) {
    $ok = Test-AIDataJunction -Source $entry.Source -Destination $entry.Destination
    $checks.Add([pscustomobject]@{ Check = "$($entry.Name) junction"; Passed = $ok; Source = $entry.Source; Destination = $entry.Destination })
    if (-not $ok) { throw "Expected junction is not healthy: $($entry.Source)" }
    $checks.Add([pscustomobject]@{ Check = "$($entry.Name) target summary"; Passed = $true; Summary = (Get-AIDataTreeSummary $entry.Destination) })
}
foreach ($name in $environment.Keys) {
    $actual = Get-AIDataUserEnvironment $name
    $ok = $actual.Exists -and $actual.Value -ieq $environment[$name]
    $checks.Add([pscustomobject]@{ Check = "$name user environment"; Passed = $ok; Expected = $environment[$name]; Actual = $actual.Value })
    if (-not $ok) { throw "User environment does not match expected value: $name" }
}

[pscustomobject]@{
    Status = 'PlacementVerified'
    Tool = $Tool
    DataRoot = $root
    Receipt = $ReceiptPath
    Checks = @($checks)
    ManualAcceptance = 'Open the selected tool in a new process and verify login, settings, extensions/plugins, one existing session/project, and one new write. Keep the C pre-move directory until this passes.'
} | ConvertTo-Json -Depth 6

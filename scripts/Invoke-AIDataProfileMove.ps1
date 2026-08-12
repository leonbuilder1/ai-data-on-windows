[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Codex', 'ClaudeCode', 'Cursor')]
    [string]$Tool,

    [ValidatePattern('^[A-Za-z]:\\')]
    [string]$DataRoot = 'D:\AIData',

    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AIData.Common.psm1') -Force

function Write-AIDataJson([string]$Path, $Value) {
    $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
}

$fullRoot = Get-AIDataFullPath $DataRoot
$profile = Get-AIDataProfile -Tool $Tool -DataRoot $fullRoot
$entryAudit = foreach ($entry in $profile.Entries) {
    [pscustomobject]@{
        Name = $entry.Name
        Source = $entry.Source
        Destination = $entry.Destination
        SourceExists = Test-Path -LiteralPath $entry.Source -PathType Container
        DestinationExists = Test-Path -LiteralPath $entry.Destination
        SourceIsJunction = if (Test-Path -LiteralPath $entry.Source) { Test-AIDataReparsePoint $entry.Source } else { $false }
    }
}

if (-not $Execute) {
    [pscustomobject]@{
        Status = 'AuditOnly'
        Tool = $Tool
        DataRoot = $fullRoot
        Entries = $entryAudit
        UserEnvironmentToSet = $profile.Environment
        Required = @('Close the selected tool and all of its terminals.', 'Initialize the data root first.', 'Review source and destination paths, then add -Execute.')
    } | ConvertTo-Json -Depth 6
    exit 0
}

New-AIDataPrivateRoot $fullRoot
$reportDirectory = Join-Path $fullRoot ('Reports\{0}-{1}' -f $Tool, (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
$stamp = Split-Path $reportDirectory -Leaf
$environmentBefore = [ordered]@{}
$renamedEntries = [Collections.Generic.List[object]]::new()

try {
    foreach ($entry in $profile.Entries) {
        Assert-AIDataChildPath -CandidatePath $entry.Destination -ParentPath $fullRoot
        Assert-AIDataOrdinaryDirectory $entry.Source
        Assert-AIDataNoNestedReparsePoints $entry.Source
        if (Test-Path -LiteralPath $entry.Destination) { throw "Destination already exists; refusing to merge: $($entry.Destination)" }
    }
    Assert-AIDataNoProfileProcess -SourcePaths @($profile.Entries | ForEach-Object Source)

    foreach ($entry in $profile.Entries) {
        $entry | Add-Member -NotePropertyName SourceSummary -NotePropertyValue (Get-AIDataTreeSummary $entry.Source)
        $destinationParent = Split-Path -LiteralPath $entry.Destination -Parent
        New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
        Invoke-AIDataRoboCopy -Source $entry.Source -Destination $entry.Destination -LogPath (Join-Path $reportDirectory ("copy-{0}.log" -f $entry.Name))
        $entry | Add-Member -NotePropertyName DestinationSummary -NotePropertyValue (Get-AIDataTreeSummary $entry.Destination)
        Assert-AIDataTreeSummaryEqual -Source $entry.SourceSummary -Destination $entry.DestinationSummary -Label $entry.Name
    }

    foreach ($name in $profile.Environment.Keys) { $environmentBefore[$name] = Get-AIDataUserEnvironment $name }
    foreach ($entry in $profile.Entries) {
        Assert-AIDataNoProfileProcess -SourcePaths @($profile.Entries | ForEach-Object Source)
        $sourceItem = Get-Item -LiteralPath $entry.Source -Force
        $preMove = Join-Path $sourceItem.Parent.FullName ('{0}.pre-ai-data-{1}' -f $sourceItem.Name, $stamp)
        if (Test-Path -LiteralPath $preMove) { throw "Rollback path already exists: $preMove" }
        Rename-Item -LiteralPath $entry.Source -NewName (Split-Path -Leaf $preMove)
        New-Item -ItemType Junction -Path $entry.Source -Target $entry.Destination | Out-Null
        if (-not (Test-AIDataJunction -Source $entry.Source -Destination $entry.Destination)) {
            throw "Junction verification failed: $($entry.Source)"
        }
        $renamedEntries.Add([pscustomobject]@{ Name = $entry.Name; Source = $entry.Source; Destination = $entry.Destination; PreMove = $preMove; SourceSummary = $entry.SourceSummary; DestinationSummary = $entry.DestinationSummary })
    }

    foreach ($value in $profile.Environment.Values) {
        Assert-AIDataChildPath -CandidatePath $value -ParentPath $fullRoot
        New-Item -ItemType Directory -Path $value -Force | Out-Null
    }
    foreach ($name in $profile.Environment.Keys) { Set-AIDataUserEnvironment -Name $name -Value $profile.Environment[$name] }

    $receipt = [ordered]@{
        Schema = 1
        Status = 'AwaitingValidation'
        Tool = $Tool
        DataRoot = $fullRoot
        CreatedAt = (Get-Date).ToString('o')
        Entries = @($renamedEntries)
        OriginalUserEnvironment = $environmentBefore
        AppliedUserEnvironment = $profile.Environment
        ValidationCommand = "pwsh -NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\Test-AIDataProfile.ps1`" -Tool $Tool -DataRoot `"$fullRoot`" -ReceiptPath `"$reportDirectory\move-receipt.json`""
    }
    $receiptPath = Join-Path $reportDirectory 'move-receipt.json'
    Write-AIDataJson -Path $receiptPath -Value $receipt
    [pscustomobject]@{ Status = 'AwaitingValidation'; Receipt = $receiptPath; Tool = $Tool; DataRoot = $fullRoot; Entries = $renamedEntries } | ConvertTo-Json -Depth 8
} catch {
    $failure = $_
    foreach ($name in $environmentBefore.Keys) {
        try { Set-AIDataUserEnvironment -Name $name -Value $environmentBefore[$name].Value } catch { Write-Warning "Could not restore user environment ${name}: $($_.Exception.Message)" }
    }
    $rollbackEntries = @($renamedEntries)
    [Array]::Reverse($rollbackEntries)
    foreach ($entry in $rollbackEntries) {
        try {
            if (Test-AIDataJunction -Source $entry.Source -Destination $entry.Destination) { Remove-AIDataJunctionOnly $entry.Source }
            if (-not (Test-Path -LiteralPath $entry.Source) -and (Test-Path -LiteralPath $entry.PreMove)) {
                Rename-Item -LiteralPath $entry.PreMove -NewName (Split-Path -Leaf $entry.Source)
            }
        } catch { Write-Warning "Could not restore $($entry.Source): $($_.Exception.Message)" }
    }
    Write-AIDataJson -Path (Join-Path $reportDirectory 'move-failure.json') -Value ([ordered]@{ Status = 'FailedBeforeValidation'; Tool = $Tool; Error = $failure.Exception.Message; RolledBackEntries = @($renamedEntries) })
    throw $failure
}

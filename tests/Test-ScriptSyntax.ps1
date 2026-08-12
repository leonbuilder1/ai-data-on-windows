[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$files = @(Get-ChildItem -LiteralPath (Join-Path $root 'scripts') -File -Recurse | Where-Object { $_.Extension -in '.ps1', '.psm1' })
$parseErrors = [Collections.Generic.List[object]]::new()
foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    foreach ($parseError in $errors) { $parseErrors.Add([pscustomobject]@{ File = $file.FullName; Message = $parseError.Message; Line = $parseError.Extent.StartLineNumber }) }
}
if ($parseErrors.Count -gt 0) {
    $parseErrors | Format-Table -AutoSize | Out-Host
    throw 'PowerShell syntax validation failed.'
}

$forbidden = @('C:\\Users\\', 'D:\\AI\\Ops', 'D:\\AI\\Data\\Codex')
$trackedText = @(Get-ChildItem -LiteralPath $root -File -Recurse | Where-Object {
    $_.Extension -in '.md', '.mdc', '.ps1', '.psm1', '.txt' -and $_.FullName -ne $PSCommandPath
})
$hits = foreach ($file in $trackedText) {
    foreach ($pattern in $forbidden) {
        $match = Select-String -LiteralPath $file.FullName -Pattern $pattern -SimpleMatch:$false
        if ($match) { $match | Select-Object Path, LineNumber, Line, @{ Name = 'Pattern'; Expression = { $pattern } } }
    }
}
if (@($hits).Count -gt 0) {
    $hits | Format-Table -AutoSize | Out-Host
    throw 'Repository contains a machine-specific path or identity marker.'
}

[pscustomobject]@{ Status = 'Passed'; Scripts = $files.Count; PrivacyScanFiles = $trackedText.Count } | ConvertTo-Json

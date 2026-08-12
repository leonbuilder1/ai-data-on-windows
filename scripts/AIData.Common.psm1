Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AIDataFullPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    if ($fullPath.Length -gt 3) { $fullPath = $fullPath.TrimEnd('\') }
    return $fullPath
}

function Assert-AIDataChildPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$CandidatePath,
        [Parameter(Mandatory)][string]$ParentPath
    )

    $candidate = Get-AIDataFullPath $CandidatePath
    $parent = Get-AIDataFullPath $ParentPath
    if (-not $candidate.StartsWith($parent + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the approved data root: $candidate"
    }
}

function Test-AIDataReparsePoint {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    return [bool]((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Assert-AIDataOrdinaryDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "Directory does not exist: $Path" }
    if (Test-AIDataReparsePoint $Path) { throw "Directory is already a reparse point: $Path" }
}

function Assert-AIDataNoNestedReparsePoints {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)

    Assert-AIDataOrdinaryDirectory $Root
    $stack = [Collections.Generic.Stack[string]]::new()
    $stack.Push((Get-AIDataFullPath $Root))
    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        foreach ($child in @(Get-ChildItem -LiteralPath $current -Force)) {
            if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Source contains a reparse point; stop for manual review: $($child.FullName)"
            }
            if ($child.PSIsContainer) { $stack.Push($child.FullName) }
        }
    }
}

function Get-AIDataTreeSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)

    Assert-AIDataOrdinaryDirectory $Root
    $files = [int64]0
    $directories = [int64]0
    $bytes = [int64]0
    $stack = [Collections.Generic.Stack[string]]::new()
    $stack.Push((Get-AIDataFullPath $Root))
    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        foreach ($child in @(Get-ChildItem -LiteralPath $current -Force)) {
            if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Tree summary refuses to follow a reparse point: $($child.FullName)"
            }
            if ($child.PSIsContainer) {
                $directories++
                $stack.Push($child.FullName)
            } else {
                $files++
                $bytes += [int64]$child.Length
            }
        }
    }
    return [pscustomobject]@{ Files = $files; Directories = $directories; Bytes = $bytes }
}

function Assert-AIDataTreeSummaryEqual {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Source,
        [Parameter(Mandatory)]$Destination,
        [Parameter(Mandatory)][string]$Label
    )

    if ($Source.Files -ne $Destination.Files -or $Source.Directories -ne $Destination.Directories -or $Source.Bytes -ne $Destination.Bytes) {
        throw "Copy validation failed for $Label. Source=$($Source | ConvertTo-Json -Compress); Destination=$($Destination | ConvertTo-Json -Compress)"
    }
}

function Invoke-AIDataRoboCopy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$LogPath
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    & robocopy.exe $Source $Destination /E /COPY:DAT /DCOPY:DAT /XJ /R:2 /W:2 /NP "/LOG:$LogPath" | Out-Null
    $exitCode = $LASTEXITCODE
    if ($exitCode -ge 8) { throw "Robocopy failed for $Source (exit $exitCode). See $LogPath" }
}

function Get-AIDataUserEnvironment {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $false)
    if ($null -eq $key) { return [pscustomobject]@{ Exists = $false; Value = $null } }
    try {
        if ($key.GetValueNames() -notcontains $Name) { return [pscustomobject]@{ Exists = $false; Value = $null } }
        return [pscustomobject]@{ Exists = $true; Value = [string]$key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) }
    } finally {
        $key.Dispose()
    }
}

function Set-AIDataUserEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [AllowNull()][object]$Value
    )

    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
    try {
        if ($null -eq $Value) {
            $key.DeleteValue($Name, $false)
            [Environment]::SetEnvironmentVariable($Name, $null, 'Process')
        } else {
            $text = [string]$Value
            $key.SetValue($Name, $text, [Microsoft.Win32.RegistryValueKind]::String)
            [Environment]::SetEnvironmentVariable($Name, $text, 'Process')
        }
    } finally {
        $key.Dispose()
    }
}

function Assert-AIDataVolume {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DataRoot)

    $fullPath = Get-AIDataFullPath $DataRoot
    $drive = [IO.Path]::GetPathRoot($fullPath).TrimEnd(':', '\')
    $volume = Get-Volume -DriveLetter $drive -ErrorAction Stop
    if ($volume.FileSystemType -ne 'NTFS' -or $volume.HealthStatus -ne 'Healthy') {
        throw "Data drive must be a healthy NTFS volume: $drive"
    }
}

function New-AIDataPrivateRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DataRoot)

    Assert-AIDataVolume $DataRoot
    if (Test-Path -LiteralPath $DataRoot -PathType Leaf) { throw "Data root is a file: $DataRoot" }
    if (Test-Path -LiteralPath $DataRoot -PathType Container) {
        if (Test-AIDataReparsePoint $DataRoot) { throw "Data root must not be a reparse point: $DataRoot" }
    } else {
        New-Item -ItemType Directory -Path $DataRoot -Force | Out-Null
    }
}

function Test-AIDataJunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container) -or -not (Test-AIDataReparsePoint $Source)) { return $false }
    $item = Get-Item -LiteralPath $Source -Force
    if ($item.LinkType -ne 'Junction') { return $false }
    $actual = Get-AIDataFullPath ([string]$item.Target)
    return $actual -ieq (Get-AIDataFullPath $Destination)
}

function Remove-AIDataJunctionOnly {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-AIDataReparsePoint $Path)) { throw "Refusing to remove a non-link path: $Path" }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.LinkType -ne 'Junction') { throw "Refusing to remove a non-junction link: $Path" }
    & cmd.exe /d /c ('rmdir "{0}"' -f $Path) | Out-Null
    if (Test-Path -LiteralPath $Path) { throw "Junction removal failed: $Path" }
}

function Assert-AIDataNoProfileProcess {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$SourcePaths)

    $needles = @($SourcePaths | ForEach-Object { (Get-AIDataFullPath $_).ToLowerInvariant() })
    $matches = @(
        Get-CimInstance Win32_Process | Where-Object {
            $command = [string]$_.CommandLine
            $executable = [string]$_.ExecutablePath
            $haystack = ($command + "`n" + $executable).ToLowerInvariant()
            $needles | Where-Object { $haystack.Contains($_) } | Select-Object -First 1
        } | Select-Object ProcessId, Name, ExecutablePath, CommandLine
    )
    if ($matches.Count -gt 0) {
        $matches | Format-Table -AutoSize | Out-Host
        throw 'A profile-related process is still running. Close the relevant app and terminal sessions before switching paths.'
    }
}

function Get-AIDataProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Codex', 'ClaudeCode', 'Cursor')][string]$Tool,
        [Parameter(Mandatory)][string]$DataRoot
    )

    $root = Get-AIDataFullPath $DataRoot
    $userProfile = [Environment]::GetFolderPath('UserProfile')
    switch ($Tool) {
        'Codex' {
            $configured = Get-AIDataUserEnvironment 'CODEX_HOME'
            $source = if ($configured.Exists -and $configured.Value) { Get-AIDataFullPath $configured.Value } else { Join-Path $userProfile '.codex' }
            return [pscustomobject]@{
                Tool = $Tool
                Entries = @([pscustomobject]@{ Name = 'CodexHome'; Kind = 'Directory'; Source = $source; Destination = (Join-Path $root 'Data\Codex\Home') })
                Environment = [ordered]@{
                    CODEX_HOME = (Join-Path $root 'Data\Codex\Home')
                    CODEX_SQLITE_HOME = (Join-Path $root 'Data\Codex\Home')
                    CODEX_INSTALL_DIR = (Join-Path $root 'Tools\Codex\Bin')
                }
            }
        }
        'ClaudeCode' {
            $configured = Get-AIDataUserEnvironment 'CLAUDE_CONFIG_DIR'
            $source = if ($configured.Exists -and $configured.Value) { Get-AIDataFullPath $configured.Value } else { Join-Path $userProfile '.claude' }
            return [pscustomobject]@{
                Tool = $Tool
                Entries = @([pscustomobject]@{ Name = 'ClaudeCodeConfig'; Kind = 'Directory'; Source = $source; Destination = (Join-Path $root 'Data\ClaudeCode\Config') })
                Environment = [ordered]@{
                    CLAUDE_CONFIG_DIR = (Join-Path $root 'Data\ClaudeCode\Config')
                    CLAUDE_CODE_TMPDIR = (Join-Path $root 'Temp\ClaudeCode')
                }
            }
        }
        'Cursor' {
            return [pscustomobject]@{
                Tool = $Tool
                Entries = @(
                    [pscustomobject]@{ Name = 'CursorProfile'; Kind = 'Directory'; Source = (Join-Path $userProfile '.cursor'); Destination = (Join-Path $root 'Data\Cursor\Home') },
                    [pscustomobject]@{ Name = 'CursorRoaming'; Kind = 'Directory'; Source = (Join-Path $userProfile 'AppData\Roaming\Cursor'); Destination = (Join-Path $root 'Data\Cursor\Roaming') }
                )
                Environment = [ordered]@{}
            }
        }
    }
}

Export-ModuleMember -Function @(
    'Get-AIDataFullPath', 'Assert-AIDataChildPath', 'Test-AIDataReparsePoint', 'Assert-AIDataOrdinaryDirectory',
    'Assert-AIDataNoNestedReparsePoints', 'Get-AIDataTreeSummary', 'Assert-AIDataTreeSummaryEqual',
    'Invoke-AIDataRoboCopy', 'Get-AIDataUserEnvironment', 'Set-AIDataUserEnvironment', 'Assert-AIDataVolume',
    'New-AIDataPrivateRoot', 'Test-AIDataJunction', 'Remove-AIDataJunctionOnly', 'Assert-AIDataNoProfileProcess',
    'Get-AIDataProfile'
)

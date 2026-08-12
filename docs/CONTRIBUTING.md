# Contributing

## Privacy requirements

Do not add real usernames, home directories, hostnames, account names, application identifiers, session IDs, report paths, tokens, screenshots of private data or copied application state. Use `%USERPROFILE%`, `%APPDATA%` and examples such as `D:\AIData`.

## Script requirements

- PowerShell 7 and Windows-native paths.
- `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'`.
- Dry run/audit behavior by default; explicit `-Execute` for every mutation.
- No recursive deletion that follows directory junctions.
- No hidden process termination.
- Validation must be proportional and explain its limits. This project intentionally compares file/dir counts and bytes, not hashes.

## Local checks

```powershell
pwsh -NoProfile -File .\tests\Test-ScriptSyntax.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Initialize-AIDataRoot.ps1 -DataRoot D:\AIData
```

Do not run `-Execute` against a development machine merely to test a pull request.

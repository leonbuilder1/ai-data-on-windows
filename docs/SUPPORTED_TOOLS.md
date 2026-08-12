# Supported tool profiles

## Codex

The profile relocates the active `CODEX_HOME` when it is configured, otherwise the default `%USERPROFILE%\.codex`. It writes `CODEX_HOME`, `CODEX_SQLITE_HOME` and `CODEX_INSTALL_DIR` in the current user's environment. A new terminal or app process is required after the change.

Do not run it while the Codex desktop app, CLI, extension host or a terminal using the profile is open. Inspect the audit output because the source may be a non-default configured home.

## Claude Code

The profile relocates the active `CLAUDE_CONFIG_DIR`, otherwise `%USERPROFILE%\.claude`; it sets `CLAUDE_CONFIG_DIR` and `CLAUDE_CODE_TMPDIR`. The supported variable covers settings, history, plugins and Windows credentials. Open a fresh Claude Code process to validate login, sessions, plugins and a new write.

Claude Desktop is different from Claude Code. Its program package, services and MSIX/AppX data are system-managed and deliberately outside this automated profile.

## Cursor

The profile relocates both `%USERPROFILE%\.cursor` and `%APPDATA%\Cursor` through junctions. It does not move Cursor's program executable or alter shortcut, protocol or file-association commands; the original logical data paths still resolve through the junctions.

Close every Cursor window, Cursor Agent and extension host before switching. Validate existing settings, extensions, MCP configuration, recent workspaces and one agent run afterwards.

## Adding a tool profile

A new profile needs all of the following before it is accepted:

- A public vendor-supported storage variable, or a documented and reversible logical path approach.
- Closed-process detection that does not kill unrelated processes by name.
- Audit-only behavior, source/destination validation and a no-follow copy plan.
- A rollback receipt and an explicit cleanup step.
- A manual acceptance checklist that includes post-update behavior.

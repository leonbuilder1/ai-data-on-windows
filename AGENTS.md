# AI agent operating rules

This repository changes local Windows storage paths for AI developer tools. Treat every `-Execute` invocation as a destructive system operation.

1. Read `README.md` and `docs/SAFETY_MODEL.md` before suggesting any command.
2. Run the audit-only command first. Do not add `-Execute` unless the computer owner explicitly approves the displayed source, destination, stop window, and rollback approach.
3. Work on exactly one `-Tool` profile per change window. Do not combine Codex, Claude Code, Cursor, package managers, or system package moves.
4. Do not copy, print, commit, upload, or summarize authentication files, session contents, local settings, receipts, logs, or directory listings from a user profile.
5. Never move or junction `WindowsApps`, `WpSystem`, `AppData\Local\Packages`, Program Files, or an unknown AppX/MSIX folder.
6. Do not replace the scripts' file-count/directory-count/byte-count validation with deletion, mirroring, or hash-only validation.
7. Keep the C `pre-ai-data-*` rollback directory until the user has completed manual application acceptance and at least one normal update check.
8. If a stop gate, source condition, junction check, or validation fails, stop. Preserve the receipt and report the exact non-sensitive error; do not improvise a delete or forced copy.

The repository must remain portable: do not add user names, account names, personal folders, machine names, application IDs, local reports, or real data paths to tracked files.

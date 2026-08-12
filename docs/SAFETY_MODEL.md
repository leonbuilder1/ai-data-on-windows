# Safety model

## Two-phase data relocation

Each supported profile uses the same sequence:

1. Inspect the source and proposed destination without writing.
2. Confirm the tool is stopped and the source is an ordinary directory tree.
3. Copy to a previously absent data-drive destination with `robocopy /E /XJ`.
4. Compare file count, directory count and total bytes. No content hash is calculated.
5. Rename the C source on the same parent volume to `*.pre-ai-data-<timestamp>`.
6. Create an NTFS directory junction at the original logical path, pointing to the D data tree.
7. Set only the documented user-level environment variables for the profile.
8. Verify the junction and variables, then perform manual application acceptance in a new process.
9. Only after acceptance, optionally delete the exact C pre-move directory recorded in the receipt.

## Failure handling

Before a junction exists, a failure leaves the original C directory untouched and may leave a D copy for review. After a junction exists, the script removes only that junction and renames the pre-move directory back. It never automatically deletes the D live copy.

The final cleanup routine refuses to follow a reparse point. If a pre-move directory has one, cleanup stops for manual review instead of traversing into an external target.

## What this project does not guarantee

Windows and vendor installers can retain small registry entries, shortcuts, update metadata, service logs or package-management files on the system drive. “Data on D” means controllable user data, caches, session state and future tool downloads are redirected where the tool supports it; it does not mean a supported application will have literally zero C-drive writes.

Never force an AppX/MSIX application by copying or linking its system-managed storage. Use supported Windows/installer operations and validate the application independently.

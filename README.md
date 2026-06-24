# Windows Maintenance Script

This repository contains a PowerShell maintenance script intended for Windows endpoint cleanup, repair, patching, and transcript logging.

The current codebase is small:

- `Tuneup-Script.ps1` - the main maintenance script.
- `LICENSE` - MIT license.

## What the Script Does

`Tuneup-Script.ps1` is a multi-stage Windows tune-up script. It is designed to be run with administrator privileges and performs actions that affect the local machine broadly.

At a high level, the script:

1. Starts a transcript log on the system drive.
2. Checks for `winget`, and attempts attended installation when possible.
3. Signs out users unless an attended user is specified.
4. Deletes user profile temp files and cache folders defined in an external JSON file.
5. Clears certificate URL cache entries.
6. Removes old Windows upgrade folders such as `Windows.old`, `$Windows.~BT`, and `$Windows.~WS`.
7. Clears Windows temp, prefetch, Windows Error Reporting, Windows Search temp data, CBS logs, and Windows Update cache.
8. Runs Disk Cleanup using downloaded registry settings and PsExec when unattended.
9. Performs Dell Command Update handling on Dell systems.
10. Uses HP Image Assistant to install driver and firmware recommendations on supported HP systems.
11. Skips or reports unsupported handling for Microsoft Surface, Hyper-V, and other manufacturer cases.
12. Runs Windows repair and optimization commands such as SFC, `Repair-WindowsImage`, `Repair-Volume`, and `Optimize-Volume`.
13. Optionally performs an OS component store reset base operation.
14. Clears DNS, ARP, and Winsock state.
15. Quarantines orphaned Windows Installer cache candidates into a compressed archive, or permanently deletes them when purge mode is requested.
16. Performs application-specific cleanup for Teams, Adobe, AAD Broker Plugin, and QuickBooks.
17. Uses `winget` to update maintained applications listed in an external JSON file.
18. Enables and runs Microsoft Defender full scan operations unless skipped.
19. Removes temporary downloaded assets.
20. Prints a final error count and error log to the transcript.
21. Logs ending system-drive free space and net free-space change.
22. Optionally reboots when `-RebootWhenDone` is supplied.

## Parameters

The script currently defines these parameters:

```powershell
.\Tuneup-Script.ps1 [-AttendedRun <username>] [-SkipDefender] [-NoRebase] [-NoMSIZap] [-MSIZapPurge] [-RebootWhenDone]
```

### `-AttendedRun <username>`

Marks the run as attended and passes the username that should remain signed in.

When this is supplied:

- The matching user is skipped during sign-out.
- Disk Cleanup runs visibly in the active user context.
- `winget` installation can be attempted in the logged-in user context if `winget` is missing.

Example:

```powershell
.\Tuneup-Script.ps1 -AttendedRun "jdoe"
```

### `-SkipDefender`

Skips the Microsoft Defender update, full scan, and threat removal stage.

Example:

```powershell
.\Tuneup-Script.ps1 -SkipDefender
```

### `-NoRebase`

Skips the OS component store reset base stage. This preserves the ability to uninstall superseded Windows updates.

Example:

```powershell
.\Tuneup-Script.ps1 -NoRebase
```

### `-NoMSIZap`

Skips the Windows Installer cache cleanup stage. This switch name is retained for compatibility with older script usage.

Example:

```powershell
.\Tuneup-Script.ps1 -NoMSIZap
```

### `-MSIZapPurge`

Permanently deletes orphaned Windows Installer cache candidates instead of placing them in a quarantine ZIP. The files are removed directly with `Remove-Item`, bypassing the Recycle Bin, and cannot be restored from a quarantine archive.

`-MSIZapPurge` cannot be combined with `-NoMSIZap`.

Example:

```powershell
.\Tuneup-Script.ps1 -MSIZapPurge
```

### `-RebootWhenDone`

Forcibly reboots the computer after cleanup and transcript logging complete. Without this switch, the script leaves the computer running whether the run is attended or unattended.

Example:

```powershell
.\Tuneup-Script.ps1 -RebootWhenDone
```

## Running the Script

Run from an elevated Windows PowerShell session:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
.\Tuneup-Script.ps1
```

For an attended local run:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
.\Tuneup-Script.ps1 -AttendedRun "username"
```

The script does not reboot by default. To request a forced reboot after cleanup:

```powershell
.\Tuneup-Script.ps1 -RebootWhenDone
```

Only use `-RebootWhenDone` when an immediate forced reboot after maintenance is acceptable.

## External Assets and Services

The script downloads or calls assets from several external locations:

- `https://api.github.com/repos/microsoft/winget-cli/releases`
- `https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx`
- `https://raw.githubusercontent.com/KoshiirRa/script-assets/main/MaintainedPrograms.json`
- `https://raw.githubusercontent.com/KoshiirRa/script-assets/main/UserTempFileLocations.json`
- `https://raw.githubusercontent.com/KoshiirRa/script-assets/main/TuneUpReg.reg`
- `https://download.sysinternals.com/files/PSTools.zip`
- `https://github.com/NetlinkSolutions/Script-Assets/raw/main/DellCommandSetup.exe`
- `https://go.microsoft.com/fwlink/?linkid=2088631`
- `https://ftp.ext.hp.com/pub/caps-softpaq/cmit/HPIA.html`
- The current signed HPIA SoftPaq URL published on HP's official HPIA page.

The script assumes these URLs are reachable at runtime and that the downloaded assets are trusted.

## Logging and Reporting

The script starts a PowerShell transcript at:

```text
%SystemDrive%\MaintenanceOutput-<timestamp>.txt
```

It tracks an internal `$ErrorCount` and `$ErrorLog`. At the end of the run, it prints the final error count and accumulated error text to the transcript output.

The transcript also records system-drive free space at the beginning and end of the run, plus the net free-space change in GB and bytes.

## Important Operational Notes

This script is intentionally invasive. It deletes files, resets Windows Update state, changes Defender policy values, runs repair tools, runs vendor update tooling, and may forcibly restart the computer.

Before running it on a production endpoint, confirm that:

- The endpoint has a current backup or restore path.
- A forced reboot is acceptable when `-RebootWhenDone` is supplied.
- Active users can be signed out.
- Downloaded third-party and Microsoft utilities are allowed by policy.
- Microsoft Defender actions will not conflict with the endpoint's security stack.
- Resetting the OS component store is acceptable, because it can remove the ability to uninstall superseded updates.
- `-MSIZapPurge` is used only when permanent, immediate deletion of orphaned installer cache candidates is acceptable.

## Current Implementation Notes

These notes describe the code as it currently stands, not planned behavior.

- The repository does not currently include tests, CI configuration, or a module structure.
- The script is one large procedural file with helper functions for winget handling, PsExec installation, disk-space metrics, and Windows Installer cache cleanup.
- The script depends on external asset files that are not versioned in this repository.
- The numbered maintenance sections currently run from Step 0 through Step 14.
- Application updates always run when the OS version check and `winget` handling allow it; there is no declared skip flag for that stage.
- Step 10 replaces the older MSIZap approach with a Windows Installer cache reference audit. By default, orphaned candidates are archived under `C:\Temp\InstallerCacheQuarantine`; `-MSIZapPurge` permanently deletes them instead.
- Deprecated `cacls.exe` usage has been replaced with `icacls.exe`, and Windows package discovery uses `Get-AppxPackage`.
- On systems whose manufacturer is reported as HP or Hewlett-Packard, Step 6 discovers the latest HPIA SoftPaq from HP's official page, verifies its HP digital signature, extracts it, and silently installs driver and firmware recommendations.
- HPIA reports are retained under `%SystemDrive%\Temp\HPIA\Reports`; downloaded HPIA tooling and SoftPaq files are removed.
- Surface firmware and driver update handling is informational only.

## AI-Assisted Development Disclosure

This script was originally written by Marty Marks. Codex and ChatGPT have subsequently been used as AI-assisted development tools to help review, document, maintain, and improve the script. AI-generated suggestions and changes are reviewed and accepted by the repository maintainer, who remains responsible for the project's direction and published code.

## License

This project is licensed under the MIT License. See `LICENSE`.

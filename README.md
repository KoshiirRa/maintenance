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
10. Skips or reports unsupported handling for some Microsoft, Surface, Hyper-V, HP, and other manufacturer cases.
11. Runs Windows repair and optimization commands such as SFC, `Repair-WindowsImage`, `Repair-Volume`, and `Optimize-Volume`.
12. Optionally performs an OS component store reset base operation.
13. Clears DNS, ARP, and Winsock state.
14. Optionally runs MSIZap to clear orphaned Windows Installer cache data.
15. Performs application-specific cleanup for Teams, Adobe, AAD Broker Plugin, and QuickBooks.
16. Uses `winget` to update maintained applications listed in an external JSON file.
17. Enables and runs Microsoft Defender full scan operations unless skipped.
18. Removes temporary downloaded assets.
19. Prints a final error count and error log to the transcript.
20. Reboots automatically after unattended runs.

## Parameters

The script currently defines these parameters:

```powershell
.\Tuneup-Script.ps1 [-AttendedRun <username>] [-SkipDefender] [-NoRebase] [-NoMSIZap]
```

### `-AttendedRun <username>`

Marks the run as attended and passes the username that should remain signed in.

When this is supplied:

- The matching user is skipped during sign-out.
- Disk Cleanup runs visibly in the active user context.
- The script does not automatically reboot at the end.
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

Skips MSIZap cleanup of orphaned Windows Installer cached data.

Example:

```powershell
.\Tuneup-Script.ps1 -NoMSIZap
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

The unattended path ends with:

```powershell
Restart-Computer -Force
```

Do not start an unattended run unless an immediate forced reboot is acceptable.

## External Assets and Services

The script downloads or calls assets from several external locations:

- `https://api.github.com/repos/microsoft/winget-cli/releases`
- `https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx`
- `https://github.com/NetlinkSolutions/Script-Assets/raw/main/MaintainedPrograms.json`
- `https://raw.githubusercontent.com/NetlinkSolutions/Script-Assets/main/UserTempFileLocations.json`
- `https://raw.githubusercontent.com/NetlinkSolutions/Script-Assets/main/TuneUpReg.reg`
- `https://github.com/NetlinkSolutions/Script-Assets/raw/main/PsExec.exe`
- `https://github.com/NetlinkSolutions/Script-Assets/raw/main/DellCommandSetup.exe`
- `https://github.com/NetlinkSolutions/Script-Assets/raw/main/msizap.exe`
- `https://go.microsoft.com/fwlink/?linkid=2088631`

The script assumes these URLs are reachable at runtime and that the downloaded assets are trusted.

## Logging and Reporting

The script starts a PowerShell transcript at:

```text
%SystemDrive%\MaintenanceOutput-<timestamp>.txt
```

It tracks an internal `$ErrorCount` and `$ErrorLog`. At the end of the run, it prints the final error count and accumulated error text to the transcript output.

## Important Operational Notes

This script is intentionally invasive. It deletes files, resets Windows Update state, changes Defender policy values, runs repair tools, runs vendor update tooling, and may forcibly restart the computer.

Before running it on a production endpoint, confirm that:

- The endpoint has a current backup or restore path.
- A forced reboot is acceptable.
- Active users can be signed out.
- Downloaded third-party and Microsoft utilities are allowed by policy.
- Microsoft Defender actions will not conflict with the endpoint's security stack.
- Resetting the OS component store is acceptable, because it can remove the ability to uninstall superseded updates.

## Current Implementation Notes

These notes describe the code as it currently stands, not planned behavior.

- The repository does not currently include tests, CI configuration, or a module structure.
- The script is one large procedural file with two helper functions: `Install-WinGet` and `WingetPatching`.
- The script depends on external asset files that are not versioned in this repository.
- The script numbering currently jumps from Step 1 to Step 3; there is no Step 2 block in the current file.
- `-SkipAppUpdates` is referenced in Step 13 but is not declared as a script parameter.
- There are several hard-coded root-drive paths such as `C:\PsExec.exe`, `C:\msizap.exe`, and QuickBooks cleanup paths under `C:\ProgramData`.
- Some commands appear to contain typos or questionable paths, such as `Write-Ouput`, `-acceptuela`, `$EnvSystemDrive`, and a cleanup path string containing `TuneUpReg.reg -Force`.
- The Home SKU branch still contains an incomplete-looking `Write-EventLog Applications` call.
- The error path appends `$logTimestamp` before assigning it, while the no-error path assigns it first.
- HP Image Assistant support is currently commented out and explicitly skipped.
- Surface firmware and driver update handling is informational only.

## License

This project is licensed under the MIT License. See `LICENSE`.

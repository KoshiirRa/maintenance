# Agent Instructions

This repository contains a Windows maintenance script that performs broad endpoint cleanup, repair, update, and reboot-related actions. Treat it as invasive automation.

## Working Rules

- Do not run the full maintenance script unless the user explicitly asks for an execution run.
- Prefer static inspection, PowerShell parser checks, and targeted function review.
- Keep `README.md` aligned with behavior whenever `Tuneup-Script.ps1` changes.
- Keep the script compatible with Windows PowerShell 5.1 unless the user explicitly changes that target.
- Avoid publishing binaries in this repository or the public `script-assets` repository when an official vendor download URL can be used instead.
- Be careful with public-facing content in the companion `script-assets` repository. Only publish sanitized text/config assets or content intentionally meant to be public.
- Do not remove destructive-operation safeguards without an explicit user request.
- Preserve user changes in the working tree. Do not reset, checkout, or revert unrelated changes.

## Validation

Use GitHub Desktop's bundled Git if `git` is not on `PATH`:

```powershell
& 'C:\Users\concentus\AppData\Local\GitHubDesktop\app-3.5.12\resources\app\git\cmd\git.exe' status --short --branch
```

Parser-check the script after edits:

```powershell
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path '.\Tuneup-Script.ps1'), [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count) { $errors | Format-List *; exit 1 }
'Parse OK'
```

Check whitespace-sensitive diff issues before committing:

```powershell
& 'C:\Users\concentus\AppData\Local\GitHubDesktop\app-3.5.12\resources\app\git\cmd\git.exe' diff --check
```

When asked to push, verify the remote head after pushing:

```powershell
& 'C:\Users\concentus\AppData\Local\GitHubDesktop\app-3.5.12\resources\app\git\cmd\git.exe' fetch origin
& 'C:\Users\concentus\AppData\Local\GitHubDesktop\app-3.5.12\resources\app\git\cmd\git.exe' status --short --branch
& 'C:\Users\concentus\AppData\Local\GitHubDesktop\app-3.5.12\resources\app\git\cmd\git.exe' ls-remote origin refs/heads/main
```

## Repository Notes

- Main repo path: `C:\Users\concentus\Documents\Windows Maintenance Script`
- Main script: `Tuneup-Script.ps1`
- Documentation: `README.md`
- Companion public assets repo: `C:\Users\concentus\Documents\script-assets`
- Remote maintenance repo: `https://github.com/KoshiirRa/maintenance.git`
- Remote assets repo: `https://github.com/KoshiirRa/script-assets.git`

## Current Behavior To Preserve

- Default behavior does not reboot. `-RebootWhenDone` makes reboot opt-in.
- `-NoMSIZap` skips Windows Installer cache cleanup.
- `-MSIZapPurge` permanently deletes orphaned installer cache candidates and cannot be combined with `-NoMSIZap`.
- Default installer-cache cleanup quarantines orphaned candidates in an optimally compressed ZIP before removing originals.
- PsExec is sourced from Microsoft's official Sysinternals `PSTools.zip`, not from a repository-hosted binary.
- HP Image Assistant is discovered from HP's official HPIA page, signature-checked, extracted, and used for HP driver/firmware recommendations.
- Transcript logging includes system-drive free space at start and end, plus net change.
- README includes an AI-assisted development disclosure.


# Project Memory

This file stores durable project context for future work in this repository.

## Project

- Repository: `KoshiirRa/maintenance`
- Local path: `C:\Users\concentus\Documents\Windows Maintenance Script`
- Main branch: `main`
- Main script: `Tuneup-Script.ps1`
- Documentation: `README.md`
- Companion public assets repository: `KoshiirRa/script-assets`
- Local assets path: `C:\Users\concentus\Documents\script-assets`

## Maintainer Intent

- Original script author: Marty Marks.
- Codex/ChatGPT is used to review, document, maintain, and improve the script.
- README should disclose AI-assisted maintenance while making clear that Marty reviews and accepts changes.
- The maintenance script is intentionally powerful and destructive in places, so changes should favor auditability, reversibility where practical, and clear docs.

## Safety Decisions

- Do not run `Tuneup-Script.ps1` end-to-end unless explicitly asked.
- Prefer parser checks and static review for validation.
- Treat Windows Installer cache cleanup as high risk.
- Prefer official vendor download URLs over re-hosted binaries.
- Be extra cautious with `script-assets` because it is public-facing.
- Keep public assets sanitized.

## Implementation Decisions

- PsExec comes from official Microsoft Sysinternals `PSTools.zip`, downloaded to the temp workflow and extracted as needed.
- MSIZap is no longer used.
- The normal installer-cache cleanup path identifies orphaned Windows Installer cache candidates, writes a manifest, compresses candidates into a ZIP with optimal compression, and removes originals after quarantine.
- `-MSIZapPurge` bypasses quarantine and permanently deletes candidates with `Remove-Item`.
- `-NoMSIZap` skips installer-cache cleanup.
- `-NoMSIZap` and `-MSIZapPurge` together should throw.
- Default script behavior does not reboot.
- `-RebootWhenDone` performs the final reboot after cleanup and transcript logging.
- System-drive free space is logged near the start and end of the transcript.
- HP Image Assistant support discovers the current official HPIA SoftPaq from HP's HPIA page, verifies the Authenticode signer, extracts the tool, and runs driver and firmware recommendations.
- Dell Command Update support is still present for Dell systems.
- `UseBasicParsing` is intentionally retained where needed for Windows PowerShell 5.1 compatibility.

## Validation Commands

Use bundled Git when needed:

```powershell
& 'C:\Users\concentus\AppData\Local\GitHubDesktop\app-3.5.12\resources\app\git\cmd\git.exe' status --short --branch
```

PowerShell parser check:

```powershell
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path '.\Tuneup-Script.ps1'), [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count) { $errors | Format-List *; exit 1 }
'Parse OK'
```

Git diff whitespace check:

```powershell
& 'C:\Users\concentus\AppData\Local\GitHubDesktop\app-3.5.12\resources\app\git\cmd\git.exe' diff --check
```

## Open Issues Snapshot

Last retrieved via public GitHub REST API:

- `#1 Disk Cleanup Sagerun not working reliably` - bug.
- `#2 Lenovo system updates?` - enhancement.
- `#3 Clear out print spooler` - enhancement.
- `#4 Hunt for more space-saving measures` - enhancement.
- `#5 Hunt for more cached updaters/installers` - enhancement.

Refresh issues before making decisions based on this list.


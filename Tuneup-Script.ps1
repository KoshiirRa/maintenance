#Author: Marty Marks
#Revision: 2.8
#
#History:
#1 - initial commit
#1.1 - renumber stages, add a new first step to sign out all users except for <sanitized> (or none of them if it is a Home SKU).  Also added support for -AttendedRun switch if you're manually running the script.
#1.2 - remember to put -ErrorAction SilentlyContinue on all the remove-item commands so it doesn't clutter the log with errors about files not existing.  fix an errant write-output that had no text on it.  Add code to stop TrustedInstaller service before trying to clear the CSB logs and start it up afterwards.  piping invoke-command to Out-Null to suppress all this meaningless trash output.  swapped one invoke-command to a powershell equivalent.  reboot at end of script to actually do disk repairs.  moved all cleanup of downloaded assets to the end before reboot.  check for (and install if necessary) dell command update (if manufacturer contains dell), scan for updates, and install updates.  Use winget to update a list of programs (if they are installed) which is stored in a json file over in the assets repo.
#1.2.1 - Oh hey I can just convert that $AttendedRun parameter to take a string instead of being a switch flag and boom - completely sanitized script aside from it mentioning our public assets repo (where nothing desanitized lives anyway)
#1.3 - convert the giant list of folders in user temp file locations to a json stored in script assets.  add windows defender scanning.
#1.3.1 - fixing typoed stuff.  fixed bad logic.  fixed dell command update (wrong flag for installing updates).  add adobe temp file cleanup.
#1.4 - fixed parameter declarations.  altered formatting on temp file cleanup.  run disk cleanup visibly if in an AttendedSession run.  fix typos.  add logic for resetbase to fail over to non-powershell if it doesn't have the -resetbase parameter.  removed an errant -whatif parameter.  fixed $AttendedRun logic because .IsPresent only works on Switch parameters and nothing else.  fixed some issues with dell command update, added in logic for a scenario where v3 is installed.
#1.5 - NEW PARAMETERS (-NoMSIZap, -NoRebase).  working on getting errors logged in ninja.  added full output logging via powershell transcription. added ability to skip step 9 (OS rebase).  added ability to skip step 11 (MSIZap).  Improved the whole script to allow for machines that don't have the system drive as C.  Rewrote psexec for disk cleanup to use invoke-expression to allow for the previous to work.  This also allowed me to condense dell command update down into a single if statement instead of one for 64 bit and one for 32 bit ($Env:ProgramFiles).  converted msizap to use invoke-expression as well.  added more error handling.
#1.5.1 - NO CHANGES TO THIS FILE BUT TRACKING STUFF IN PUBLIC REPO AS WELL: Added Edge cache/temp file locations to UserTempFileLocations.json.  Added Firefox cache location to UserTempFileLocations.json
#1.6 - PRE-LAUNCH REVISIONS.  Change transcript location to $env:ProgramData\NinjaRMMAgent\.  Fix disk cleanup.  Fixed dell command update errors.
#1.7 - Fixing parameters to be spelled correctly.  Minor tweaks.  Expanded out error logging to ninja to add a timestamp.
#1.8 - Fixed attendedrun disk cleanup.
#1.9 - Added theoretical support for HP firmware/driver updates.  
#1.10 - fixed auto-signout logic.
#1.11 - add auto-install of winget
#1.12 - enhanced winget script block, yay functions
#2.0 - forking from original script
#2.1 - added two lines to application cleanup to deal with the fact that Intuit never cleans up after itself.
#2.2 - Had Codex add some improvements.
#2.3 - merge back in stuff I forgot to push from the work machine.  suppress errors on Intuit cleanup, expand QB cache cleanup, add logic to see if github is accessible.
#2.4 - Fixed step numbering, parameter handling, typos, and path issues. Moved public text assets to the script-assets repository and replaced the repository-hosted PsExec binary with the official Microsoft Sysinternals PSTools.zip download.
#2.5 - Replaced MSIZap with an orphaned Windows Installer cache audit that stores candidates in an optimally compressed quarantine archive before removing the originals.
#2.6 - Added transcript metrics for system-drive free space at the beginning and end of each run.
#2.7 - Added -MSIZapPurge for immediate permanent deletion of orphaned installer cache candidates and -RebootWhenDone to make rebooting opt-in. Replaced deprecated command usage and updated package detection.
#2.8 - Enabled HP Image Assistant support for HP and Hewlett-Packard systems. The script now discovers the latest official signed HPIA SoftPaq, extracts it, installs driver and firmware recommendations, handles documented return codes, and retains timestamped reports.
#
#Description: Okay so this is a horrible, horrible idea, but I'm going to try and consolidate my 4-batch-file-plus-1-powershell-script tuneup process we had on Automate into a single powershell script.  Yes, I'm crazy.  Yes, this file is going to be full of a lot of bastardized code for a while.
#
#FUTURE PLANS
#-Holy crap wipe out the System32\Spool\Printers folder
#--65534 = 
#--65533 = 
#-find a way to strip out the old Dell Command Update
#
#PARAMETERS
#-AttendedRun: feed it the username and it will skip that user
#-NoMSIZap: switch flag, if set it will skip Windows Installer cache quarantine
#-MSIZapPurge: switch flag, if set it permanently deletes orphaned Windows Installer cache candidates instead of quarantining them
#-NoRebase: switch flag, if set it will skip OS Rebase
#-RebootWhenDone: switch flag, if set it will forcibly reboot the computer after cleanup completes
#-SkipDefender: switch flag, if set it will skip defender run (also set internally further down if it detects that defender is off and cannot be turned on)

param (
    # Am I watching this run locally or not?
    [Parameter()][String]$AttendedRun,
    # Do I need to run Defender?
    [Parameter()][Switch]$SkipDefender,
    # Do I need to skip OS Rebasing?
    [Parameter()][Switch]$NoRebase,
    # Do I need to skip Windows Installer cache quarantine?
    [Parameter()][Switch]$NoMSIZap,
    # Do I need to permanently delete orphaned Windows Installer cache candidates instead of quarantining them?
    [Parameter()][Switch]$MSIZapPurge,
    # Do I need to forcibly reboot the computer after cleanup completes?
    [Parameter()][Switch]$RebootWhenDone
)

if ($NoMSIZap.IsPresent -and $MSIZapPurge.IsPresent) {
    throw "-NoMSIZap and -MSIZapPurge cannot be used together."
}

Function Install-WinGet {
    #Install the latest package from GitHub
    [cmdletbinding(SupportsShouldProcess)]
    [alias("iwg")]
    [OutputType("None")]
    [OutputType("Microsoft.Windows.Appx.PackageManager.Commands.AppxPackage")]
    Param(
        [Parameter(HelpMessage = "Display the AppxPackage after installation.")]
        [switch]$Passthru
    )

    Write-Verbose "[$((Get-Date).TimeofDay)] Starting $($myinvocation.mycommand)"

    if ($PSVersionTable.PSVersion.Major -eq 7) {
        Write-Warning "This command does not work in PowerShell 7. You must install in Windows PowerShell."
        return
    }

    #test for requirement
    $Requirement = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller"
    if (-Not $requirement) {
        Write-Verbose "Installing Desktop App Installer requirement"
        Try {
            Add-AppxPackage -Path "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" -erroraction Stop
        }
        Catch {
            Throw $_
        }
    }

    $uri = "https://api.github.com/repos/microsoft/winget-cli/releases"

    Try {
        Write-Verbose "[$((Get-Date).TimeofDay)] Getting information from $uri"
        $get = Invoke-RestMethod -uri $uri -Method Get -ErrorAction stop

        Write-Verbose "[$((Get-Date).TimeofDay)] getting latest release"
        #$data = $get | Select-Object -first 1
        $data = $get[0].assets | Where-Object name -Match 'msixbundle'

        $appx = $data.browser_download_url
        #$data.assets[0].browser_download_url
        Write-Verbose "[$((Get-Date).TimeofDay)] $appx"
        If ($pscmdlet.ShouldProcess($appx, "Downloading asset")) {
            $file = Join-Path -path $env:temp -ChildPath $data.name

            Write-Verbose "[$((Get-Date).TimeofDay)] Saving to $file"
            Invoke-WebRequest -Uri $appx -UseBasicParsing -DisableKeepAlive -OutFile $file

            Write-Verbose "[$((Get-Date).TimeofDay)] Adding Appx Package"
            Add-AppxPackage -Path $file -ErrorAction Stop

            if ($passthru) {
                Get-AppxPackage microsoft.desktopAppInstaller
            }
        }
    } #Try
    Catch {
        Write-Verbose "[$((Get-Date).TimeofDay)] There was an error."
        Throw $_
    }
    Write-Verbose "[$((Get-Date).TimeofDay)] Ending $($myinvocation.mycommand)"
}

Function WingetPatching {
    Write-Output "Winget available :)"
        Invoke-WebRequest -Uri https://raw.githubusercontent.com/KoshiirRa/script-assets/main/MaintainedPrograms.json -OutFile "$Env:SystemDrive\MaintainedPrograms.json"
        $maintainedPrograms = Get-Content "$Env:SystemDrive\MaintainedPrograms.json" | Out-String | ConvertFrom-Json
        foreach ($program in $maintainedPrograms) {
            $name = $program.Name
            Write-Output "Updating $name if it is installed..."
            winget upgrade $program.Id --accept-package-agreements --accept-source-agreements -h
        }
}

Function Get-SystemDriveFreeSpace {
    $driveLetter = $Env:SystemDrive.Trim(":")
    $drive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$Env:SystemDrive'"

    [PSCustomObject]@{
        DriveLetter = $driveLetter
        FreeBytes = [Int64]$drive.FreeSpace
        FreeGB = [math]::Round(($drive.FreeSpace / 1GB), 2)
    }
}

Function Write-SystemDriveFreeSpaceMetric {
    Param(
        [Parameter(Mandatory)][String]$Label,
        [Parameter(Mandatory)][Object]$Metric
    )

    Write-Output "SYSTEM DRIVE FREE SPACE ($Label): $($Metric.FreeGB) GB ($($Metric.FreeBytes) bytes)"
}

Function Install-PsExec {
    $tempPath = "C:\Temp"
    $psToolsZip = Join-Path -Path $tempPath -ChildPath "PSTools.zip"
    $psToolsExtractPath = Join-Path -Path $tempPath -ChildPath "PSTools"
    $psExecSource = Join-Path -Path $psToolsExtractPath -ChildPath "PsExec.exe"
    $psExecDestination = Join-Path -Path $Env:SystemDrive -ChildPath "PsExec.exe"

    New-Item -Path $tempPath -ItemType Directory -Force | Out-Null
    Remove-Item -Path $psToolsExtractPath -Force -Recurse -ErrorAction SilentlyContinue

    Write-Output "Downloading PsTools from Microsoft Sysinternals..."
    Invoke-WebRequest -Uri https://download.sysinternals.com/files/PSTools.zip -OutFile $psToolsZip

    Write-Output "Extracting PsExec from PsTools..."
    Expand-Archive -Path $psToolsZip -DestinationPath $psToolsExtractPath -Force
    Copy-Item -Path $psExecSource -Destination $psExecDestination -Force
}

Function Install-DotNetFramework48 {
    $script:DotNetFramework48RequiresReboot = $false
    $dotNetRelease = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction SilentlyContinue).Release

    if ($dotNetRelease -ge 528040) {
        Write-Output ".NET Framework 4.8 or higher is installed."
        return
    }

    $dotNetInstallerPath = Join-Path -Path $Env:SystemDrive -ChildPath "Net48.exe"
    Write-Output "Installing .NET Framework 4.8..."
    Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=2088631" -OutFile $dotNetInstallerPath
    $dotNetInstall = Start-Process -FilePath $dotNetInstallerPath -ArgumentList "/q", "/norestart" -Wait -PassThru

    if ($dotNetInstall.ExitCode -notin 0, 3010) {
        throw ".NET Framework 4.8 installation failed with exit code $($dotNetInstall.ExitCode)."
    }

    if ($dotNetInstall.ExitCode -eq 3010) {
        $script:DotNetFramework48RequiresReboot = $true
        Write-Output ".NET Framework 4.8 installed successfully and requires a reboot."
    }
}

Function Install-HPImageAssistantUpdates {
    $hpiaPageUri = "https://ftp.ext.hp.com/pub/caps-softpaq/cmit/HPIA.html"
    $hpiaBasePath = Join-Path -Path $Env:SystemDrive -ChildPath "Temp\HPIA"
    $hpiaInstallerPath = Join-Path -Path $hpiaBasePath -ChildPath "HPIA-SoftPaq.exe"
    $hpiaToolPath = Join-Path -Path $hpiaBasePath -ChildPath "Tool"
    $hpiaDownloadPath = Join-Path -Path $hpiaBasePath -ChildPath "Downloads"
    $hpiaReportTimestamp = Get-Date -Format "yyyy-MM-dd_HH.mm.ss"
    $hpiaReportPath = Join-Path -Path $hpiaBasePath -ChildPath "Reports\$hpiaReportTimestamp"

    Install-DotNetFramework48
    if ($script:DotNetFramework48RequiresReboot) {
        throw ".NET Framework 4.8 requires a reboot before HP Image Assistant can run."
    }

    New-Item -Path $hpiaBasePath -ItemType Directory -Force | Out-Null
    Remove-Item -Path $hpiaToolPath -Recurse -Force -ErrorAction SilentlyContinue

    Write-Output "Finding the latest HP Image Assistant SoftPaq..."
    $hpiaPage = Invoke-WebRequest -Uri $hpiaPageUri -UseBasicParsing
    $hpiaDownloadUri = $hpiaPage.Links |
        Where-Object { $_.href -match "^https://hpia\.hpcloud\.hp\.com/downloads/hpia/hp-hpia-[0-9.]+\.exe$" } |
        Select-Object -First 1 -ExpandProperty href

    if ([string]::IsNullOrWhiteSpace($hpiaDownloadUri)) {
        $hpiaDownloadMatch = [regex]::Match(
            $hpiaPage.Content,
            "https://hpia\.hpcloud\.hp\.com/downloads/hpia/hp-hpia-[0-9.]+\.exe"
        )
        $hpiaDownloadUri = $hpiaDownloadMatch.Value
    }

    if ([string]::IsNullOrWhiteSpace($hpiaDownloadUri)) {
        throw "Unable to find the current HP Image Assistant download on HP's official page."
    }

    Write-Output "Downloading HP Image Assistant from $hpiaDownloadUri..."
    Invoke-WebRequest -Uri $hpiaDownloadUri -OutFile $hpiaInstallerPath

    $hpiaSignature = Get-AuthenticodeSignature -FilePath $hpiaInstallerPath
    if ($hpiaSignature.Status -ne "Valid" -or $hpiaSignature.SignerCertificate.Subject -notmatch "HP Inc") {
        throw "The downloaded HP Image Assistant SoftPaq did not have a valid HP digital signature."
    }

    Write-Output "Extracting HP Image Assistant..."
    $hpiaExtract = Start-Process -FilePath $hpiaInstallerPath -ArgumentList "/s", "/e", "/f", $hpiaToolPath -Wait -PassThru
    $hpiaExecutable = Get-ChildItem -Path $hpiaToolPath -Filter "HPImageAssistant.exe" -File -Recurse |
        Select-Object -First 1
    if (-not $hpiaExecutable) {
        throw "HPImageAssistant.exe was not found after extracting the SoftPaq. Wrapper exit code: $($hpiaExtract.ExitCode)."
    }
    if ($hpiaExtract.ExitCode -ne 0) {
        Write-Output "HP's SoftPaq wrapper returned exit code $($hpiaExtract.ExitCode), but HPImageAssistant.exe was extracted successfully."
    }

    foreach ($category in "Drivers", "Firmware") {
        $categoryDownloadPath = Join-Path -Path $hpiaDownloadPath -ChildPath $category
        $categoryReportPath = Join-Path -Path $hpiaReportPath -ChildPath $category
        New-Item -Path $categoryDownloadPath -ItemType Directory -Force | Out-Null
        New-Item -Path $categoryReportPath -ItemType Directory -Force | Out-Null

        Write-Output "Analyzing and installing HP $category updates..."
        $hpiaArguments = @(
            "/Operation:Analyze",
            "/Category:$category",
            "/Selection:All",
            "/Action:Install",
            "/Silent",
            "/AutoCleanup",
            "/IgnoreGenericOsError",
            "/ReportFolder:$categoryReportPath",
            "/SoftPaqDownloadFolder:$categoryDownloadPath"
        )
        $hpiaProcess = Start-Process -FilePath $hpiaExecutable.FullName -ArgumentList $hpiaArguments -Wait -PassThru

        switch ($hpiaProcess.ExitCode) {
            0 { Write-Output "HP $category updates completed successfully." }
            256 { Write-Output "HP Image Assistant found no $category recommendations." }
            257 { Write-Output "HP Image Assistant found no selected $category recommendations." }
            3010 { Write-Output "HP $category updates completed successfully and require a reboot." }
            3011 {
                Write-Output "WARNING ---------- One or more HP $category updates require manual installation and were skipped."
                $script:ErrorCount += 1
                $script:ErrorLog += "One or more HP $category updates require manual installation.  "
            }
            default {
                throw "HP Image Assistant $category processing failed with exit code $($hpiaProcess.ExitCode)."
            }
        }
    }

    Remove-Item -Path $hpiaInstallerPath -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $hpiaToolPath -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $hpiaDownloadPath -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output "HP Image Assistant reports retained at $hpiaReportPath"
}

Function Invoke-OrphanedInstallerCacheCleanup {
    Param(
        [Parameter()][Switch]$Purge
    )

    $installerCachePath = Join-Path -Path $Env:SystemRoot -ChildPath "Installer"
    $quarantineBasePath = "C:\Temp\InstallerCacheQuarantine"
    $timestamp = Get-Date -Format o | ForEach-Object { $_ -replace ":", "." }
    $stagingPath = Join-Path -Path $quarantineBasePath -ChildPath $timestamp
    $stagedFilesPath = Join-Path -Path $stagingPath -ChildPath "Files"
    $manifestPath = Join-Path -Path $stagingPath -ChildPath "manifest.csv"
    $archivePath = Join-Path -Path $quarantineBasePath -ChildPath "OrphanedInstallerCache-$timestamp.zip"
    $referencedInstallerFiles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    if (-not (Test-Path -Path $installerCachePath)) {
        Write-Output "Windows Installer cache path not found, skipping orphaned installer cache cleanup..."
        return
    }

    Write-Output "Auditing Windows Installer cache references..."
    $installerRegistryRoots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Installer\UserData"
    )

    foreach ($registryRoot in $installerRegistryRoots) {
        if (-not (Test-Path -Path $registryRoot)) {
            continue
        }

        Get-ChildItem -Path $registryRoot -Recurse -ErrorAction SilentlyContinue |
            Get-ItemProperty -Name LocalPackage -ErrorAction SilentlyContinue |
            ForEach-Object {
                if (-not [string]::IsNullOrWhiteSpace($_.LocalPackage)) {
                    try {
                        $fullPath = [System.IO.Path]::GetFullPath($_.LocalPackage)
                        $referencedInstallerFiles.Add($fullPath) | Out-Null
                    } catch {
                        Write-Output "Unable to normalize installer reference $($_.LocalPackage)"
                    }
                }
            }
    }

    $installerCacheFiles = Get-ChildItem -Path (Join-Path -Path $installerCachePath -ChildPath "*") -File -Include "*.msi", "*.msp" -ErrorAction SilentlyContinue
    $orphanedInstallerFiles = $installerCacheFiles | Where-Object {
        -not $referencedInstallerFiles.Contains($_.FullName)
    }

    if (-not $orphanedInstallerFiles) {
        Write-Output "No orphaned Windows Installer cache files found."
        return
    }

    Write-Output "Found $($orphanedInstallerFiles.Count) orphaned Windows Installer cache candidate(s)."

    if ($Purge.IsPresent) {
        Write-Output "MSIZap purge mode enabled. Permanently deleting orphaned installer cache candidates..."
        $purgedFileCount = 0

        foreach ($file in $orphanedInstallerFiles) {
            try {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                $purgedFileCount += 1
            } catch {
                Write-Output "WARNING ---------- Failed to permanently delete installer cache candidate $($file.FullName)"
                $script:ErrorCount += 1
                $script:ErrorLog += "Failed to purge installer cache candidate $($file.FullName).  "
            }
        }

        Write-Output "Permanently deleted $purgedFileCount of $($orphanedInstallerFiles.Count) orphaned installer cache candidate(s)."
        return
    }

    New-Item -Path $stagedFilesPath -ItemType Directory -Force | Out-Null

    $quarantinedFiles = @()
    $manifest = foreach ($file in $orphanedInstallerFiles) {
        try {
            $hash = Get-FileHash -Path $file.FullName -Algorithm SHA256 -ErrorAction Stop
            Copy-Item -Path $file.FullName -Destination (Join-Path -Path $stagedFilesPath -ChildPath $file.Name) -Force -ErrorAction Stop
            $quarantinedFiles += $file

            [PSCustomObject]@{
                OriginalPath = $file.FullName
                FileName = $file.Name
                Length = $file.Length
                LastWriteTimeUtc = $file.LastWriteTimeUtc.ToString("o")
                SHA256 = $hash.Hash
                Reason = "Not referenced by registered Windows Installer LocalPackage data"
            }
        } catch {
            Write-Output "WARNING ---------- Failed to stage installer cache candidate $($file.FullName)"
        }
    }

    if (-not $quarantinedFiles) {
        Write-Output "No orphaned Windows Installer cache candidates could be staged for quarantine."
        Remove-Item -Path $stagingPath -Force -Recurse -ErrorAction SilentlyContinue
        return
    }

    $manifest | Export-Csv -Path $manifestPath -NoTypeInformation

    Write-Output "Compressing orphaned installer cache candidates to $archivePath..."
    Compress-Archive -Path (Join-Path -Path $stagingPath -ChildPath "*") -DestinationPath $archivePath -CompressionLevel Optimal -Force

    if (Test-Path -Path $archivePath) {
        foreach ($file in $quarantinedFiles) {
            Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -Path $stagingPath -Force -Recurse -ErrorAction SilentlyContinue
        Write-Output "Archived and removed orphaned installer cache candidates. Archive retained at $archivePath"
    } else {
        Write-Output "WARNING ---------- Failed to create installer cache quarantine archive; original files were not removed."
        $script:ErrorCount += 1
        $script:ErrorLog += "Failed to create installer cache quarantine archive.  "
    }
}

#Step 0 - Initialize some stuff.
try {
    Invoke-WebRequest -uri https://github.com -UseBasicParsing
} catch {
    Write-Output "No github access!  Checking for json, reg files..."
    if ((Test-Path -Path $Env:SystemDrive\UserTempFileLocations.json) -and (Test-Path -Path $Env:SystemDrive\TuneUpReg.reg)) {
        Write-Output "Files found!  Continuing..."
    } else {
        Write-Output "Files not found!"
        throw "NO GITHUB ACCESS.  DOWNLOAD JSON AND REG FILES MANUALLY AND PLACE IN THE ROOT OF THE SYSTEM DRIVE" 
    }
}
$timestamp = Get-Date -Format o | ForEach-Object { $_ -replace ":", "." }
Start-Transcript -Path "$Env:SystemDrive\MaintenanceOutput-$timestamp.txt"
$StartingSystemDriveFreeSpace = Get-SystemDriveFreeSpace
Write-SystemDriveFreeSpaceMetric -Label "START" -Metric $StartingSystemDriveFreeSpace
$ErrorCount = 0 #0 = no, >0 = yes
$ErrorLog = ""
$HomeSKU = $false
$SystemDriveLetter = $Env:SystemDrive.Trim(":")
try {
    winget
} catch {
    if ([string]::IsNullOrEmpty($AttendedRun)) {
        Write-Output "Machine missing winget!!!!!"
        Write-Output "Cannot install Winget in System scope, relaunch script in attended mode and run as logged-in user!"
    } else {
        Install-WinGet
    }
}

#Step 1 - Sign out all users (unless we're on an attended run in which case skip the specified user)
#Check to see if we're on a SKU that can actually do this because Home can't...
$edition = Get-WindowsEdition -Online
if ($edition.Edition -notcontains "Home") {
    if ([string]::IsNullOrEmpty($AttendedRun)) {
        #log everyone off
        Write-Output "Logging off all users..."
        quser | Select-Object -Skip 1 | ForEach-Object {
            $id = ($_ -split ' +')[-6]
            if($id -match "^\d+$") {
                logoff $id
            } else {
                $id = ($_ -split ' +')[-5]
                if($id -match "^\d+$") {
                    logoff $id
                } else {
                    $id = ($_ -split ' +')[-7]
                    if($id -match "^\d+$") {
                        logoff $id
                    } else {
                        Write-Output "Something really went wacky here, unable to sign someone out?"
                        $ErrorCount++
                        $ErrorLog += "Error signing people out!  "
                    }
                }
            }
        }
    } else {
        #log off all users except the specified user
        Write-Output "Logging off all users except for $AttendedRun..."
        $users = (((quser) -replace '^>', '') -replace '\s{2,}', ',').Trim() | ForEach-Object { if ($_.Split(',').Count -eq 5) { Write-Output ($_ -replace '(^[^,]+)', '$1,')} else { Write-Output $_ } } | ConvertFrom-Csv
        ForEach ($user in $users) {
         if ([string]$user.username -like "*$AttendedRun*") {
             Write-Output "Skipping $AttendedRun..."
         } else {
             logoff $user.ID
         }
        }
    }
} else {
    Write-Output "Home SKU, no query support, skipping to next step..."
    Write-Output "!!! ---- WARNING: Assume there will be errors on temp file cleanup since we can't ensure everyone is signed out. ---- !!!"
    $ErrorCount += 1
    $ErrorLog += "Home SKU - WARNING - cannot log out users.  "
    $HomeSKU = $true
    #Maybe in the future reboot the PC and then run the script again with a flag.
}

#Step 2 - Clean up temp files, caches, Java stuff, etc in all user profiles
Write-Output "Starting user temp file & cache cleanup..."
if ($HomeSKU -eq $TRUE) {
    Write-Output "------------- FAIR WARNING YOU ARE GONNA SEE SOME ERRORS HERE -------------"
    Write-Output "------------------ HOME SKU CAN NOT SIGN OUT OTHER USERS ------------------"
}
foreach ($user in Get-Childitem "$Env:SystemDrive\Users") {
    Write-Output "Cleaning up $user..."
    $Path = "$Env:SystemDrive\Users\$user"
    Invoke-WebRequest -Uri https://raw.githubusercontent.com/KoshiirRa/script-assets/main/UserTempFileLocations.json -OutFile "$Env:SystemDrive\UserTempFileLocations.json"
    $paths = Get-Content "$Env:SystemDrive\UserTempFileLocations.json" | Out-String | ConvertFrom-Json
    foreach ($tempPath in $paths) {
        $removePath = $tempPath.Path
        if ($tempPath.Recurse -eq "TRUE") {
            Write-Output "Clearing $Path$removePath..."
            Remove-Item -Force -Recurse "$path$removePath" -ErrorAction SilentlyContinue
        } else {
            Write-Output "Clearing $Path$removePath..."
            Remove-Item -Force "$path$removePath" -ErrorAction SilentlyContinue
        }
    }
    Write-Output "---------------------------------"
}
Write-Output "Done cleaning up user temp files and caches..."

#Step 3 - Clear the CL Cache (yeah this isn't powershell code, there isn't actually powershell support for this?)
Write-Output "Clearing the CL Cache..."
Invoke-Command {certutil -URLcache * delete}

#Step 4 - Check and see if old versions of Windows still exist after an upgrade, and delete them if they do
$WindowsOldPath = Join-Path -Path $Env:SystemDrive -ChildPath 'Windows.old'
if (Test-Path -Path $WindowsOldPath) {
    Write-Output "Cleaning up $WindowsOldPath..."
    takeown /F "$WindowsOldPath\*" /R /A /D Y
    icacls "$WindowsOldPath" /grant "*S-1-5-32-544:(OI)(CI)F" /T /C
    Remove-Item -Force -Recurse $WindowsOldPath -ErrorAction SilentlyContinue
}
$WindowsBTPath = Join-Path -Path $Env:SystemDrive -ChildPath '$Windows.~BT'
if (Test-Path -Path $WindowsBTPath) {
    Write-Output "Cleaning up $WindowsBTPath..."
    takeown /F "$WindowsBTPath\*" /R /A /D Y
    icacls "$WindowsBTPath" /grant "*S-1-5-32-544:(OI)(CI)F" /T /C
    Remove-Item -Force -Recurse $WindowsBTPath -ErrorAction SilentlyContinue
}
$WindowsWSPath = Join-Path -Path $Env:SystemDrive -ChildPath '$Windows.~WS'
if (Test-Path -Path $WindowsWSPath) {
    Write-Output "Cleaning up $WindowsWSPath..."
    takeown /F "$WindowsWSPath\*" /R /A /D Y
    icacls "$WindowsWSPath" /grant "*S-1-5-32-544:(OI)(CI)F" /T /C
    Remove-Item -Force -Recurse $WindowsWSPath -ErrorAction SilentlyContinue
}

#Step 5 - Clean up system-wide stuff
#Specifically this is *Windows Only* stuff - application-specific cleanup should be handled down in its own step.
Write-Output "Cleaning up system temp files..."
Remove-Item -Force -Recurse "$Env:SystemRoot\Prefetch\*" -ErrorAction SilentlyContinue
Remove-Item -Force -Recurse "$Env:SystemRoot\Temp\*" -ErrorAction SilentlyContinue
Remove-Item -Force -Recurse "$Env:SystemDrive\Temp\*" -ErrorAction SilentlyContinue
if (Test-Path -Path "$Env:SystemDrive\MSOCache") {
    Write-Output "Cleaning up Office installation cache..."
    Remove-Item -Force -Recurse "$Env:SystemDrive\MSOCache\*" -ErrorAction SilentlyContinue
}
if (Test-Path -Path "$Env:SystemDrive\i386") {
    Write-Output "Cleaning up the Windows installation cache..."
    Remove-Item -Force -Recurse "$Env:SystemDrive\i386" -ErrorAction SilentlyContinue
}
if (Test-Path -Path "$Env:ProgramData\Microsoft\Windows\WER\ReportArchive") {
    Write-Output "Cleaning up archived Windows Error Reporting reports..."
    Remove-Item -Force -Recurse "$Env:ProgramData\Microsoft\Windows\WER\ReportArchive" -ErrorAction SilentlyContinue
}
if (Test-Path -Path "$Env:ProgramData\Microsoft\Windows\WER\ReportQueue") {
    Write-Output "Cleaning up queued Windows Error Reporting reports..."
    Remove-Item -Force -Recurse "$Env:ProgramData\Microsoft\Windows\WER\ReportQueue" -ErrorAction SilentlyContinue
}
if (Test-Path -Path "$Env:ProgramData\Microsoft\Search\Data\Temp") {
    Write-Output "Cleaning up Windows Search temp data..."
    Remove-Item -Force -Recurse "$Env:ProgramData\Microsoft\Search\Data\Temp" -ErrorAction SilentlyContinue
}
### Clean up CBS logs ###
Write-Output "Stopping TrustedInstaller service..." #TrustedInstaller starts again on demand when Windows needs it.
Stop-Service -Name "TrustedInstaller" -Force
Write-Output "Cleaning up CBS Logs..."
Remove-Item -Force -Recurse "$Env:SystemRoot\Logs\CBS\*" -ErrorAction SilentlyContinue
### Clean up Windows Update
Write-Output "Resetting Windows Update and clearing cache..."
Stop-Service -Name wuauserv
Stop-Service -Name BITS
Stop-Service -Name CryptSvc
Remove-Item -Force -Recurse "$Env:SystemRoot\softwaredistribution\" -ErrorAction SilentlyContinue
Remove-Item "$Env:ProgramData\Microsoft\Network\Downloader\qmgr*.dat"
Start-Service -Name BITS
Start-Service -Name wuauserv
Start-Service -Name CryptSvc
### Do Disk Cleanup
Write-Output "Running Disk Cleanup..."
Invoke-WebRequest -Uri https://raw.githubusercontent.com/KoshiirRa/script-assets/main/TuneUpReg.reg -OutFile "$Env:SystemDrive\TuneUpReg.reg" #go grab the registry file to save space in the script...
Invoke-Command {reg import "$Env:SystemDrive\TuneUpReg.reg"} -ErrorAction SilentlyContinue #Far, far saner to import registry files using this than with powershell
try {
    if ([string]::IsNullOrEmpty($AttendedRun)) {
        Install-PsExec #go grab psexec so we can run disc cleanup silently in the background / without active login session
        Invoke-Command {& "$Env:SystemDrive\PsExec.exe" -accepteula -s "cleanmgr" /sagerun:100} 
    } else {
        & cleanmgr.exe /sagerun:100
    }
} catch {
    Write-Output "!!!!! ------ DISK CLEANUP FAILED ------ !!!!!"
    $ErrorCount += 1
    $ErrorLog += "Disk Cleanup failed!  "
}

#STEP 6 - Manufacturer Driver and Firmware Updates
Write-Output "Checking system manufacturer for supported update tooling..."
$PCInfo = Get-CimInstance -ClassName Win32_ComputerSystem
if ($PCInfo.Manufacturer.Contains("Dell")) {
    Write-Output "Dell system detected. Checking for Dell Command Update..."
    Install-PsExec
    if (Test-Path -Path "$Env:ProgramFiles\Dell\CommandUpdate\dcu-cli.exe") {
        Write-Output "Found Dell Command Update!"
        Write-Output "Scanning for updates via Dell Command CLI..."
        Invoke-Command {& "$Env:SystemDrive\PsExec.exe" -accepteula -s "$Env:ProgramFiles\Dell\CommandUpdate\dcu-cli.exe" /scan} -ErrorVariable ErrorVar
        if ([string]$ErrorVar -like "*error code 0*") {
            Write-Output "Installing Dell updates..."
            Invoke-Command {& "$Env:SystemDrive\PsExec.exe" -accepteula -s "$Env:ProgramFiles\Dell\CommandUpdate\dcu-cli.exe" /applyUpdates}
        } else {
            if ([string]$ErrorVar -like "error code 3") {
                Write-Output "Something went wrong, this isn't actually a Dell!"
            }
            if ([string]$ErrorVar -like "error code 2") {
                Write-Output "An unknown application error has occurred."
                $ErrorCount += 1
                $ErrorLog += "Dell Command Update had an unknown error.  "
            }
            if ([string]$ErrorVar -like "error code 4") {
                Write-Output "Reboot pending, can't patch yet!"
                $ErrorCount += 1
                $ErrorLog += "Machine needs a reboot before it can run Command Update.  "
            }
            if ([string]$ErrorVar -like "error code 5") {
                Write-Output "Reboot pending from previous Command Update operations"
                $ErrorCount += 1
                $ErrorLog += "Machine needs a reboot before it can run Command Update again.  "
            }
            if ([string]$ErrorVar -like "error code 7") {
                Write-Output "This Dell is not supported by Command Update!"
                $ErrorCount += 1
                $ErrorLog += "Dell machine not supported by Command Update.  "
            } else {
                Write-Output "Unknown Error from Command Update!"
                Write-Output [string]$ErrorVar
                $ErrorCount += 1
                $ErrorText = [string]$ErrorVar
                $ErrorLog += "Unknown Command Update Error - $ErrorText"
            }
        }
    } else {
        Write-Output "Dell Command Update not present...attempting install..."
        Install-DotNetFramework48
        Write-Output "Proceeding to Dell Command Update install..."
        Write-Output "Downloading Dell Command Update installer..."
        Invoke-WebRequest -Uri "https://github.com/NetlinkSolutions/Script-Assets/raw/main/DellCommandSetup.exe" -OutFile "$Env:SystemDrive\DellCommandSetup.exe"
        Write-Output "Installing Dell Command Update..."
        Start-Service -Name "TrustedInstaller"
        Invoke-Command {& "$Env:SystemDrive\PsExec.exe" -accepteula -s "$Env:SystemDrive\DellCommandSetup.exe" /S /v /qn} -ErrorVariable ErrorVar
        if ($ErrorVar.Contains("error code 1602")) {
            #this means that the old version of dell command is installed
            #find a way to strip it out automatically at some point
            #$OldCommandUpdate = Get-CimInstance -ClassName Win32_Product | Where-Object {$_.Name -match "Dell Command"}
            #$DellPackage = Get-Package -Provider Programs -IncludeWindowsInstaller -Name $OldCommandUpdate.Name
            #check for nuget, install if not available
            Write-Output "!!!!! ------ OLDER DELL COMMAND VERSION FOUND, REMOVE AND TRY AGAIN ------ !!!!!"
            $ErrorCount += 1
            $ErrorLog += "Old Dell Command Update version requires manual removal at this time.  "
        } else {
            Write-Output "Scanning for and installing updates via Dell Command CLI..."
            Invoke-Command {& "$Env:SystemDrive\PsExec.exe" -accepteula -s "$Env:ProgramFiles\Dell\CommandUpdate\dcu-cli.exe" /scan}
            Invoke-Command {& "$Env:SystemDrive\PsExec.exe" -accepteula -s "$Env:ProgramFiles\Dell\CommandUpdate\dcu-cli.exe" /installUpdates}
        }
    }
} elseif ($PCInfo.Manufacturer.Contains("Microsoft")) {
    if ($PCInfo.Model.Contains("Surface")) {
        # Surface
        Write-Output "There's no good way to roll Surface driver and firmware updates into this, go do it yourself."
    } elseif ($PCInfo.Model.Contains("Virtual")) {
        # Hyper-V VM
        Write-Output "This is a Hyper-V VM - it doesn't need driver updates."
    }
} elseif ($PCInfo.Manufacturer -match "^(HP|Hewlett-Packard)") {
    Write-Output "HP system detected. Running HP Image Assistant..."
    try {
        Install-HPImageAssistantUpdates
    } catch {
        Write-Output "WARNING ---------- HP Image Assistant failed: $($_.Exception.Message)"
        $ErrorCount += 1
        $ErrorLog += "HP Image Assistant failed: $($_.Exception.Message)  "
    }
} else {
    $Manufacturer = $PCInfo.Manufacturer
    Write-Output "This is a $Manufacturer. Marty needs to write support for this manufacturer."
    $ErrorCount += 1
    $ErrorLog += "Hey Marty, this isn't a Dell.  Please program in support for $Manufacturer.  "
}

#STEP 7 - Check For And Force Repairs on Windows, Windows Image, and C drive
try {
    Write-Output "Running SFC /SCANNOW..."
    Invoke-Command {sfc /scannow}
} catch {
    $ErrorCount += 1
    $ErrorLog += "Something went wrong with sfc /scannow!  "
    Write-Output "As you can see, something went wrong with SFC /SCANNOW."
}
try {
    Write-Output "Checking Windows Image health..."
    Repair-WindowsImage -Online -CheckHealth -NoRestart
    Write-Output "Scanning Windows Image health..."
    Repair-WindowsImage -Online -ScanHealth -NoRestart
    Write-Output "Restoring Windows Image health..."
    Repair-WindowsImage -Online -RestoreHealth -NoRestart
} catch {
    $ErrorCount += 1
    $ErrorLog += "Something went wrong with the Repair-WindowsImage commands.  "
    Write-Output "As you can see, something went wrong with Repair-WindowsImage commands"
}
Write-Output "Checking for system drive errors..."
Repair-Volume -DriveLetter $SystemDriveLetter -SpotFix
Write-Output "Performing maintenance on the system drive..."
Optimize-Volume -DriveLetter $SystemDriveLetter -Analyze -Verbose
Optimize-Volume -DriveLetter $SystemDriveLetter -Defrag
Optimize-Volume -DriveLetter $SystemDriveLetter -SlabConsolidate
$Disk = Get-PhysicalDisk -DeviceNumber 0
if ($Disk.MediaType -eq "SSD") {
    #Do SSD Optimization Things
    Optimize-Volume -DriveLetter $SystemDriveLetter -Retrim
}
Write-Output "How'd we do?"
Optimize-Volume -DriveLetter $SystemDriveLetter -Analyze -Verbose

#STEP 8 - Rebase the OS
#https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/clean-up-the-winsxs-folder?view=windows-11
#Basically the longer the OS goes without this, the bigger the WinSxS folder gets.  This removes all superseded components in the component store.
#Layman's Terms: This removes the ability to uninstall updates
#Kinda weird but /ResetBase and /StartComponentCleanup didn't have equivalents in Repair-WindowsImage in older versions of powershell, so gotta use more Invoke-Command here
if ($NoRebase.IsPresent) {
    Write-Output "Skipping OS rebase per your request..."
} else {
    Write-Output "Resetting the OS base..."
    try {
        Repair-WindowsImage -Online -ResetBase -NoRestart -StartComponentCleanup
    } catch { #older windows/powershell versions don't have the -ResetBase parameter in the Repair-WindowsImage cmdlet
        try {
            Invoke-Command {dism /online /Cleanup-Image /StartComponentCleanup /ResetBase}
        } catch {
            Write-Output "Something screwed up during the OS Rebase?!"
            $ErrorCount += 1
            $ErrorLog += "Something went horribly wrong with OS Rebasing.  "
        }
    }
}

#STEP 9 - Network Cleanup
Write-Output "Clearing the DNS and ARP caches..."
try {
    Clear-DnsClientCache
    Invoke-Command {netsh interface ip delete arpcache} #Another one with no powershell equivalent?
    Invoke-Command {netsh winsock reset catalog}
} catch {
    $ErrorCount += 1
    $ErrorLog += "Something went wrong with cleaning up the DNS and ARP caches.  "
    Write-Output "WARNING ------- Something went wrong with cleaning up the DNS and ARP caches..."
}

#STEP 10 - Windows Installer Cache Cleanup
#This audits Windows Installer cache files and either quarantines orphaned candidates or permanently deletes them in purge mode.
if ($NoMSIZap.IsPresent) {
    Write-Output "Skipping Windows Installer cache cleanup per your request..."
} else 
{
    try {
        Invoke-OrphanedInstallerCacheCleanup -Purge:$MSIZapPurge
    } catch {
        $ErrorCount += 1
        $ErrorLog += "Something went wrong with Windows Installer cache cleanup.  "
        Write-Output "WARNING ---------- Something went wrong with Windows Installer cache cleanup"
    }
}

#STEP 11 - Application-Specific Cleanup
#I'M LOOKING AT YOU, TEAMS AND ADOBE!
Write-Output "Cleaning up Microsoft Teams cache..."
Get-ChildItem "$Env:SystemDrive\Users\*\AppData\Roaming\Microsoft\Teams\*" -directory | Where name -in ('service worker','application cache','blob storage','databases','GPUcache','IndexedDB','Local Storage','tmp') | ForEach {Remove-Item $_.FullName -Recurse -Force}

Write-Output "---------------------------------"
if (Test-Path -Path "$Env:ProgramData\Adobe") {
    Write-Output "Cleaning up Adobe's mess..."
    Remove-Item -Force -Recurse "$Env:ProgramData\Adobe\Setup\*" -ErrorAction SilentlyContinue
    Remove-Item -Force -Recurse "$Env:ProgramData\Adobe\ARM\*" -ErrorAction SilentlyContinue
    Write-Output "---------------------------------"    
}
Get-ChildItem "$Env:SystemDrive\Users\*\AppData\Local\Microsoft.AAD.BrokerPlugin_cw5n1h2txyewy\*" -directory | ForEach {Remove-Item $_.FullName -Recurse -Force}
Write-Output "Cleaning up QuickBooks cache..."
Get-ChildItem "C:\ProgramData\Intuit\QuickBooks 20*\Components\DownloadQB*\SPatch*.dat" -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem "C:\ProgramData\Intuit\QuickBooks 20*\Components\QBUpdateCache" -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem "C:\ProgramData\Intuit\Quickbooks Enterprise Solutions*\Components\DownloadQB*" -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem "C:\ProgramData\Intuit\Quickbooks Enterprise Solutions*\Components\QBUpdateCache*" -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

#STEP 12 - Use Winget to upgrade specific applications
Write-Output "Checking to see if we can use winget to do program updates..."
if ((Get-CimInstance Win32_OperatingSystem).version -gt 10.0.16299) {#Are we new enough to have winget?
    try {
        WingetPatching
    } catch {
        Write-Output "Where is Winget?  Attempting to install Winget!"
        Install-WinGet
        try {
            WingetPatching
        } catch {
            Write-Output "Nope still no Winget.  Skipping the rest of this."
        }
    }
} else { 
    Write-Output "Winget not available.  Have a sadface :("
    $ErrorCount += 1
    $ErrorLog += "Winget is not available, cannot perform application updates.  WARNING THAT MEANS THIS MACHINE IS RUNNING A REALLY OLD VERSION OF WINDOWS 10.  "
}

#STEP 13 - Windows Defender Operations
$PSStatus = Get-MpComputerStatus
if ($PSStatus.RealTimeProtectionEnabled -ne "TRUE" -or $PSStatus.IoavProtectionEnabled -ne "TRUE") {
    Write-Output "Antimalware service not enabled!  Attempting to enable..."
    try {
        Set-MpPreference -DisableRealtimeMonitoring $false
        Set-MpPreference -DisableIOAVProtection $false
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "Real-Time Protection" -Force
        New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableBehaviorMonitoring" -Value 0 -PropertyType DWORD -Force
        New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableOnAccessProtection" -Value 0 -PropertyType DWORD -Force
        New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" -Name "DisableScanOnRealtimeEnable" -Value 0 -PropertyType DWORD -Force
        New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender" -Name "DisableAntiSpyware" -Value 0 -PropertyType DWORD -Force
        Start-Service WinDefend
        Start-Service WdNisSvc
    } catch {
        Write-Output "!!!!! ------ UNABLE TO ACTIVATE WINDOWS DEFENDER ------ !!!!!"
        $SkipDefender = "TRUE"
        $ErrorCount += 1
        $ErrorLog += "Unable to activate Windows Defender.  "
    }
}
if ($SkipDefender.IsPresent -or $SkipDefender -eq "TRUE") {
    Write-Output "!!!!! ------ SKIPPING DEFENDER RUN ------ !!!!!"
} else {
    Write-Output "Updating Windows Defender, running a full scan, and removing threats..."
    Update-MpSignature -UpdateSource MicrosoftUpdateServer
    Start-MpScan -ScanType FullScan
    Remove-MpThreat
}

#STEP 14 - Clean up after ourselves and optionally reboot
Remove-Item -Path "$Env:SystemDrive\PsExec.exe" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Temp\PSTools.zip" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Temp\PSTools" -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item -Path "$Env:SystemDrive\DellCommandSetup.exe" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$Env:SystemDrive\TuneUpReg.reg" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$Env:SystemDrive\MaintainedPrograms.json" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$Env:SystemDrive\UserTempFileLocations.json" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$Env:SystemDrive\Net48.exe" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$Env:SystemDrive\Temp\HPIA\HPIA-SoftPaq.exe" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$Env:SystemDrive\Temp\HPIA\Tool" -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item -Path "$Env:SystemDrive\Temp\HPIA\Downloads" -Force -Recurse -ErrorAction SilentlyContinue
if ($ErrorCount -gt 0) {
    Write-Output "I HAD $ErrorCount ERRORS!"
    Write-Output "FINAL ERROR LOG FOLLOWS:"
    Write-Output $ErrorLog
    $logTimestamp = Get-Date -Format o | ForEach-Object { $_ -replace ":", "." }
    $ErrorLog += "  TIMESTAMP: $logTimestamp"
} else {
    Write-Output "I HAD NO ERRORS :D"
    $logTimestamp = Get-Date -Format o | ForEach-Object { $_ -replace ":", "." }
    $ErrorLog += "  TIMESTAMP: $logTimestamp"
}
$EndingSystemDriveFreeSpace = Get-SystemDriveFreeSpace
Write-SystemDriveFreeSpaceMetric -Label "END" -Metric $EndingSystemDriveFreeSpace
$FreedSystemDriveBytes = $EndingSystemDriveFreeSpace.FreeBytes - $StartingSystemDriveFreeSpace.FreeBytes
$FreedSystemDriveGB = [math]::Round(($FreedSystemDriveBytes / 1GB), 2)
Write-Output "SYSTEM DRIVE FREE SPACE CHANGE: $FreedSystemDriveGB GB ($FreedSystemDriveBytes bytes)"
if ($RebootWhenDone.IsPresent) {
    Write-Output "Rebooting..."
    Stop-Transcript
    Restart-Computer -Force
} else {
    Write-Output "Cleanup completed. The computer will not reboot unless -RebootWhenDone is specified."
    Stop-Transcript
}

﻿# WinGet  installer

<#
TODO

#>
<#

Notes
Requires: PowerShellGet module 

As of 9/26/25...

Name                          Id                             Version      Match            Source
--------------------------------------------------------------------------------------------------
Adobe Express                 9P94LH3Q1CP5                   Unknown                       msstore
Adobe Photoshop               XPFD4T9N395QN6                 Unknown                       msstore
Adobe Creative Cloud          XPDLPKWG9SW2WD                 Unknown                       msstore
Adobe Acrobat Reader DC       XPDP273C0XHQH2                 Unknown                       msstore
Adobe Photoshop Express       9WZDNCRFJ27N                   Unknown                       msstore
Adobe Premiere Elements 2025  XPDCG0J5HFNTKX                 Unknown                       msstore
Adobe Fresco                  XP8C8R0ZKZR27V                 Unknown                       msstore
Adobe Acrobat Reader (32-bit) Adobe.Acrobat.Reader.32-bit    25.001.20693 Tag: adobe       winget
Adobe Acrobat Reader (64-bit) Adobe.Acrobat.Reader.64-bit    25.001.20744 Tag: adobe       winget
Avocode                       Avocode.Avocode                4.15.6       Tag: adobe       winget
Adobe Acrobat Pro             Adobe.Acrobat.Pro              25.001.20693                  winget
Adobe Connect                 Adobe.AdobeConnect             21.11.22                      winget
Brackets                      Adobe.Brackets                 1.14.17770                    winget
Adobe Connect                 Adobe.Connect                  2025.8.189                    winget
Adobe Connect application MSI Adobe.Connect.MSI              25.8.189                      winget
Adobe Creative Cloud          Adobe.CreativeCloud            6.7.0.278                     winget
Cryptr                        Adobe.Cryptr                   0.6.0                         winget
Adobe DNG Converter           Adobe.DNGConverter             17.5                          winget
Workfront Proof               Adobe.WorkfrontProof           2.1.52                        winget
Adobe AIR                     HARMAN.AdobeAIR                51.2.1.5                      winget
FileOpen Client               FileOpenSystems.FileOpenClient 1.0.142.1016 Tag: adobereader winget

#>

# 

Param(

    [Parameter(Mandatory=$true)]
    [String]$AppName = $null,

    [Parameter(Mandatory=$true)]
    [String]$AppID = $null,

    [Parameter(Mandatory=$true)]
    [String]$WorkingDirectory, # Recommended param: "C:\ProgramData\COMPANY_NAME"


    [Parameter(Mandatory=$false)]
    $Version = $null,
    
    #[String]$VerboseLogs = $True,
    [int]$timeoutSeconds = 900 # Timeout in seconds (300 sec = 5 minutes)

)


### Other Vars ###
$LogRoot = "$WorkingDirectory\Logs\Installer_Logs"
$SafeAppID = $AppName -replace '[^\w]', '_'
$LogPath = "$LogRoot\$AppName.$SafeAppID._WinGet_Installer_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

#################
### Functions ###
#################

# NOTE: This function will not use write-log.
function Test-PathSyntaxValidity {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Paths,
        [switch]$ExitOnError
    )
    
    # Windows illegal path characters (excluding : for drive letters and \ for path separators)
    $illegalChars = '[<>"|?*]'
    
    # Reserved Windows filenames
    $reservedNames = @(
        'CON', 'PRN', 'AUX', 'NUL',
        'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
        'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9'
    )
    
    $allValid = $true
    $issues = @()
    
    foreach ($paramName in $Paths.Keys) {
        $path = $Paths[$paramName]
        
        # Skip if null or empty
        if ([string]::IsNullOrWhiteSpace($path)) {
            $issues += "Parameter '$paramName' is null or empty"
            $allValid = $false
            continue
        }
        
        # Check for trailing backslash before closing quote pattern (common BAT file issue)
        if ($path -match '\\["\' + "']$") {
            $issues += "Parameter '$paramName' has trailing backslash before quote: '$path' - This will cause escape character issues"
            $allValid = $false
        }
        
        # Check for illegal characters
        if ($path -match $illegalChars) {
            $matches = [regex]::Matches($path, $illegalChars)
            $foundChars = ($matches | ForEach-Object { $_.Value }) -join ', '
            $issues += "Parameter '$paramName' contains illegal characters ($foundChars): '$path'"
            $allValid = $false
        }
        
        # Check for invalid double backslashes (except at start for UNC paths)
        if ($path -match '(?<!^)\\\\') {
            $issues += "Parameter '$paramName' contains double backslashes (not a UNC path): '$path'"
            $allValid = $false
        }
        
        # Check for reserved Windows names in path components
        $pathComponents = $path -split '[\\/]'
        foreach ($component in $pathComponents) {
            $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($component)
            if ($nameWithoutExt -in $reservedNames) {
                $issues += "Parameter '$paramName' contains reserved Windows name '$nameWithoutExt': '$path'"
                $allValid = $false
            }
        }
        
        # Check for paths that are too long (MAX_PATH = 260 characters in Windows)
        if ($path.Length -gt 260) {
            $issues += "Parameter '$paramName' exceeds maximum path length (260 characters): '$path' (Length: $($path.Length))"
            $allValid = $false
        }
        
        # Check for invalid drive letter format
        if ($path -match '^[a-zA-Z]:' -and $path -notmatch '^[a-zA-Z]:\\') {
            $issues += "Parameter '$paramName' has invalid drive format (missing backslash after colon): '$path'"
            $allValid = $false
        }
        
        # Check for spaces at beginning or end of path (common copy-paste issue)
        if ($path -ne $path.Trim()) {
            $issues += "Parameter '$paramName' has leading or trailing whitespace: '$path'"
            $allValid = $false
        }
    }
    
    # Report results
    if (-not $allValid) {
        Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX PATH VALIDATION FAILED - Issues detected:"
        foreach ($issue in $issues) {
            Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX - $issue"
        }
        
        if ($ExitOnError) {
            Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX Exiting script due to path validation errors"
            Exit 1
        }
    } else {
        Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX Path validation successful - all parameters valid"
    }
    
    #return $allValid

}


function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        "ERROR"   { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "DRYRUN"  { Write-Host $logEntry -ForegroundColor Cyan }
        default   { Write-Host $logEntry }
    }
    
    # Ensure log directory exists
    $logDir = Split-Path $LogPath -Parent
    if (!(Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    Add-Content -Path $LogPath -Value $logEntry
}


Function CheckAndInstall-WinGet {

    Try {

        # 1) Ensure winget (App Installer) is provisioned for SYSTEM
        function Get-WingetPath {
            
            #$base = "${Env:ProgramFiles}\WindowsApps"

            # if (Test-Path $base) {
            #     $candidates = Get-ChildItem $base -Filter "Microsoft.DesktopAppInstaller_*x64__8wekyb3d8bbwe" -ErrorAction SilentlyContinue | Sort-Object Name -Descending
            #     foreach ($c in $candidates) {
            #     $p = Join-Path $c.FullName 'winget.exe'
            #     if (Test-Path $p) { return $p }
            #     }
            # }

            ## Got this snippet from here, all rights to go original writer: https://github.com/SorenLundt/WinGet-Wrapper/blob/main/WinGet-Wrapper.ps1
            $resolveWingetPath = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*__8wekyb3d8bbwe"
            
            if ($resolveWingetPath) {
                $wingetPath = $resolveWingetPath[-1].Path
                $wingetPath = $wingetPath + "\winget.exe"
                Write-Log "WinGet path: $wingetPath"
                return $wingetPath

            ## end of snippet 
            } else {

                return $null

            }
            

        }

        $winget = Get-WingetPath


        # NEEDS TESTING
        if (-not $winget) {

            Write-Log "WinGet not found. Attempting to provision App Installer (offline)..."
            $temp = Join-Path $env:TEMP "AppInstaller"
            New-Item $temp @newItemSplat | Out-Null
            $bundle = Join-Path $temp "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
            
            # Use official shortlink which redirects to the current App Installer bundle
            $url = "https://aka.ms/getwinget"
            Invoke-WebRequest -Uri $url -OutFile $bundle -UseBasicParsing

            try {

                Add-AppxProvisionedPackage -Online -PackagePath $bundle -SkipLicense | Out-Null
                Write-Log "Provisioned App Installer."

            } catch {

                #throw "Provisioning failed: $($_.Exception.Message)"
                Write-Log "Provisioning failed: $_" "ERROR"
                throw "$_"


            }

            Start-Sleep -Seconds 5
            $winget = Get-WingetPath

        }

        # In theory this shouldn't work. In practice it might.
        if (-not $winget){

            Write-Log "WinGet still not found. Attempting to use Install-Script."

            Try{

                Install-Script -Name winget-install -Force -Scope CurrentUser 2>&1
                $result = winget-install
                ForEach ($line in $result) { Write-Log "WINGET-INSTALL: $line" } #; if ($LASTEXITCODE -ne 0) {Write-Log "SCRIPT: $ThisFileName | END | Failed. Exit code: $LASTEXITCODE" "ERROR"; Exit 1 }

                Write-Log "WinGet installed successfully."

            } Catch {
                
                Write-Log "Provisioning failed: $_" "ERROR"
                throw "$_"

            }

            Start-Sleep -Seconds 5
            $winget = Get-WingetPath

        }


        if (-not $winget) { throw "winget.exe still not found after provisioning: $_" }
        
        Write-Log "Successfully resolved WinGet path. Using winget at: $winget"

        # 2) Prep sources (first-run) and install packages
        Write-Log "Prepping WinGet source"
        $result = & $winget source reset --force | Out-String
        ForEach ($line in $result) { Write-Log "WINGET: $line" } #; if ($LASTEXITCODE -ne 0) {Write-Log "SCRIPT: $ThisFileName | END | Failed. Exit code: $LASTEXITCODE" "ERROR"; Exit 1 }
        $result = & $winget source update | Out-String
        ForEach ($line in $result) { Write-Log "WINGET: $line" } #; if ($LASTEXITCODE -ne 0) {Write-Log "SCRIPT: $ThisFileName | END | Failed. Exit code: $LASTEXITCODE" "ERROR"; Exit 1 }

        Return $WinGet

    } Catch {

        Write-Log "SCRIPT: $ThisFileName| END | Install of WinGet failed. Please investigate. Return message: $_" "ERROR"
        Exit 1

    }

    

    # Old version
    <#
    if (!(Get-Command winget -ErrorAction SilentlyContinue)) {

        Write-Log "WinGet not found, beginning installation..."
        # Install and run the winget installer script
        # NOTE: This requires PowerShellGet module
        Try{

            Install-Script -Name winget-install -Force -Scope CurrentUser 2>&1
            $result = winget-install
            ForEach ($line in $result) { Write-Log "WINGET-INSTALL: $line" } #; if ($LASTEXITCODE -ne 0) {Write-Log "SCRIPT: $ThisFileName | END | Failed. Exit code: $LASTEXITCODE" "ERROR"; Exit 1 }

            Write-Log "WinGet installed successfully."

        } Catch {

            Write-Log "SCRIPT: $ThisFileName| END | Install of WinGet failed. Please investigate. Now exiting script." "ERROR"
            Exit 1
        }
        
    } else {
        Write-Log "Winget is already installed"
    }
    #>

}

function WinGet-Detect{
    Param(
    $ID
    )

    Write-Log "Checking if app $ID is installed"

    # May want to remove the --exact if it causes issues
    $result = & $winget list --id "$ID" --exact --disable-interactivity --accept-source-agreements --source winget 2>&1#| Out-String
    ForEach ($line in $result) { Write-Log "WINGET: $line" } #; if ($LASTEXITCODE -ne 0) {Write-Log "SCRIPT: $ThisFileName | END | Failed. Exit code: $LASTEXITCODE" "ERROR"; Exit 1 }

    if ($result -match "$ID") {
        Write-Log "Function: WinGet-Detect | Installation detected of $ID"

        if ($Version -ne $null){

            Write-Log "Now checking if local install is version: $Version"

            if ($result -match $Version) {
                Write-Log "Function: WinGet-Detect | Specific version $Version detected"
                return $true
            } else {
                Write-Log "Function: WinGet-Detect | Requested version $Version NOT detected"
                Write-Log "NOTE: WinGet does not play nice with installing versions lower than your current install version. You must uninstall first if that is your intended purpose." "WARNING"
                return $false
            }

        }



        return $true
    } else {
        Write-Log "Function: WinGet-Detect | Installation not detected of $ID"
        return $false
    }

}

Function Validate-WinGet-Search{

    Write-Log "Checking if AppID $AppID is valid"

    if ($null -eq $Version){

        $result = & $winget show --id $AppId --exact --disable-interactivity --accept-source-agreements --source winget 2>&1 | Out-String
        ForEach ($line in $result) { Write-Log "WINGET: $line" } #; if ($LASTEXITCODE -ne 0) {Write-Log "SCRIPT: $ThisFileName | END | Failed. Exit code: $LASTEXITCODE" "ERROR"; Exit 1 }


    } else {

        Write-Log "Version $Version requested, checking if that exists as well"
        $result = & $winget show --id $AppId --version $Version --exact --disable-interactivity --accept-source-agreements --source winget 2>&1 | Out-String
        ForEach ($line in $result) { Write-Log "WINGET: $line" } #; if ($LASTEXITCODE -ne 0) {Write-Log "SCRIPT: $ThisFileName | END | Failed. Exit code: $LASTEXITCODE" "ERROR"; Exit 1 }

    }

    if ($result -match "No package found") {

        if ($null -eq $Version){
            Write-Log "SCRIPT: $ThisFileName | END | AppID $AppID is not valid. Please use WinGet Search to find a valid ID. Now exiting script." "ERROR"
        } else {
            Write-Log "SCRIPT: $ThisFileName | END | AppID $AppID with version $Version is not valid. Please use WinGet Search to find a valid ID and version. Now exiting script." "ERROR"
        }

        Exit 1

    } else {
        if ($null -eq $Version){
            Write-Log "App ID $AppID is valid. Now proceeding with script."

        } else {
            Write-Log "App ID $AppID with version $Version is valid. Now proceeding with script."

        }
    }

}

############
### Main ###
############

## Pre-Check
$ThisFileName = $MyInvocation.MyCommand.Name
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX PRE-CHECK for SCRIPT: $ThisFileName"
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX NOTE: PRE-CHECK is not logged"
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX Checking if supplied paths are valid"
# Test the paths
$pathsToValidate = @{
    'WorkingDirectory' = $WorkingDirectory
    'LogRoot' = $LogRoot
    'LogPath' = $LogPath
}
Test-PathSyntaxValidity -Paths $pathsToValidate -ExitOnError
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

## Begin main body

Write-Log "===== WinGet Installer Script Started ====="

Write-Log "AppName: $AppName"
Write-Log "AppID: $AppID"
Write-Log "WorkingDirectory: $WorkingDirectory"
Write-Log "Version: $Version"
Write-Log "TmeoutSeconds: $timeoutSeconds"

Write-Log "==========================================="

## Checks

Write-Log "Checking script params"
if ($AppName -eq $null -or $AppID -eq $null){

    Write-Log "SCRIPT: $ThisFileName | END | AppName and/or AppID params are empty. Cannot run script." "ERROR"
    Exit 1

} else {

    Write-Log "Params present. Proceeding with script."
}


$WinGet = CheckAndInstall-WinGet


Validate-WinGet-Search

Write-Log "----- Now attempting to install $appname -----"
# Write-Log "----------------------------------------------"


Write-Log "Target app ID to install: $AppID"
if($Version){ Write-Log "Target version to install: $Version"}

# Check if app ID is already installed
Write-Log "Checking for pre-existing local installation of $AppID $Version..."
$detectPreviousInstallation = WinGet-Detect $AppID
if($detectPreviousInstallation -eq $true){
    
    if ($null -ne $Version){

        Write-Log "Installation of $AppID with version $version already detected! If you need to uninstall this instance, please run the General Uninstall script with the WinGet method." "SUCCESS"    
    
    } else {

        Write-Log "Installation of $AppID already detected! If you need to uninstall this instance, please run the General Uninstall script with the WinGet method." "SUCCESS"

    }

    
    
    $InstallSuccess = $true


# if not...
}else{

    if ($null -ne $Version){

        Write-Log "No pre-existing local installation of $AppID with version $Version, proceeding with installation"


    } else {

        Write-Log "No pre-existing local installation of $AppID, proceeding with installation"


    }

    # Try installation of target ID
    try {
    
        $cmd = "$winget"
        if ($null -eq $Version){
            
            $args = "install --id $AppID -e --silent --accept-package-agreements --accept-source-agreements  --disable-interactivity --source winget"

        } else {
            
            $args = "install --id $AppID --version $Version -e --silent --accept-package-agreements --accept-source-agreements  --disable-interactivity --source winget"

        }

        # Santitize the name of the log path
        $SafeAppID = $AppID -replace '[^\w]', '_'

        $InstallationOutputLog = "$LogRoot\$SafeAppID.InstallationOutputLog_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        $InstallationErrorLog = "$LogRoot\$SafeAppID.InstallationErrorLog_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

        Write-Log "Executing command: $cmd $args"

        Write-Log "Installation Output log for $AppID located at: $InstallationOutputLog"
        Write-Log "Installation Error log for $AppID located at: $InstallationErrorLog"
        

        $proc = Start-Process -FilePath $cmd -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput "$InstallationOutputLog" -RedirectStandardError "$InstallationErrorLog"
        #$proc = Start-Process -FilePath $cmd -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$InstallationOutputLog" -RedirectStandardError "$InstallationErrorLog"

        # Start the process and wait for the process with timeout
        $startTime = Get-Date
        while (-not $proc.HasExited) {
            Start-Sleep -Seconds 10
            $elapsed = (Get-Date) - $startTime
            Write-Log "Time elapsed: $elapsed / $TimeoutSeconds seconds"
            if ($elapsed.TotalSeconds -ge $timeoutSeconds) {
                Write-Log "Timeout reached ($timeoutSeconds seconds) for $AppID. Killing process..." "WARNING"
                try {
                    $proc.Kill()
                    Write-Log "Process killed due to timeout for $AppID" "ERROR"
                } catch {
                    Write-Log "Failed to kill process for $AppID : $_" "ERROR"
                }
                break
            }
        }
        
        
        # If the process exited and had a success code...
        if ($proc.HasExited -and $proc.ExitCode -eq 0) {

            Write-Log "Installation return success exit code, now detecting local installation..."
            $detectInstallation = WinGet-Detect $AppID

            if($detectInstallation -eq $true){

                Write-Log "Local installation detected. Installation successful for $AppID" "SUCCESS"
                $InstallSuccess = $true

            # If process did not exit...
            } elseif(-not $proc.HasExited) {

                Write-Log "Process still running after timeout, unexpected behavior." "WARNING"
                #$InstallSuccess = $false
            
            # If the detect was unsuccessful AND the process did not exit...
            } else {

                $InstallSuccess = $false
                Write-Log "No local installation detected. Install failure of $AppID." "ERROR"
            
            }


        
        } else {
            Write-Log "Install process returned non-zero exit code ($($proc.ExitCode)) for $AppID" "WARNING"
            $InstallSuccess = $false
        }           


    # If installation returns a catchable error...
    } catch {

            

            Write-Log "Install failure of $AppID." "ERROR"
            $InstallSuccess = $false

    }

    # Final Check (sometimes it installs anyways despite returning an error above)
    if ($InstallSuccess -eq $false){


        Write-Log "Running a final check to see if target app installed anyways despite errors: $AppID $Version "

        Start-Sleep -Seconds 5

        $detectInstallation2 = WinGet-Detect $AppID

        if($detectInstallation2 -eq $true) {

            Write-Log "Local installation detected. Installation successful of $AppID $Version" "SUCCESS"
            $InstallSuccess = $true

        } else {

            Write-Log "Final check failed. No local installation of $AppID $Version detected." "ERROR"

        }

    }

}


# Final result
Write-Log "----------------------------------------------"
Write-Log "Final Result:"

if ($InstallSuccess -eq $True) {

    Write-Log "SCRIPT: $ThisFileName | END | Installation of $appname $Version with ID $AppID success!" "SUCCESS"
    Exit 0

} else {

    Write-Log "SCRIPT: $ThisFileName | END | Critical Error: Could not install $appname $Version with ID $AppID" "ERROR"
    Exit 1
}

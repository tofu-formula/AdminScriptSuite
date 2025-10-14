# WinGet  installer

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

    [String]$AppName = $null,
    [String]$AppID = $null,
    [String]$WorkingDirectory = "C:\temp",
    #[String]$VerboseLogs = $True,
    [int]$timeoutSeconds = 900 # Timeout in seconds (300 sec = 5 minutes)

)


### Other Vars ###
$LogRoot = "$WorkingDirectory\Installer_Logs"
$SafeAppID = $AppName -replace '[^\w]', '_'
$LogPath = "$LogRoot\$AppName.$SafeAppID._WinGet_install_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"


#################
### Functions ###
#################

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

function WinGet-Detect{
    Param(
    $ID
    )

    # May want to remove the --exact if it causes issues
    $result = winget list --id "$ID" --exact --accept-source-agreements| Out-String

    if ($result -match "$ID") {
        Write-Log "Function: WinGet-Detect | Installation detected of $ID"
        return $true
    } else {
        Write-Log "Function: WinGet-Detect | Installation not detected of $ID"
        return $false
    }

}


############
### Main ###
############

Write-Log "===== WinGet Installer Script Started ====="

##Checks

Write-Log "Checking params"
if ($AppName -eq $null -or $AppID -eq $null){

    Write-Log "AppName and/or AppID params are empty. Cannot run script." "ERROR"
    Exit 1

} else {

    Write-Log "Params present. Proceeding with script."
}


Write-Log "Checking if AppID $AppID is valid"
$result = winget show --id $AppId --exact 2>&1 | Out-String
if ($result -match "No package found") {
    Write-Log "App ID $AppID is not valid. Please use WinGet Search to find a valid ID. Now exiting script." "ERROR"
    Exit 1
} else {
    Write-Log "App ID $AppID is valid. Now proceeding with script."
}

Write-Log "Checking if WinGet is installed"
if (!(Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Log "WinGet not found, beginning installation..."
    # Install and run the winget installer script
    # NOTE: This requires PowerShellGet module
    Try{

        Install-Script -Name winget-install -Force -Scope CurrentUser
        winget-install

    } Catch {

        Write-Host "Install of WinGet failed. Please investigate. Now exiting script." "ERROR"
        Exit 1
    }
    
} else {
    Write-Host "Winget is already installed"
}

Write-Log "----- Now attempting to install $appname -----"
# Write-Log "----------------------------------------------"


Write-Log "Target app ID to install: $AppID"


# Check if app ID is already installed
Write-Log "Checking for pre-existing local installation of $AppID..."
$detectPreviousInstallation = WinGet-Detect $AppID
if($detectPreviousInstallation -eq $true){
    
    Write-Log "Installation of $AppID already detected! If you need to uninstall this instance, please run the General Uninstall script with the WinGet method." "SUCCESS"
    $InstallSuccess = $true


# if not...
}else{

    Write-Log "No pre-existing local installation of $AppID, proceeding with installation"

    # Try installation of target ID
    try {
    
        $cmd = "winget"
        $args = "install --id $AppID -e --silent --accept-package-agreements --accept-source-agreements"

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

            

            Write-Log "Install failure of $AppID. Will attempt another app ID if there are any assigned remaining." "ERROR"
            $InstallSuccess = $false

    }

    # Final Check (sometimes it installs anyways despite returning an error above)
    if ($InstallSuccess -eq $false){


        Write-Log "Running a final check to see if $AppID installed anyways despite errors."

        Start-Sleep -Seconds 5

        $detectInstallation2 = WinGet-Detect $AppID

        if($detectInstallation2 -eq $true) {

            Write-Log "Local installation detected. Installation successful of $AppID" "SUCCESS"
            $InstallSuccess = $true

        } else {

            Write-Log "Final check failed. No local installation of $AppID detected." "Error"

        }

    }

}


# Final result
Write-Log "----------------------------------------------"
Write-Log "Final Result:"

if ($InstallSuccess -eq $True) {

    Write-Log "Installation of $appname with ID $AppID success!" "SUCCESS"
    Exit 0

} else {

    Write-Log "Critical Error: Could not install $appname with ID $AppID" "ERROR"
    Exit 1
}


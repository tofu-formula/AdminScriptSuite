<#

Based off of the Git_Runner_TEMPLATE.ps1
Simplified - It just downloads/uploads the requested repo, and keeps all the needed safety checks
Meant to be ran straight, no params - CHANGE THE VARS TO MATCH YOUR NEEDS
Useful for running using a tool that doesn't play nice with passing params
Good first step in your endpoint deployment workflow
It's a kinda dumb script that needs
Good as a set-and-forget, leave-it-alone kinda thing


What if you can't pass variables to Git_Runner???
What if you need a quick, simplfied version of the template that just downloads/uploads the repo, even to just get you started?
This script is for these sorts of purposes

Tho honestly I could just make a BAT file that configs the Git_Runner_TEMPLATE to do the same thing as this
But sanity testing is so nice and easy with this one

Notes from ChatGPT

Force InTune to use 64-bit powershell
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\YourScript.ps1

Make WinGet “present and healthy” everywhere

Ensure App Installer across your fleet
Assign App Installer via Microsoft Store app (new) to all devices. This keeps WinGet current and avoids most bootstrap flakiness. 
https://learn.microsoft.com/en-us/windows/msix/app-installer/install-update-app-installer?utm_source=chatgpt.com

Autopilot/OOBE note
App Installer/WinGet CLI is only fully registered after the first user sign‑in; avoid CLI‑based installs during pre‑login phases. Use Store apps (new) or the PowerShell module in SYSTEM during OOBE. 
https://learn.microsoft.com/en-us/windows/package-manager/winget/

Lock down or extend sources via policy (optional)
Use the DesktopAppInstaller CSP/ADMX to restrict sources (e.g., only msstore), add a private REST source, or disable settings. This stabilizes results and reduces surprises. 
https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-desktopappinstaller?utm_source=chatgpt.com

#>

##########
## Vars ##
##########

# Configure these vars as needed!
$RepoNickName = "GITHUB-AdminScriptSuite"
$RepoUrl = "https://github.com/tofu-formula/AdminScriptSuite"
$WorkingDirectory = "C:\ProgramData\TEST" # Like specifically this one. Recommended param: "C:\ProgramData\COMPANY_NAME"
$ThisFileName = "Git Puller"

# Probably don't touch these!
$LocalRepoPath = "$WorkingDirectory\$RepoNickName"
$LogRoot = "$WorkingDirectory\Logs\Git_Logs"
$LogPath = "$LogRoot\Download_Local_Repo._Git_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"




###############
## Functions ##
###############

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

# NOTE: This function will not use write-log.
function Test-PathParameters {
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



Function CheckAndInstall-WinGetOld {

    if (!(Get-Command winget -ErrorAction SilentlyContinue)) {

        Write-Log "WinGet not found, beginning installation..."
        # Install and run the winget installer script
        # NOTE: This requires PowerShellGet module
        Try{

            Install-Script -Name winget-install -Force -Scope CurrentUser
            winget-install
            Write-Log "WinGet installed successfully."

        } Catch {

            Write-Log "SCRIPT: $ThisFileName | END | Install of WinGet failed. Please investigate. Now exiting script." "ERROR"
            Exit 1
        }
        
    } else {
        Write-Log "Winget is already installed"
    }

}

Function CheckAndInstallandRepair-WinGetPSmodule {

    if (!(Get-Command Test-WinGetUserSetting -ErrorAction SilentlyContinue)) {

        Write-Log "WinGetPSmodule not found, beginning installation..."
        # Install and run the WinGetPSmodule installer script
        # NOTE: This requires PowerShellGet module
    

        Write-Log "Installing NuGet..."
        Try {
            Install-PackageProvider -Name NuGet -Force | Out-Null
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
        } Catch {
            Write-Log "Failed to install NuGet: $_" "ERROR"
            Write-Log "SCRIPT: $ThisFileName | END | Install of WinGet failed. Please investigate. Now exiting script." "ERROR"
            Exit 1
        }

        Write-Log "Installing WinGet PowerShell Module..."
        Try {
            Install-Module -Name Microsoft.WinGet.Client -Scope AllUsers -Force
        } Catch {
            Write-Log "Failed to install WinGet PowerShell Module: $_" "ERROR"
            Write-Log "SCRIPT: $ThisFileName | END | Install of WinGet failed. Please investigate. Now exiting script." "ERROR"
            Exit 1
        }

        Write-Log "Importing WinGet PowerShell Module..."
        Try {
            Import-Module Microsoft.WinGet.Client -Force
        } Catch {
            Write-Log "Failed to import WinGet PowerShell Module: $_" "ERROR"
            Write-Log "SCRIPT: $ThisFileName | END | Install of WinGet failed. Please investigate. Now exiting script." "ERROR"
            Exit 1
        }

        # Ensure App Installer/WinGet is in a good state for all users
        Try {
            Repair-WinGetPackageManager -AllUsers -Force
        } Catch {
            Write-Log "Failed to repair WinGetPackageManager: $_" "ERROR"
            Write-Log "SCRIPT: $ThisFileName | END | Install of WinGet failed. Please investigate. Now exiting script." "ERROR"
            Exit 1
        }


        Write-Log "WinGetPSmodule installed successfully."
        
    } else {
        Write-Log "WinGetPSmodule is already installed"
    }

}

function CheckAndInstall-Git {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Log "Git not found. Installing via winget..." "WARNING"
        
        try {

            Write-Log "Checking if WinGet is installed..."
            #CheckAndInstall-WinGet
            CheckAndInstallandRepair-WinGetPSmodule

            Install-WinGetPackage -id Git.Git -Exact -source winget -Scope Machine -silent -accept-package-agreements -accept-source-agreements
            
            # Refresh environment variables
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            
            Write-Log "Git installed successfully!" "SUCCESS"
        }
        catch {
            Write-Log "SCRIPT: $ThisFileName | END | ERROR: Failed to install Git: $_" "ERROR"
            exit 1
        }
    }
    else {
        Write-Log "Git is already installed."
    }
}


##########
## Main ##
##########

## Pre-Check
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX PRE-CHECK for SCRIPT: $ThisFileName"
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX NOTE: PRE-CHECK is not logged"
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX Checking if supplied paths are valid"
# Test the paths


$pathsToValidate = @{
    'WorkingDirectory' = $WorkingDirectory
    'LogRoot' = $LogRoot
    'LogPath' = $LogPath
    'LocalRepoPath' = $LocalRepoPath
}


Test-PathParameters -Paths $pathsToValidate -ExitOnError
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"


## Begin main body


Write-Log "+++++ Git Puller +++++"

Write-Log "RepoNickName: $RepoNickName"
Write-Log "RepoUrl: $RepoUrl"
Write-Log "WorkingDirectory: $WorkingDirectory"

Write-Log "++++++++++++++++++++++"

# Check if git is installed
Write-Log "Checking if Git is installed..."
CheckAndInstall-Git

# Add safe directory configuration
Write-Log "Configuring Git safe directory for: $LocalRepoPath"
try {
    # Check if the directory is already in safe.directory list
    $safeDirectories = git config --global --get-all safe.directory 2>$null
    $normalizedRepoPath = $LocalRepoPath -replace '\\', '/'
    
    if ($safeDirectories -notcontains $LocalRepoPath -and $safeDirectories -notcontains $normalizedRepoPath) {
        Write-Log "Adding $LocalRepoPath to Git safe directories..."
        git config --global --add safe.directory $normalizedRepoPath
        Write-Log "Successfully added to safe directories" "SUCCESS"
    } else {
        Write-Log "Repository already in safe directories"
    }
} catch {
    Write-Log "Note: Could not configure safe directory (non-critical): $_" "WARNING"
}

Write-Log "Now checking if local repo exists..."
# Clone or update repository
if (Test-Path $LocalRepoPath) {

    Write-Log "Local repository exists. Pulling latest changes..."
    Push-Location $LocalRepoPath
    try {
        $gitOutput = git pull 2>&1
        foreach ($line in $gitOutput) {
            Write-Log "GIT: $line"
        }
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "SCRIPT: $ThisFileName | END | Failed to pull latest changes" "ERROR"
            exit 1
        } else {
            Write-Log "Successfully pulled latest changes" "SUCCESS"
        }
    }
    finally {
        Pop-Location
    }
}
else {
    Write-Log "No local repo yet. Cloning repository..."
    $gitOutput = git clone $RepoUrl $LocalRepoPath 2>&1
    foreach ($line in $gitOutput) {
        Write-Log "GIT: $line"
    }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "SCRIPT: $ThisFileName | END | Failed to clone repository" "ERROR"
        exit 1
    } else {
        Write-Log "Successfully cloned repository" "SUCCESS"
    }
}

Write-Log "++++++++++++++++++++++"
    Write-Log "SCRIPT: $ThisFileName | END | Repo: $RepoNickName | Update local repo completed." "SUCCESS"
    Exit 0


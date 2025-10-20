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

Make WinGet "present and healthy" everywhere

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
    
    # Check if WinGet PowerShell module is installed
    $moduleInstalled = Get-Module -ListAvailable -Name Microsoft.WinGet.Client -ErrorAction SilentlyContinue
    
    if (!$moduleInstalled) {
        Write-Log "WinGetPSmodule not found, beginning installation..."
        
        # Install NuGet provider if needed
        Write-Log "Installing NuGet provider..."
        Try {
            $null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
            Write-Log "NuGet provider installed successfully"
        } Catch {
            Write-Log "Failed to install NuGet: $_" "ERROR"
            Write-Log "SCRIPT: $ThisFileName | END | Install of NuGet failed. Now exiting script." "ERROR"
            Exit 1
        }

        # Install WinGet PowerShell Module
        Write-Log "Installing WinGet PowerShell Module..."
        Try {
            Install-Module -Name Microsoft.WinGet.Client -Repository PSGallery -Force -AllowClobber -Scope AllUsers -ErrorAction Stop
            Write-Log "WinGet PowerShell Module installed successfully"
        } Catch {
            Write-Log "Failed to install WinGet PowerShell Module: $_" "ERROR"
            Write-Log "SCRIPT: $ThisFileName | END | Install of WinGet module failed. Now exiting script." "ERROR"
            Exit 1
        }
    } else {
        Write-Log "WinGetPSmodule is already installed"
    }
    
    # Import the module
    Write-Log "Importing WinGet PowerShell Module..."
    Try {
        Import-Module Microsoft.WinGet.Client -Force -ErrorAction Stop
        Write-Log "WinGet PowerShell Module imported successfully"
    } Catch {
        Write-Log "Failed to import WinGet PowerShell Module: $_" "ERROR"
        Write-Log "SCRIPT: $ThisFileName | END | Import of WinGet module failed. Now exiting script." "ERROR"
        Exit 1
    }
    
    # Try to repair WinGet, but don't fail if it doesn't work (common in SYSTEM context)
    Try {
        # Check if the Repair cmdlet exists and if we're not running as SYSTEM
        if (Get-Command Repair-WinGetPackageManager -ErrorAction SilentlyContinue) {
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            if ($currentUser.Name -ne 'NT AUTHORITY\SYSTEM') {
                Write-Log "Attempting to repair WinGetPackageManager..."
                Repair-WinGetPackageManager -AllUsers -Force -ErrorAction Stop
                Write-Log "WinGetPackageManager repair completed"
            } else {
                Write-Log "Running as SYSTEM, skipping WinGet repair (not needed for PowerShell module)"
            }
        } else {
            Write-Log "Repair-WinGetPackageManager not available, continuing without repair"
        }
    } Catch {
        # Don't fail on repair errors - the module often works without it
        Write-Log "Note: Could not repair WinGetPackageManager (non-critical): $_" "WARNING"
        Write-Log "Continuing with installation - PowerShell module should still work"
    }
    
    # Verify the module is working
    Try {
        $testCommand = Get-Command Install-WinGetPackage -ErrorAction Stop
        Write-Log "WinGet PowerShell Module verified and ready to use"
    } Catch {
        Write-Log "Failed to verify WinGet PowerShell Module: $_" "ERROR"
        Write-Log "SCRIPT: $ThisFileName | END | WinGet module verification failed. Now exiting script." "ERROR"
        Exit 1
    }
}

function CheckAndInstall-Git {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Log "Git not found. Installing via WinGet PowerShell module..." "WARNING"
        
        try {
            Write-Log "Checking if WinGet PowerShell module is installed..."
            CheckAndInstallandRepair-WinGetPSmodule
            
            Write-Log "Installing Git using WinGet PowerShell module..."
            
            # Try to install Git using the PowerShell module
            Try {

                # First, try to find the package to make sure it's available
                $gitPackage = Find-WinGetPackage -Id Git.Git -Exact -Source winget -ErrorAction Stop

                if ($gitPackage) {
                    Write-Log "Git package found, proceeding with installation..."
                    
                    # Install Git
                    $installResult = Install-WinGetPackage -Id Git.Git -Mode Silent -Source winget -Force -ErrorAction Stop
                    
                    if ($installResult) {
                        Write-Log "Git installation completed"
                    }
                    
                } else {
                    Write-Log "Git package not found in WinGet repository" "ERROR"
                    Exit 1
                }


            } Catch {
                Write-Log "Failed to install Git via PowerShell module: $_" "ERROR"
                
                <#
                # Fallback: try using winget.exe if available
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    Write-Log "Attempting fallback installation using winget.exe..."
                    $wingetResult = winget install --id Git.Git -e --source winget --silent --accept-package-agreements --accept-source-agreements 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "Git installed successfully via winget.exe fallback"
                    } else {
                        Write-Log "Fallback installation also failed" "ERROR"
                        Exit 1
                    }
                } else {
                    Write-Log "No fallback method available" "ERROR"
                    Exit 1
                }
                #>

            }
            
            # Refresh environment variables
            Write-Log "Refreshing environment variables..."
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            
            # Verify Git installation
            Start-Sleep -Seconds 5  # Give the system a moment to register the installation
            

            
            # Final verification
            if (Get-Command git -ErrorAction SilentlyContinue) {
                Write-Log "Git installed and verified successfully!" "SUCCESS"
            } else {
                Write-Log "Git installation completed but git.exe not found in PATH. Attempting to search for Git and add to PATH manually." "WARNING"
                
                # Try common Git installation paths if not in PATH yet
                Write-Log "Attempting to find Git and add to PATH"
                $gitPaths = @(
                    "C:\Program Files\Git\cmd",
                    "C:\Program Files (x86)\Git\cmd",
                    "${env:ProgramFiles}\Git\cmd",
                    "${env:ProgramFiles(x86)}\Git\cmd"
                )

                $FoundGit = $False
                foreach ($gitPath in $gitPaths) {

                    if (Test-Path "$gitPath\git.exe") {
                        Write-Log "Found Git at: $gitPath"
                        $env:Path += ";$gitPath"

                        # Refresh environment variables
                        Write-Log "Refreshing environment variables..."
                        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
                        
                        # Verify Git installation
                        Start-Sleep -Seconds 5  # Give the system a moment to register the installation
        
                        $FoundGit = $True
                        break

                    } 

                }

                if (Get-Command git -ErrorAction SilentlyContinue){
                    Write-Log "Git installed and verified successfully!" "SUCCESS"
                    $FoundGit = $True
                }

                if ($FoundGit -eq $False){

                    Write-Log "Git installation returned success but git.exe not found in PATH or common locations. It may be available after a reboot." "ERROR"
                    Exit 1
                }

                if ($FoundGit -eq $True) {
                    # Try to add to system PATH permanently
                    try {
                        $currentPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
                        if ($currentPath -notlike "*$gitPath*") {
                            [Environment]::SetEnvironmentVariable("Path", "$currentPath;$gitPath", "Machine")
                            Write-Log "Added Git to system PATH permanently"
                        }
                    } catch {
                        Write-Log "Could not add Git to system PATH permanently (may need admin rights): $_" "WARNING"
                    }
                }

            }
            
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
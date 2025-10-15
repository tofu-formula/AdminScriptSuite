
<#

.SYNOPSIS
    Pull the latest commit from your target repo, and run a powershell script within, even passing parameters to that powershell script.

.DESCRIPTION
    This template...
        - can be used to pull the latest commit from your target repo, and run a powershell script within, even passing parameters to that powershell script.
        - was intended to be used as the primary component in this project: https://github.com/tofu-formula/AdminScriptSuite and interacts with the scripts within
        - can be ran as-is, or set up to be ran independently by removing the parameters.
        - will not be updated much so safe to keep and run. If used as a part of the github repo above, it can update itself.

.PARAMETER RepoNickName
    Name to call the repo, for logging/local file path ($LocalRepoPath = "$WorkingDirectory\Git_Repos\$RepoNickName")
    EXAMPLE
        Win-AdminScriptSuite

.PARAMETER RepoUrl
    Link to the target repo
    EXAMPLE
        https://github.com/tofu-formula/AdminScriptSuite.git

.PARAMETER ScriptPath
    Path within the repo to your target script
    EXAMPLE
        Uninstallers\General_Uninstaller.ps1

.PARAMETER WorkingDirectory
    Path to directory on the host machine that will be used to hold the repo and logs
    NOTE: Recommended path "C:\ProgramData\YourCompanyName\Logs\"  - Useful because user does not have visibility to this unless they enable it
    NOTE: The directory will be created if it does not already exist
    NOTE: A seperate WorkingDirectory path will need to be provided in the params passed to the target script
    EXAMPLE
        C:\ProgramData\COMPANY_NAME

.PARAMETER ScriptParams
    Params to pass to the target script
    NOTE: You will need to check the target script's description to see what params are needed
    NOTE: Enclose in single brackets
    EXAMPLE 
        for General_Uninstaller.ps1: 
            '-AppName "7-zip" -UninstallType "All" -WorkingDirectory "C:\ProgramData\COMPANY_NAME\Logs"'


.EXAMPLE
    .\Git_Runner_TEMPLATE.ps1 -RepoNickName "Win-AdminScriptSuite" -RepoURL "https://github.com/tofu-formula/AdminScriptSuite.git" -ScriptPath "Uninstallers\General_Uninstaller.ps1" -WorkingDirectory "C:\ProgramData\COMPANY_NAME" -ScriptParams '-AppName "7-zip" -UninstallType "All" -WorkingDirectory "C:\ProgramData\COMPANY_NAME\Logs"'
    
    Template: .\Git_Runner_TEMPLATE.ps1 -RepoNickName "" -RepoURL "" -ScriptPath "" -WorkingDirectory "" -ScriptParams ""


.NOTES
    TODO:
        - Maybe add a timeout feature for the script?

    SOURCE:
        https://github.com/tofu-formula/AdminScriptSuite

#>


param(
    [Parameter(Mandatory=$true)]
    [string]$RepoNickName, # Name to call the repo, for logging/local file path

    [Parameter(Mandatory=$true)]
    [string]$RepoUrl,
    
    [Parameter(Mandatory=$true)]
    [string]$ScriptPath,
    
    [Parameter(Mandatory=$true)]
    [string]$WorkingDirectory, # Recommended param: "C:\ProgramData\YourCompanyName\Logs\"
    
    [Parameter(ValueFromRemainingArguments=$true)]
    $ScriptParams # Params to pass to the target script. Example for General_Uninstaller.ps1: -ScriptParams '-AppName "7-zip" -UninstallType "All" -WorkingDirectory "C:\ProgramData\COMPANY_NAME\Logs"'

)

##########
## Vars ##
##########

$LocalRepoPath = "$WorkingDirectory\Git_Repos\$RepoNickName"
$LogRoot = "$WorkingDirectory\Git_Logs"
$LogPath = "$LogRoot\$RepoNickName._Git_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"


# Uncomment this part if you don't want to use params
# $RepoNickName = zz
# $RepoUrl = zz
# $ScriptPath = zz
# $WorkingDirectory = zz
# $ScriptParams = zz

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

Function CheckAndInstall-WinGet {

    if (!(Get-Command winget -ErrorAction SilentlyContinue)) {

        Write-Log "WinGet not found, beginning installation..."
        # Install and run the winget installer script
        # NOTE: This requires PowerShellGet module
        Try{

            Install-Script -Name winget-install -Force -Scope CurrentUser
            winget-install
            Write-Log "WinGet installed successfully."

        } Catch {

            Write-Log "SCRIPT: GitHub_Runner | END | Install of WinGet failed. Please investigate. Now exiting script." "ERROR"
            Exit 1
        }
        
    } else {
        Write-Log "Winget is already installed"
    }

}

function CheckAndInstall-Git {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Log "Git not found. Installing via winget..." "WARNING"
        
        try {

            Write-Log "Checking if WinGet is installed"
            CheckAndInstall-WinGet

            winget install --id Git.Git -e --source winget --silent --accept-package-agreements --accept-source-agreements
            
            # Refresh environment variables
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            
            Write-Log "Git installed successfully!" "SUCCESS"
        }
        catch {
            Write-Log "SCRIPT: GitHub_Runner | END | ERROR: Failed to install Git: $_" "ERROR"
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

Write-Log "+++++ Git Runner +++++"

Write-Log "RepoNickName: $RepoNickName"
Write-Log "RepoUrl: $RepoUrl"
Write-Log "ScriptPath: $ScriptPath"
Write-Log "WorkingDirectory: $WorkingDirectory"
Write-Log "ScriptParams: $ScriptParams"
Write-Log "++++++++++++++++++++++"

# Check if git is installed
Write-Log "Checking first if Git is installed..."
CheckAndInstall-Git

Write-Log "Now checking if local repo exists..."
# Clone or update repository
if (Test-Path $LocalRepoPath) {

    Write-Log "Repository exists. Pulling latest changes..."
    Push-Location $LocalRepoPath
    try {
        $gitOutput = git pull 2>&1
        foreach ($line in $gitOutput) {
            Write-Log "GIT: $line"
        }
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "SCRIPT: GitHub_Runner | END | Failed to pull latest changes" "ERROR"
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
        Write-Log "SCRIPT: GitHub_Runner | END | Failed to clone repository" "ERROR"
        exit 1
    } else {
        Write-Log "Successfully cloned repository" "SUCCESS"
    }
}



# Build full script path
$FullScriptPath = Join-Path $LocalRepoPath $ScriptPath

# Check if script exists
if (-not (Test-Path $FullScriptPath)) {
    Write-Log "SCRIPT: GitHub_Runner | END | Script not found: $FullScriptPath" "ERROR"
    Exit 1
}

# Run the script with parameters
Write-Log "Running script: $ScriptPath"
Write-Log "With parameters: $ScriptParams"

try {
    if ($ScriptParams) {
        $command = "& `"$FullScriptPath`" $ScriptParams"
        Invoke-Expression $command
    }
    else {
        & $FullScriptPath
    }
}
catch {
    Write-Log "SCRIPT: GitHub_Runner | END | Failed to execute script: $_" "ERROR"
    Exit 1
}


Write-Log "++++++++++++++++++++++"
Write-Log "SCRIPT: GitHub_Runner | END | Repo: $RepoNickName | Script: $ScriptPath | Execution completed." "SUCCESS"
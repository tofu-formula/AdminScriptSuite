
<#
TODO

- Maybe add a timeout feature for the script?


#>



# This template can be ran as-is, or set up to be ran independently by removing the parameters.
param(
    [Parameter(Mandatory=$true)]
    [string]$RepoNickName, # Name to call the repo, for logging

    [Parameter(Mandatory=$true)]
    [string]$RepoUrl,
    
    [Parameter(Mandatory=$true)]
    [string]$ScriptPath,
    
    [Parameter(Mandatory=$false)]
    [string]$WorkingDirectory = "C:\temp", # Recommended param: "C:\ProgramData\YourCompanyName\Logs\"
    
    [Parameter(ValueFromRemainingArguments=$true)]
    $ScriptParams
)

##########
## Vars ##
##########

$LocalRepoPath = "$WorkingDirectory\$RepoNickName"
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

            Write-Log "Install of WinGet failed. Please investigate. Now exiting script." "ERROR"
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
            Write-Log "ERROR: Failed to install Git: $_" "ERROR"
            exit 1
        }
    }
    else {
        Write-Host "Git is already installed."
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

# Check if git is installed
Write-Log "Checking first if Git is installed..."
CheckAndInstall-Git

# Clone or update repository
if (Test-Path $LocalRepoPath) {

    Write-Log "Repository exists. Pulling latest changes..."
    Push-Location $LocalRepoPath
    try {
        git pull
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Failed to pull latest changes" "ERROR"
            exit 1
        }
    }
    finally {
        Pop-Location
    }
}
else {
    Write-Log "Cloning repository..."
    git clone $RepoUrl $LocalRepoPath
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Failed to clone repository" "ERROR"
    }
}

# Build full script path
$FullScriptPath = Join-Path $LocalRepoPath $ScriptPath

# Check if script exists
if (-not (Test-Path $FullScriptPath)) {
    Write-Log "Script not found: $FullScriptPath" "ERROR"
}

# Run the script with parameters
Write-Log "Running script: $ScriptPath"
Write-Log "With parameters: $ScriptParams"

try {
    if ($ScriptParams) {
        & $FullScriptPath @ScriptParams
    }
    else {
        & $FullScriptPath
    }
}
catch {
    Write-Log "Failed to execute script: $_" "ERROR"
}

Write-Log "SCRIPT: GitHub_Runner | End | Repo: $RepoNickName | Script: $ScriptPath | Execution completed." "SUCCESS"
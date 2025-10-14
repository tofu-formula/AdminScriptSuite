# This template can be ran as is or set up to be ran independently by removing the parameters.

param(
    [Parameter(Mandatory=$true)]
    [string]$RepoNickName, # Name to call the repo, for logging

    [Parameter(Mandatory=$true)]
    [string]$RepoUrl,
    
    [Parameter(Mandatory=$true)]
    [string]$ScriptPath,
    
    [Parameter(Mandatory=$false)]
    [string]$WorkingDirectory, # Recommended param: "C:\ProgramData\YourCompanyName\Logs\"
    
    [Parameter(ValueFromRemainingArguments=$true)]
    $ScriptParams
)

##########
## Vars ##
##########

$LocalRepoPath = "$WorkingDirectory\GitHubRepoZZ"
$LogRoot = "$WorkingDirectory\GitHub_Logs"
$LogPath = "$LogRoot\$RepoNickName._GitHub_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"


# Uncomment this part if you don't want to use params
# $RepoUrl = zz
# $ScriptPath = zz
# $LocalRepoPath = zz
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

##########
## Main ##
##########

# Check if git is installed
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Log "Git is not installed or not in PATH" "ERROR"
    exit 1
}

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
# Git Runner Tester
# Clone the repo to test
# Run winget installer for 7-zip


##########
## Vars ##
##########


#$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$RepoRoot = Split-Path -Path $PSScriptRoot -Parent
#$WorkingDirector = (Resolve-Path "$PSScriptRoot\..\..").Path
$WorkingDirectory = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

$LogRoot = "$WorkingDirectory\Logs\Git_Logs"

# path of WinGet installer
$WinGetInstallerScript = "$RepoRoot\Installers\General_WinGet_Installer.ps1"
# path of General uninstaller
$UninstallerScript = "$RepoRoot\Uninstallers\General_Uninstaller.ps1"
# path of the DotNet installer
$DotNetInstallerScript = "$RepoRoot\Installers\Install-DotNET.ps1"
# path to Git Runner
$GitRunnerScript = "$RepoRoot\Templates\Git_Runner_TEMPLATE.ps1"


$AppToTest
$FunctionToTest

$LogPath = "$LogRoot\TEST._$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

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

Function TESTER-UninstallAll-7Zip {


    # Write-Log "========================================"
    # Write-Log "SCRIPT: $ThisFileName | 1. Attempt clean uninstall of pre-existing installations of DCU"
    # Write-Log "========================================"

    Write-Log "========================================="

    Write-Log "FUNCTION: $($MyInvocation.MyCommand.Name) | Begin"

    $AppName = "7zip.7zip"
    $UninstallType = "All"

    Try{ 

        Write-Log "SCRIPT: $ThisFileName | Attempting to uninstall $AppName"

        #Powershell.exe -executionpolicy remotesigned -File $UninstallerScript -AppName "Dell.CommandUpdate" -UninstallType "All" -WorkingDirectory $WorkingDirectory
        
        & $UninstallerScript -AppName "$AppName" -UninstallType "$UninstallType" -WorkingDirectory $WorkingDirectory
        if ($LASTEXITCODE -ne 0) { throw "$LASTEXITCODE" }

    } Catch {

        Write-Log "SCRIPT: $ThisFileName | END | $AppName Uninstall failed. Code: $_" "ERROR"
        Exit 1

    }


}


Function TESTER-InstallWinGet-7Zip {

    Write-Log "========================================="

    Write-Log "FUNCTION: $($MyInvocation.MyCommand.Name) | Begin"

    $AppName = "7-Zip"
    $AppID = "7zip.7zip"

    Try {

        Write-Log "SCRIPT: $ThisFileName | Attempting to install $AppName"


        #Powershell.exe -executionpolicy remotesigned -File $WinGetInstallerScript -AppName "DellCommandUpdate" -AppID "Dell.CommandUpdate" -WorkingDirectory $WorkingDirectory
        & $WinGetInstallerScript -AppName "$AppName" -AppID "$AppID" -WorkingDirectory $WorkingDirectory
        if ($LASTEXITCODE -ne 0) { throw "$LASTEXITCODE" }

    } Catch {

        Write-Log "SCRIPT: $ThisFileName | END | Failed to install $AppName. Code: $_" "ERROR"
        Exit 1

    }


}

# Still testing this one
# Function TESTER-GitRunner-InstallWinGet-7Zip{

#     Write-Log "========================================="

#     Write-Log "FUNCTION: $($MyInvocation.MyCommand.Name) | Begin"

#     $AppName = "7-Zip"
#     $AppID = "7zip.7zip"    

#     Try {

#         Write-Log "SCRIPT: $ThisFileName | "

#         #Powershell.exe -executionpolicy remotesigned -File $WinGetInstallerScript -AppName "DellCommandUpdate" -AppID "Dell.CommandUpdate" -WorkingDirectory $WorkingDirectory
#         #& $GitRunnerScript -AppName "$AppName" -AppID "$AppID" -WorkingDirectory $WorkingDirectory


#         #Powershell.exe -executionpolicy bypass -Command "& '%SCRIPT_DIR%Templates\Git_Runner_TEMPLATE.ps1' -RepoNickName '%LOCAL_REPO_FOLDER_NAME%' -RepoUrl 'https://github.com/tofu-formula/AdminScriptSuite' -UpdateLocalRepoOnly $true -WorkingDirectory '%WORKINGDIR%'"

#         & $GitRunnerScript  -RepoNickName 'TEST' -RepoUrl 'https://github.com/tofu-formula/AdminScriptSuite' -UpdateLocalRepoOnly $False -WorkingDirectory $WorkingDirectory -ScriptParams "-AppName $AppName -AppID $AppID -WorkingDirectory $WorkingDirectory"
#         if ($LASTEXITCODE -ne 0) { throw "$LASTEXITCODE" }

#     } Catch {

#         Write-Log "SCRIPT: $ThisFileName | END | Failed to finish $($MyInvocation.MyCommand.Name) | Code: $_" "ERROR"
#         Exit 1

#     }

# }


##########
## Main ##
##########

## Pre-Check
$ThisFileName = $MyInvocation.MyCommand.Name
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX PRE-CHECK for SCRIPT: $ThisFileName"
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX NOTE: PRE-CHECK is not logged"
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX Checking if supplied paths have valid syntax"

# Test the paths syntax
$pathsToValidate = @{
    'WorkingDirectory' = $WorkingDirectory
    'RepoRoot' = $RepoRoot
    'LogRoot' = $LogRoot
    'LogPath' = $LogPath
    'WinGetInstallerScript' = $WinGetInstallerScript
    'UninstallerScript' = $UninstallerScript
    'GitRunnerScript'= $GitRunnerScript
}
Test-PathSyntaxValidity -Paths $pathsToValidate -ExitOnError

# Test the paths existance
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX Checking if supplied paths exist"
$pathsToTest = @{
    'WorkingDirectory' = $WorkingDirectory
    'WinGetInstallerScript' = $WinGetInstallerScript
    'UninstallerScript' = $UninstallerScript
    'GitRunnerScript' = $GitRunnerScript
}
Foreach ($pathToTest in $pathsToTest.keys){ 

    $TargetPath = $pathsToTest[$pathToTest]

    if((test-path $TargetPath) -eq $false){
        Write-Log "Required path $pathToTest does not exist at $TargetPath" "ERROR"
        Exit 1
    }

}
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX Path validation successful - all exist"

Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"



Write-Log "===== General Tester ====="

$methods = Get-Command -CommandType Function -Name "TESTER-*" | Select-Object -ExpandProperty Name


$AvailableTests = @{}

Write-Log "Available tests:" "INFO"
$COUNTER = 1
$methods | ForEach-Object { 
    
    Write-Log "$Counter - $_" "INFO"
    $AvailableTests.add($Counter,$_)
    $Counter++ 

}

Write-Log "========================================="

#$AvailableTests

Write-Log "Enter the # of your desired test:"
[int]$SelectedTestNumber = Read-Host "Please enter a #"

$SelectedTest = $AvailableTests[$SelectedTestNumber]

#$SelectedTest 

Write-Log "You have selected: $SelectedTest"

& $SelectedTest

Write-Log "SCRIPT: $ThisFileName | END | Test $SelectedTest complete" "SUCCESS"
Exit 0
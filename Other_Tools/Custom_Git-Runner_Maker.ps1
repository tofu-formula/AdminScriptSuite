# Custom Git Runner maker

# Run Generate_Install-Command.ps1 to call this script

param(
    [string]$RepoNickName,
    [string]$RepoUrl,
    [string]$WorkingDirectory,
    [string]$ScriptPath,
    #[hashtable]$ScriptParams,
    [string]$ScriptParamsBase64
)

# $RepoNickName = 'TEST'
# $RepoUrl = 'TEST'
# $WorkingDirectory = 'TEST'
# $ScriptPath = 'TEST'
# $ScriptParams

# Fix the params
$RepoNickName = "'" +    $RepoNickName + "'"
$RepoUrl = "'" +    $RepoUrl + "'"
$WorkingDirectory = "'" +    $WorkingDirectory + "'"
$ScriptPath = "'" +    $ScriptPath + "'"
$ScriptParamsBase64 = "'" +    $ScriptParamsBase64 + "'"

    # $RepoNickName
    # $RepoUrl
    # $WorkingDirectory
    # $ScriptPath
    # $ScriptParams

$ThisFileName = $MyInvocation.MyCommand.Name
$RepoRoot = Split-Path -Path $PSScriptRoot -Parent
$ThisWorkingDirectory = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

$LogRoot = "$ThisWorkingDirectory\Logs\Other_Logs"
$LogPath = "$LogRoot\$ThisFileName._Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

$GitRunnerScript = "$RepoRoot\Templates\Git_Runner_TEMPLATE.ps1"

$TargetScript = $GitRunnerScript   # original script

$DestinationPath = "$ThisWorkingDirectory\TEMP\Custom_Git_Runners"
# $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($TargetScript)
$Ext      = [System.IO.Path]::GetExtension($TargetScript)

$EndScript ="Git-Runner_Custom.$(Get-Date -Format 'yyyyMMdd_HHmmss')$Ext"

# ---

    $RepoNickName_DEC = '$RepoNickName = '+$RepoNickName
    $RepoUrl_DEC = '$RepoUrl = '+$RepoUrl
    $WorkingDirectory_DEC = '$WorkingDirectory = '+$WorkingDirectory
    $ScriptPath_DEC = '$ScriptPath = '+$ScriptPath
    $ScriptParamsBase64_DEC = '$ScriptParamsBase64 = '+$ScriptParamsBase64


# --- config ---
$KeyPhrase    = "#####" # the marker/keyphrase
$NewCode      = @"
# --- injected code start ---

    $RepoNickName_DEC
    $RepoUrl_DEC
    $WorkingDirectory_DEC
    $ScriptPath_DEC
    $ScriptParamsBase64_DEC

# --- injected code end ---
"@

TRY{


    # --- 1. Make a copy of the target script ---

    $CopyPath = Join-Path $DestinationPath $EndScript

    if(!(Test-Path -Path $DestinationPath)){
        New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
    }

    Copy-Item -Path $TargetScript -Destination $CopyPath -Force

    # --- 2. Load the copied script as a single string ---
    $content = Get-Content -Path $CopyPath -Raw

    # Find the keyphrase position
    $index = $content.IndexOf($KeyPhrase)
    if ($index -lt 0) {
        throw "Key phrase '$KeyPhrase' not found in script '$CopyPath'."
    }

    # Erase everything *before* the keyphrase, keep from keyphrase onward
    $restOfScript = $content.Substring($index)

    # Build new content: injected code + newline + original from keyphrase down
    $updatedContent = $NewCode + "`r`n" + $restOfScript

    # Overwrite the copied script (original remains untouched)
    $updatedContent | Set-Content -Path $CopyPath -Encoding UTF8

    Write-Host "Custom Git-Runner script written to: $CopyPath"

}CATCH{

    $ErrorMessage = $_.Exception.Message
    $FailedItem   = $_.Exception.ItemName
    Write-Host "Error: $ErrorMessage"
    Write-Host "Failed Item: $FailedItem"

}
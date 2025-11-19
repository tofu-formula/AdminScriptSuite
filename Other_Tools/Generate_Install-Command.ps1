# Helper script to generate Intune commands and create custom Git Runners. 
# This is the main script you will use to build your new infrastructure based on this suite.


<#

Instructions:

Build your command

Open elevated cmd on the test machine

navigate to the dir of git runner template (on mac you may need to do pushd)



#>

########
# Vars #
########

# These are for identifying the running environment of this script not for the end script
$RepoRoot = Split-Path -Path $PSScriptRoot -Parent
$WorkingDirectory = Split-Path -Path $RepoRoot -Parent
$GitRunnerScript = "$RepoRoot\Templates\Git_Runner_TEMPLATE.ps1"
$CustomGitRunnerMakerScript = "$RepoRoot\Other_Tools\Custom_Git-Runner_Maker.ps1"

# $RepoRoot = "C:\ProgramData\AdminScriptSuite\AdminScriptSuite-Repo"
# $WorkingDirectory = Split-Path -Path $RepoRoot -Parent

$InstallCommandTXT = "$WorkingDirectory\TEMP\Intune-Install-Commands\$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

#############
# Functions #
#############

function New-IntuneGitRunnerCommand {
    param(
        [string]$RepoNickName,
        [string]$RepoUrl,
        [string]$WorkingDirectory,
        [string]$ScriptPath,
        [hashtable]$ScriptParams
    )
    
    if ($ScriptParams) {
        # Encode the parameters
        $paramsJson = $ScriptParams | ConvertTo-Json -Compress
        $paramsBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($paramsJson))
        
        # Build the command
        $command = @"
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '.\Git_Runner_TEMPLATE.ps1' -RepoNickName '$RepoNickName' -RepoUrl '$RepoUrl' -WorkingDirectory '$WorkingDirectory' -ScriptPath '$ScriptPath' -ScriptParamsBase64 '$paramsBase64'"
"@
    } else {
        # for a no param script
        $command = @"
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '.\Git_Runner_TEMPLATE.ps1' -RepoNickName '$RepoNickName' -RepoUrl '$RepoUrl' -WorkingDirectory '$WorkingDirectory' -ScriptPath '$ScriptPath'"
"@
    }

    # Create the custom script with the current params
    & $CustomGitRunnerMakerScript -RepoNickName $RepoNickName -RepoUrl $RepoUrl -WorkingDirectory $WorkingDirectory -ScriptPath $ScriptPath -ScriptParamsBase64 $paramsBase64

    # done
    return $command
}

########
# MAIN #
########

# See the examples below. You can uncomment one to generate the command you want.

#################################
### Example: Update repo only ###
#################################

<#
$updateCommand = New-IntuneGitRunnerCommand `
    -RepoNickName "Test00" `
    -RepoUrl "https://github.com/tofu-formula/AdminScriptSuite.git" `
    -WorkingDirectory "C:\ProgramData\Test7"

Write-Host "Update Only Command:" -ForegroundColor Green
Write-Host $updateCommand
Write-Host ""
#>



##################################################
### Example: Run a Remediation script - DETECT ###
##################################################

# Set the registry changes. first
 
    # Set which function you want to do
    $Function = "Remediate"

    # Declare as list to bypass the Git Runner's function of putting passed string params into double quotes. This breaks the pass to the remediation script.
    $RegistryChanges = @()

    # Registry Value 1
    $KeyPath = "HKEY_LOCAL_MACHINE\SOFTWARE\AdminScriptSuite-Test"
    $KeyName = "Test"
    $KeyType = "String"
    $Value = "$(Get-Date -Format 'yyyyMMdd_HHmmss')"

    $RegistryChangesSTRING = "["+"-KeyPath ""$KeyPath"" -KeyName ""$KeyName"" -KeyType ""$KeyType"" -Value ""$Value"""+"]"+","


    # Registry Value 2
    $KeyPath = "HKEY_LOCAL_MACHINE\SOFTWARE\AdminScriptSuite-Test"
    $KeyName = "Test 2"
    $KeyType = "String"
    $Value = "$(Get-Date -Format 'yyyyMMdd_HHmmss') 2"

    $RegistryChangesSTRING += "["+"-KeyPath ""$KeyPath"" -KeyName ""$KeyName"" -KeyType ""$KeyType"" -Value ""$Value"""+"]" # no comma at the end cuz this is the end of the list

    # Make as many as you need

    # Create a passable object
    $RegistryChangesSTRING = ''''+$RegistryChangesSTRING+''''
    $RegistryChanges+=$RegistryChangesSTRING

  
    # This works too!
    # $RegistryChanges = @()
    # $RegistryChanges += '''[-KeyPath "HKEY_LOCAL_MACHINE\SOFTWARE\AdminScriptSuite-Test" -KeyName "Test" -KeyType "String" -Value "zz"],[-KeyPath "HKEY_LOCAL_MACHINE\SOFTWARE\AdminScriptSuite-Test" -KeyName "Test 2" -KeyType "String" -Value "zz 2"]'''


# Then compose the install command args
$installCommand = New-IntuneGitRunnerCommand `
    -RepoNickName "AdminScriptSuite-Repo" `
    -RepoUrl "https://github.com/tofu-formula/AdminScriptSuite.git" `
    -WorkingDirectory "C:\ProgramData\AdminScriptSuite" `
    -ScriptPath "Templates\General_RemediationScript-Registry_TEMPLATE.ps1" `
    -ScriptParams @{
        RegistryChanges = $RegistryChanges
        RepoNickName = "AdminScriptSuite-Repo"
        WorkingDirectory = "C:\ProgramData\AdminScriptSuite"
        Function = $Function
    }

<#

Output for detect:
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '.\Git_Runner_TEMPLATE.ps1' -RepoNickName 'AdminScriptSuite-Repo' -RepoUrl 'https://github.com/tofu-formula/AdminScriptSuite.git' -WorkingDirectory 'C:\ProgramData\AdminScriptSuite' -ScriptPath 'Templates\General_RemediationScript-Registry_TEMPLATE.ps1' -ScriptParamsBase64 'eyJSZWdpc3RyeUNoYW5nZXMiOlsiXHUwMDI3Wy1LZXlQYXRoIFwiSEtFWV9MT0NBTF9NQUNISU5FXFxTT0ZUV0FSRVxcQWRtaW5TY3JpcHRTdWl0ZS1UZXN0XCIgLUtleU5hbWUgXCJUZXN0XCIgLUtleVR5cGUgXCJTdHJpbmdcIiAtVmFsdWUgXCIyMDI1MTExOF8xNTE3MzJcIl0sWy1LZXlQYXRoIFwiSEtFWV9MT0NBTF9NQUNISU5FXFxTT0ZUV0FSRVxcQWRtaW5TY3JpcHRTdWl0ZS1UZXN0XCIgLUtleU5hbWUgXCJUZXN0IDJcIiAtS2V5VHlwZSBcIlN0cmluZ1wiIC1WYWx1ZSBcIjIwMjUxMTE4XzE1MTczMiAyXCJdXHUwMDI3Il0sIkZ1bmN0aW9uIjoiRGV0ZWN0IiwiUmVwb05pY2tOYW1lIjoiQWRtaW5TY3JpcHRTdWl0ZS1SZXBvIiwiV29ya2luZ0RpcmVjdG9yeSI6IkM6XFxQcm9ncmFtRGF0YVxcQWRtaW5TY3JpcHRTdWl0ZSJ9'"

Output for remediate
#>

###


####################################################################
### Example: Install Dell Command Update (custom install script) ###
####################################################################

<#
$installCommand = New-IntuneGitRunnerCommand `
    -RepoNickName "AdminScriptSuite-Repo" `
    -RepoUrl "https://github.com/tofu-formula/AdminScriptSuite.git" `
    -WorkingDirectory "C:\ProgramData\AdminScriptSuite" `
    -ScriptPath "Installers\Install-DellCommandUpdate-FullClean.ps1"
#>


#################################################################
### Example: Install Zoom Workplace (standard WinGet install) ###
#################################################################

<#
$installCommand = New-IntuneGitRunnerCommand `
    -RepoNickName "AdminScriptSuite-Repo" `
    -RepoUrl "https://github.com/tofu-formula/AdminScriptSuite.git" `
    -WorkingDirectory "C:\ProgramData\AdminScriptSuite" `
    -ScriptPath "Installers\General_WinGet_Installer.ps1" `
    -ScriptParams @{
        AppName = "Zoom.Zoom.EXE"
        AppID = "Zoom.Zoom.EXE"
        WorkingDirectory = "C:\ProgramData\AdminScriptSuite"
    }
#>



# Output the command to a txt file and to clipboard

If (!(Test-Path $InstallCommandTXT)){New-item -path $InstallCommandTXT -ItemType File -Force | out-null}

$installCommand | Set-Content -Encoding utf8 $InstallCommandTXT
Write-Host "Install command saved here: $InstallCommandTXT"

$installCommand | Set-Clipboard 
Write-Host "Install command saved to your clip board!"


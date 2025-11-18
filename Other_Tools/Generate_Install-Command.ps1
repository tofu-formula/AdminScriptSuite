# Helper script to generate Intune commands

# Vars

# These are for identifying the running environment of this script not for the end script
$RepoRoot = Split-Path -Path $PSScriptRoot -Parent
$WorkingDirectory = Split-Path -Path $RepoRoot -Parent

# $RepoRoot = "C:\ProgramData\AdminScriptSuite\AdminScriptSuite-Repo"
# $WorkingDirectory = Split-Path -Path $RepoRoot -Parent

$InstallCommandTXT = "$WorkingDirectory\TEMP\Intune-Install-Commands\$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

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
    
    return $command
}



# Example: Update repo only
<#
$updateCommand = New-IntuneGitRunnerCommand `
    -RepoNickName "Test00" `
    -RepoUrl "https://github.com/tofu-formula/AdminScriptSuite.git" `
    -WorkingDirectory "C:\ProgramData\Test7"

Write-Host "Update Only Command:" -ForegroundColor Green
Write-Host $updateCommand
Write-Host ""
#>



### Example: Run a Remediation script - DETECT
# Set the registry changes. first
    $RegistryChanges = "-KeyPath ""$KeyPath"" -KeyName ""$KeyName"" -KeyType ""$KeyType"" -Value ""$Value"""

    $KeyPath = "HKEY_LOCAL_MACHINE\SOFTWARE\AdminScriptSuite-Test"
    $KeyName = "Test"
    $KeyType = "String"
    $Value = "$(Get-Date -Format 'yyyyMMdd_HHmmss')"

    $RegistryChanges = "'"+"-KeyPath ""$KeyPath"" -KeyName ""$KeyName"" -KeyType ""$KeyType"" -Value ""$Value"""+"'"+","

    $KeyPath = "HKEY_LOCAL_MACHINE\SOFTWARE\AdminScriptSuite-Test"
    $KeyName = "Test 2"
    $KeyType = "String"
    $Value = "$(Get-Date -Format 'yyyyMMdd_HHmmss') 2"

    $RegistryChanges+="'"+"-KeyPath ""$KeyPath"" -KeyName ""$KeyName"" -KeyType ""$KeyType"" -Value ""$Value"""+"'"

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
        Function = "Detect"
    }

###


# Example: Install Dell Command Update (custom install script)
<#
$installCommand = New-IntuneGitRunnerCommand `
    -RepoNickName "AdminScriptSuite-Repo" `
    -RepoUrl "https://github.com/tofu-formula/AdminScriptSuite.git" `
    -WorkingDirectory "C:\ProgramData\AdminScriptSuite" `
    -ScriptPath "Installers\Install-DellCommandUpdate-FullClean.ps1"
#>


# Example: Install Zoom Workplace (standard WinGet install)
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

If (!(Test-Path $InstallCommandTXT)){New-item -path $InstallCommandTXT -ItemType File -Force | out-null}

$installCommand | Set-Content -Encoding utf8 $InstallCommandTXT
Write-Host "Install command saved here: $InstallCommandTXT"

$installCommand | Set-Clipboard 
Write-Host "Install command saved to your clip board!"





# Intune run example

# %SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '.\Git_Runner_TEMPLATE.ps1' -RepoNickName 'Test00' -RepoUrl 'https://github.com/tofu-formula/AdminScriptSuite.git' -WorkingDirectory 'C:\ProgramData\Test00' -ScriptPath 'Installers\General_WinGet_Installer.ps1' -ScriptParamsBase64 'eyJBcHBJRCI6Ijd6aXAuN3ppcCIsIkFwcE5hbWUiOiI3LXppcCIsIldvcmtpbmdEaXJlY3RvcnkiOiJDOlxcUHJvZ3JhbURhdGFcXFRlc3QwMCJ9'"
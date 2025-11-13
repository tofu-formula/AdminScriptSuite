# Helper script to generate Intune commands
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
        # Update only command
        $command = @"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0Git_Runner_TEMPLATE.ps1' -RepoNickName '$RepoNickName' -RepoUrl '$RepoUrl' -UpdateLocalRepoOnly `$true -WorkingDirectory '$WorkingDirectory'"
"@
    }
    
    return $command
}

# Example 1: Update repo only
# $updateCommand = New-IntuneGitRunnerCommand `
#     -RepoNickName "Test00" `
#     -RepoUrl "https://github.com/tofu-formula/AdminScriptSuite.git" `
#     -WorkingDirectory "C:\ProgramData\Test7"

# Write-Host "Update Only Command:" -ForegroundColor Green
# Write-Host $updateCommand
# Write-Host ""

# Example 2: Install 7-zip
$installCommand = New-IntuneGitRunnerCommand `
    -RepoNickName "AdminScriptSuite-Repo" `
    -RepoUrl "https://github.com/tofu-formula/AdminScriptSuite.git" `
    -WorkingDirectory "C:\ProgramData\AdminScriptSuite" `
    -ScriptPath "Installers\General_WinGet_Installer.ps1" `
    -ScriptParams @{
        AppName = "Adobe_CC"
        AppID = "Adobe.CreativeCloud"
        WorkingDirectory = "C:\ProgramData\AdminScriptSuite"
    }

Write-Host "Install Command:" -ForegroundColor Green
Write-Host $installCommand

# Intune run example

# %SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '.\Git_Runner_TEMPLATE.ps1' -RepoNickName 'Test00' -RepoUrl 'https://github.com/tofu-formula/AdminScriptSuite.git' -WorkingDirectory 'C:\ProgramData\Test00' -ScriptPath 'Installers\General_WinGet_Installer.ps1' -ScriptParamsBase64 'eyJBcHBJRCI6Ijd6aXAuN3ppcCIsIkFwcE5hbWUiOiI3LXppcCIsIldvcmtpbmdEaXJlY3RvcnkiOiJDOlxcUHJvZ3JhbURhdGFcXFRlc3QwMCJ9'"
<#

.SYNOPSIS
    Helper script to generate Intune commands and create custom Git Runners.

.DESCRIPTION
    This is the main script you will use to build your new infrastructure based on this suite.
    This script is called from the Setup.ps1 script. For most scenarios you will not use this script outside of that context.
    Currently the main exception is if you need to build Remedation scripts, but I will be adding that functionality to Setup.ps1 in the future.


.NOTES

    Some old notes:

        Instructions:

        Build your command

        Open elevated cmd on the test machine

        navigate to the dir of git runner template (on mac VM you may need to do pushd)

#>



Param(

    [string]$DesiredFunction,
    [hashtable]$FunctionParams

)

########
# Vars #
########

# These are for identifying the running environment of this script not for the end script
$RepoRoot = Split-Path -Path $PSScriptRoot -Parent
$WorkingDirectory = Split-Path -Path $RepoRoot -Parent
$GitRunnerScript = "$RepoRoot\Templates\Git-Runner_TEMPLATE.ps1"
$CustomGitRunnerMakerScript = "$RepoRoot\Other_Tools\Generate_Custom-Script_FromTemplate.ps1"

$ThisFileName = $MyInvocation.MyCommand.Name

# $RepoRoot = "C:\ProgramData\AdminScriptSuite\AdminScriptSuite-Repo"
# $WorkingDirectory = Split-Path -Path $RepoRoot -Parent


#############
# Functions #
#############

function New-IntuneGitRunnerCommand {
    param(
        [string]$RepoNickName,
        [string]$RepoUrl,
        [string]$WorkingDirectory,
        [string]$ScriptPath,
        [hashtable]$ScriptParams,
        [string]$CustomNameModifier
    )
    
    if ($ScriptParams) {

        Write-Host "Script parameters to encode:" #-ForegroundColor Cyan
        $ScriptParams | Format-List | Out-Host

        # Encode the parameters
        $paramsJson = $ScriptParams | ConvertTo-Json -Compress
        $paramsBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($paramsJson))
        
        # Build the command
        $command = @"
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '.\Git-Runner_TEMPLATE.ps1' -RepoNickName '$RepoNickName' -RepoUrl '$RepoUrl' -WorkingDirectory '$WorkingDirectory' -ScriptPath '$ScriptPath' -ScriptParamsBase64 '$paramsBase64'"
"@
    } else {
        # for a no param script
        $command = @"
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '.\Git-Runner_TEMPLATE.ps1' -RepoNickName '$RepoNickName' -RepoUrl '$RepoUrl' -WorkingDirectory '$WorkingDirectory' -ScriptPath '$ScriptPath'"
"@
    }

    # Create the custom script with the current params
    if($CustomNameModifier){
        $global:CustomScript = & $CustomGitRunnerMakerScript -RepoNickName $RepoNickName -RepoUrl $RepoUrl -WorkingDirectory $WorkingDirectory -ScriptPath $ScriptPath -ScriptParamsBase64 $paramsBase64 -CustomNameModifier $CustomNameModifier
    }
    else {
        $global:CustomScript = & $CustomGitRunnerMakerScript -RepoNickName $RepoNickName -RepoUrl $RepoUrl -WorkingDirectory $WorkingDirectory -ScriptPath $ScriptPath -ScriptParamsBase64 $paramsBase64
    }   

    # done
    Write-Host ""
    return $command
}


function ExportTXT {

    if($CustomNameModifier){

        $InstallCommandTXT = "$WorkingDirectory\TEMP\Intune_Install-Commands_Output\$CustomNameModifier.Install-Command_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    } else {

        $InstallCommandTXT = "$WorkingDirectory\TEMP\Intune_Install-Commands_Output\Install-Command_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
   
    }

    If (!(Test-Path $InstallCommandTXT)){New-item -path $InstallCommandTXT -ItemType File -Force | out-null}

    # Output the command to a txt file and to clipboard

    Write-Host "Final install command:"
    Write-Host $installCommand #-ForegroundColor Green
    Write-Host ""


    $installCommand | Set-Content -Encoding utf8 $InstallCommandTXT
    Write-Host "Install command saved here: $InstallCommandTXT"
    Write-Host ""

    $installCommand | Set-Clipboard 
    Write-Host "Install command saved to your clip board!"

    Write-Host ""

    return $InstallCommandTXT
}



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



############################################################
### Example: Create Detect/Remediation Script for InTune ###
############################################################
Function RemediationScript {

    Write-Host "SCRIPT: $ThisFileName | FUNCTION: $($MyInvocation.MyCommand.Name) | START" -ForegroundColor Yellow

    Write-Host "Generating Detect/Remediation scripts for Registry changes..." -ForegroundColor Yellow
    # Choose the registry changes.

        # Declare as list to bypass the Git Runner's function of putting passed string params into double quotes. This breaks the pass to the remediation script.
        $RegistryChanges = @()

        <#
        # Registry Value 1
        $KeyPath = "HKEY_LOCAL_MACHINE\SOFTWARE\AdminScriptSuite-Test"
        $ValueName = "Test"
        $ValueType = "String"
        #$Value = "$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        $Value = "1"

        $RegistryChangesSTRING = "["+"-KeyPath ""$KeyPath"" -ValueName ""$ValueName"" -ValueType ""$ValueType"" -Value ""$Value"""+"]"+","


        # Registry Value 2
        $KeyPath = "HKEY_LOCAL_MACHINE\SOFTWARE\AdminScriptSuite-Test"
        $ValueName = "Test 2"
        $ValueType = "String"
        #$Value = "$(Get-Date -Format 'yyyyMMdd_HHmmss') 2"
        $Value = "2"

        $RegistryChangesSTRING += "["+"-KeyPath ""$KeyPath"" -ValueName ""$ValueName"" -ValueType ""$ValueType"" -Value ""$Value"""+"]" # no comma at the end cuz this is the end of the list
        #>


        # Registry Value 1
        $KeyPath = "HKEY_LOCAL_MACHINE\SOFTWARE\AdminScriptSuite\General"
        $ValueName = "StorageAccountName"
        $ValueType = "String"
        #$Value = "$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        $Value = "genericdeploy" # Modify this

        $RegistryChangesSTRING = "["+"-KeyPath ""$KeyPath"" -ValueName ""$ValueName"" -ValueType ""$ValueType"" -Value ""$Value"""+"]"+","

        # Registry Value 2
        $KeyPath = "HKEY_LOCAL_MACHINE\SOFTWARE\AdminScriptSuite\Printers"
        $ValueName = "PrinterDataJSONpath"
        $ValueType = "String"
        #$Value = "$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        $Value = "printers/PrinterData.json" # Modify this

        $RegistryChangesSTRING += "["+"-KeyPath ""$KeyPath"" -ValueName ""$ValueName"" -ValueType ""$ValueType"" -Value ""$Value"""+"]"+","

        # Registry Value 3
        $KeyPath = "HKEY_LOCAL_MACHINE\SOFTWARE\AdminScriptSuite\Printers"
        $ValueName = "PrinterContainerSASkey"
        $ValueType = "String"
        #$Value = "$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        $Value = "" # Modify this

        $RegistryChangesSTRING += "["+"-KeyPath ""$KeyPath"" -ValueName ""$ValueName"" -ValueType ""$ValueType"" -Value ""$Value"""+"]"+","

        # Registry Value 4
        $KeyPath = "HKEY_LOCAL_MACHINE\SOFTWARE\AdminScriptSuite\Applications"
        $ValueName = "ApplicationDataJSONpath"
        $ValueType = "String"
        #$Value = "$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        $Value = "applications/ApplicationData.json" # Modify this

        $RegistryChangesSTRING += "["+"-KeyPath ""$KeyPath"" -ValueName ""$ValueName"" -ValueType ""$ValueType"" -Value ""$Value"""+"]"+","

        # Registry Value 5
        $KeyPath = "HKEY_LOCAL_MACHINE\SOFTWARE\AdminScriptSuite\Applications"
        $ValueName = "ApplicationContainerSASkey"
        $ValueType = "String"
        #$Value = "$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        $Value = "" # Modify this

        $RegistryChangesSTRING += "["+"-KeyPath ""$KeyPath"" -ValueName ""$ValueName"" -ValueType ""$ValueType"" -Value ""$Value"""+"]"


        # Make as many as you need

        # Create a passable object
        $RegistryChangesSTRING = ''''+$RegistryChangesSTRING+''''
        $RegistryChanges+=$RegistryChangesSTRING

    
        # This works too!
        # $RegistryChanges = @()
        # $RegistryChanges += '''[-KeyPath "HKEY_LOCAL_MACHINE\SOFTWARE\AdminScriptSuite-Test" -ValueName "Test" -ValueType "String" -Value "zz"],[-KeyPath "HKEY_LOCAL_MACHINE\SOFTWARE\AdminScriptSuite-Test" -ValueName "Test 2" -ValueType "String" -Value "zz 2"]'''

        Write-Host "Registry Changes to process: $RegistryChanges" #-ForegroundColor Yellow

    # Then compose the install command args and run for DETECT
    Write-Host ""
    Write-Host "DETECT SCRIPT" -ForegroundColor Yellow
    $CustomNameModifier = "Detect"
    $installCommand = New-IntuneGitRunnerCommand `
        -RepoNickName "AdminScriptSuite-Repo" `
        -RepoUrl "https://github.com/tofu-formula/AdminScriptSuite.git" `
        -WorkingDirectory "C:\ProgramData\AdminScriptSuite" `
        -ScriptPath "Templates\General_RemediationScript-Registry_TEMPLATE.ps1" `
        -CustomNameModifier "$CustomNameModifier" `
        -ScriptParams @{
            RegistryChanges = $RegistryChanges
            RepoNickName = "AdminScriptSuite-Repo"
            WorkingDirectory = "C:\ProgramData\AdminScriptSuite"
            Function = "Detect"
        }

    # Export the txt file
    ExportTXT

    # Then compose the install command args and run for REMEDIATE
    Write-Host ""
    Write-Host "REMEDIATION SCRIPT" -ForegroundColor Yellow
    $CustomNameModifier = "Remediate"
    $installCommand = New-IntuneGitRunnerCommand `
        -RepoNickName "AdminScriptSuite-Repo" `
        -RepoUrl "https://github.com/tofu-formula/AdminScriptSuite.git" `
        -WorkingDirectory "C:\ProgramData\AdminScriptSuite" `
        -ScriptPath "Templates\General_RemediationScript-Registry_TEMPLATE.ps1" `
        -CustomNameModifier "$CustomNameModifier" `
        -ScriptParams @{
            RegistryChanges = $RegistryChanges
            RepoNickName = "AdminScriptSuite-Repo"
            WorkingDirectory = "C:\ProgramData\AdminScriptSuite"
            Function = "Remediate"
        }

    # Export the txt file
    ExportTXT

    <#

    Output for detect:
    %SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '.\Git-Runner_TEMPLATE.ps1' -RepoNickName 'AdminScriptSuite-Repo' -RepoUrl 'https://github.com/tofu-formula/AdminScriptSuite.git' -WorkingDirectory 'C:\ProgramData\AdminScriptSuite' -ScriptPath 'Templates\General_RemediationScript-Registry_TEMPLATE.ps1' -ScriptParamsBase64 'eyJSZWdpc3RyeUNoYW5nZXMiOlsiXHUwMDI3Wy1LZXlQYXRoIFwiSEtFWV9MT0NBTF9NQUNISU5FXFxTT0ZUV0FSRVxcQWRtaW5TY3JpcHRTdWl0ZS1UZXN0XCIgLUtleU5hbWUgXCJUZXN0XCIgLUtleVR5cGUgXCJTdHJpbmdcIiAtVmFsdWUgXCIyMDI1MTExOF8xNTE3MzJcIl0sWy1LZXlQYXRoIFwiSEtFWV9MT0NBTF9NQUNISU5FXFxTT0ZUV0FSRVxcQWRtaW5TY3JpcHRTdWl0ZS1UZXN0XCIgLUtleU5hbWUgXCJUZXN0IDJcIiAtS2V5VHlwZSBcIlN0cmluZ1wiIC1WYWx1ZSBcIjIwMjUxMTE4XzE1MTczMiAyXCJdXHUwMDI3Il0sIkZ1bmN0aW9uIjoiRGV0ZWN0IiwiUmVwb05pY2tOYW1lIjoiQWRtaW5TY3JpcHRTdWl0ZS1SZXBvIiwiV29ya2luZ0RpcmVjdG9yeSI6IkM6XFxQcm9ncmFtRGF0YVxcQWRtaW5TY3JpcHRTdWl0ZSJ9'"

    Output for remediate
    #>
}
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


##############################################################
### Example: Install Printer by IP (custom install script) ###
##############################################################
function InstallPrinterByIP {

    Param(

        [hashtable]$FunctionParams, # NOTE: This works for my intended use case but this with the param received snippet below are NOT done according to intent...
        [String]$PrinterName="zz" # I don't remember why I had to do this...

    )
    Write-Host "SCRIPT: $ThisFileName | FUNCTION: $($MyInvocation.MyCommand.Name) | START" -ForegroundColor Yellow

    Write-Host "Generating Install script for Printer by IP..." -ForegroundColor Yellow

    Write-Host "Function parameters received:"
    # Check the returned hashtable
    if(($FunctionParams -eq $null) -or ($FunctionParams.Count -eq 0)){
        Write-Host "No data returned! Checking if a printer was explicitly specified..." #"ERROR"
        if(-not $PrinterName){
            Write-Host "No printer specified. Exiting!" #"ERROR"
            Exit 1

        } else {
            Write-Host "Printer specified as: $PrinterName"
        }
    } else {

        Write-Host "Values retrieved:"
        foreach ($key in $FunctionParams.Keys) {
            $value = $FunctionParams[$key]
            Write-Host "   $key : $value"
        }    

        # Turn the returned hashtable into variables
        Write-Host "Setting values as local variables..."
        foreach ($key in $FunctionParams.Keys) {
            Set-Variable -Name $key -Value $FunctionParams[$key] -Scope Local
            # Write-Log "Should be: $key = $($ReturnHash[$key])"
            $targetValue = Get-Variable -Name $key -Scope Local
            Write-Host "Ended up as: $key = $($targetValue.Value)"

        }

    }


    If ($PrinterName -eq "zz"){
        Write-Host "PrinterName is still the default 'zz'. Please specify a valid PrinterName. Exiting!" #"ERROR"
        Exit 1
    }


    #$PrinterName = "Auckland"

    # Main install command:
    Write-Host ""
    Write-Host "INSTALL COMMAND" -ForegroundColor Yellow
    $CustomNameModifier = "Install-Printer-IP.$PrinterName"
    $installCommand = New-IntuneGitRunnerCommand `
        -RepoNickName "AdminScriptSuite-Repo" `
        -RepoUrl "https://github.com/tofu-formula/AdminScriptSuite.git" `
        -WorkingDirectory "C:\ProgramData\AdminScriptSuite" `
        -ScriptPath "Installers\General_IP-Printer_Installer.ps1" `
        -CustomNameModifier "$CustomNameModifier" `
        -ScriptParams @{
            PrinterName = "$PrinterName"
            WorkingDirectory = "C:\ProgramData\AdminScriptSuite"
        }

    $InstallPrinterScript = $global:CustomScript
    # Export the txt file
    $InstallCommandTXT = ExportTXT

    # Detection script command:
    Write-Host ""
    Write-Host "DETECT SCRIPT" -ForegroundColor Yellow
    $CustomNameModifier = "Detect-Printer.$PrinterName"
    $detectCommand = New-IntuneGitRunnerCommand `
        -RepoNickName "AdminScriptSuite-Repo" `
        -RepoUrl "https://github.com/tofu-formula/AdminScriptSuite.git" `
        -WorkingDirectory "C:\ProgramData\AdminScriptSuite" `
        -ScriptPath "Templates\Detection-Script-Printer_TEMPLATE.ps1" `
        -CustomNameModifier "$CustomNameModifier" `
        -ScriptParams @{
            PrinterName = "$PrinterName"
            WorkingDirectory = "C:\ProgramData\AdminScriptSuite"
        }

    $DetectPrinterScript = $global:CustomScript

    # Export the txt file
    $DetectCommandTXT = ExportTXT

    <#
    $ReturnHash = @{
        MainInstallCommand = $installCommand
        MainInstallCommandTXT = $InstallCommandTXT
        MainDetectCommand = $detectCommand
        MainDetectCommandTXT = $DetectCommandTXT
        InstallPrinterScript = $InstallPrinterScript
        DetectPrinterScript = $DetectPrinterScript
    }

    Write-host "Return values prepared."
    $ReturnHash.Keys | ForEach-Object { Write-Host "   $_ : $($ReturnHash[$_])" }   
    Return $ReturnHash

    #>

    # Store results in script-scoped variables so the main script can package them up
    $script:GI_MainInstallCommand    = $installCommand
    $script:GI_MainInstallCommandTXT = $InstallCommandTXT
    $script:GI_MainDetectCommand     = $detectCommand
    $script:GI_MainDetectCommandTXT  = $DetectCommandTXT
    $script:GI_InstallPrinterScript      = $InstallPrinterScript
    $script:GI_DetectPrinterScript       = $DetectPrinterScript

    # Just for visibility, still log what we *think* we produced
    Write-Host "Return values prepared."
    Write-Host "   MainInstallCommand     : $script:GI_MainInstallCommand"
    Write-Host "   MainInstallCommandTXT  : $script:GI_MainInstallCommandTXT"
    Write-Host "   MainDetectCommand      : $script:GI_MainDetectCommand"
    Write-Host "   MainDetectCommandTXT   : $script:GI_MainDetectCommandTXT"
    Write-Host "   InstallPrinterScript       : $script:GI_InstallPrinterScript"
    Write-Host "   DetectPrinterScript        : $script:GI_DetectPrinterScript"

    Write-Host "SCRIPT: $ThisFileName | FUNCTION: $($MyInvocation.MyCommand.Name) | END"
    Write-host ""

    $Script:HashPattern = "InstallPrinterByIP"

    return "BuildMe"


}


######################################
### Example: Install App with JSON ###
######################################
function InstallAppWithJSON {

    Param(

        [String]$ApplicationName="zz", # I don't remember why I had to do this...
        $DetectMethod,
        $DisplayName,
        $AppID
        # [Parameter(ValueFromRemainingArguments=$true)] # NOTE: Can't get this working the way I want, just gonna hardcode below.
        # $FunctionParams


    )
    Write-Host "SCRIPT: $ThisFileName | FUNCTION: $($MyInvocation.MyCommand.Name) | START" -ForegroundColor Yellow
    Write-Host "Generating Install script for App with JSON..." -ForegroundColor Yellow
    Write-Host "Function parameters received:"
    # Check the returned hashtable
    #if(($FunctionParams -eq $null) -or ($FunctionParams.Count -eq 0)){
    # if(($FunctionParams -eq $null)){
    #     Write-Host "No data returned! Checking if an app was explicitly specified..." #"ERROR"
    #     if(-not $ApplicationName){
    #         Write-Host "No app specified. Exiting!" #"ERROR"
    #         Exit 1

    #     } else {
            
    #         Write-Host "App specified as: $ApplicationName"

    #     }
    # } else {

    #     Write-Host "Values retrieved:"
    #     foreach ($key in $FunctionParams.Keys) {
    #         $value = $FunctionParams[$key]
    #         Write-Host "   $key : $value"
    #     }    

    #     # Turn the returned hashtable into variables
    #     Write-Host "Setting values as local variables..."
    #     foreach ($key in $FunctionParams.Keys) {
    #         Set-Variable -Name $key -Value $FunctionParams[$key] -Scope Local
    #         # Write-Log "Should be: $key = $($ReturnHash[$key])"
    #         $targetValue = Get-Variable -Name $key -Scope Local
    #         Write-Host "Ended up as: $key = $($targetValue.Value)"

    #     }

    # }
    
    Write-Host "App specified as: $ApplicationName"
    Write-Host "DetectMethod specified as: $DetectMethod"
    Write-Host "DisplayName specified as: $DisplayName"
    Write-Host "AppID specified as: $AppID"


    If ($ApplicationName -eq "zz"){
        Write-Host "AppName is still the default 'zz'. Please specify a valid AppName. Exiting!" #"ERROR"
        Exit 1
    }


    # Main install command:
    Write-Host ""
    Write-Host "INSTALL COMMAND" -ForegroundColor Yellow
    $CustomNameModifier = "Install-JSON-App.$ApplicationName"
    $installCommand = New-IntuneGitRunnerCommand `
        -RepoNickName "AdminScriptSuite-Repo" `
        -RepoUrl "https://github.com/tofu-formula/AdminScriptSuite.git" `
        -WorkingDirectory "C:\ProgramData\AdminScriptSuite" `
        -ScriptPath "Installers\General_JSON-App_Installer.ps1" `
        -CustomNameModifier "$CustomNameModifier" `
        -ScriptParams @{
            TargetAppName = "$ApplicationName"
            WorkingDirectory = "C:\ProgramData\AdminScriptSuite"
        }


        
    $InstallAppScript = $global:CustomScript
    # Export the txt file
    $InstallCommandTXT = ExportTXT

    # Detection script command:
    Write-Host ""
    Write-Host "DETECT SCRIPT" -ForegroundColor Yellow

    If ($DetectMethod -eq "WinGet"){

        Write-Host "Using WinGet detection method."

        if (-not $AppID){
            Write-Error "AppID must be specified for WinGet detection method."
            Exit 1
        }

        $CustomNameModifier = "Detect-App.Winget.$ApplicationName"
        $detectCommand = New-IntuneGitRunnerCommand `
            -RepoNickName "AdminScriptSuite-Repo" `
            -RepoUrl "https://github.com/tofu-formula/AdminScriptSuite.git" `
            -WorkingDirectory "C:\ProgramData\AdminScriptSuite" `
            -ScriptPath "Templates\Detection-Script-Application_TEMPLATE.ps1" `
            -CustomNameModifier "$CustomNameModifier" `
            -ScriptParams @{
                WorkingDirectory = "C:\ProgramData\AdminScriptSuite"
                AppToDetect = $ApplicationName
                AppID = $AppID
                DetectMethod = $DetectMethod
            }

    } elseif ( $DetectMethod -eq "MSI_Registry" ) {

        Write-Host "Using MSI Registry detection method."

 
        $CustomNameModifier = "Detect-App.MSIRegistry.$ApplicationName"
        $detectCommand = New-IntuneGitRunnerCommand `
            -RepoNickName "AdminScriptSuite-Repo" `
            -RepoUrl "https://github.com/tofu-formula/AdminScriptSuite.git" `
            -WorkingDirectory "C:\ProgramData\AdminScriptSuite" `
            -ScriptPath "Templates\Detection-Script-Application_TEMPLATE.ps1" `
            -CustomNameModifier "$CustomNameModifier" `
            -ScriptParams @{
                WorkingDirectory = "C:\ProgramData\AdminScriptSuite"
                DisplayName = $DisplayName
                AppToDetect = $ApplicationName
                DetectMethod = $DetectMethod

            }


    } {

        Write-Error "Unsupported DetectMethod specified: $DetectMethod"
        Exit 1

    }


    $DetectAppScript = $global:CustomScript

    # Export the txt file
    $DetectCommandTXT = ExportTXT


    <# # For some reason this doesn't work here even though it works for the printer function...
    $ReturnHash = @{
        MainInstallCommand = $installCommand
        MainInstallCommandTXT = $InstallCommandTXT
        MainDetectCommand = $detectCommand
        MainDetectCommandTXT = $DetectCommandTXT
        InstallAppScript = $InstallAppScript
        DetectAppScript = $DetectAppScript
    }

    Write-host "Return values prepared."
    $ReturnHash.Keys | ForEach-Object { Write-Host "   $_ : $($ReturnHash[$_])" }   
    Return $ReturnHash

    #>

    # ...So instead we are doing this:

    # Store results in script-scoped variables so the main script can package them up
    $script:GI_MainInstallCommand    = $installCommand
    $script:GI_MainInstallCommandTXT = $InstallCommandTXT
    $script:GI_MainDetectCommand     = $detectCommand
    $script:GI_MainDetectCommandTXT  = $DetectCommandTXT
    $script:GI_InstallAppScript      = $InstallAppScript
    $script:GI_DetectAppScript       = $DetectAppScript

    # Just for visibility, still log what we *think* we produced
    Write-Host "Return values prepared."
    Write-Host "   MainInstallCommand     : $script:GI_MainInstallCommand"
    Write-Host "   MainInstallCommandTXT  : $script:GI_MainInstallCommandTXT"
    Write-Host "   MainDetectCommand      : $script:GI_MainDetectCommand"
    Write-Host "   MainDetectCommandTXT   : $script:GI_MainDetectCommandTXT"
    Write-Host "   InstallAppScript       : $script:GI_InstallAppScript"
    Write-Host "   DetectAppScript        : $script:GI_DetectAppScript"

    Write-Host "SCRIPT: $ThisFileName | FUNCTION: $($MyInvocation.MyCommand.Name) | END"
    Write-host ""

    $Script:HashPattern = "InstallAppWithJSON"

    return "BuildMe"

}



########
# MAIN #
########

# Choose what function to run here:
# TODO: Make this a selectable menu
#Write-Host "Generating Intune Install Commands from function: $DesiredFunction..."
#Write-Host ""

Write-Host "SCRIPT: $ThisFileName | DESIRED FUNCTION: $DesiredFunction | PARAMS: $FunctionParams | START"

# Write-Host "Function Parameters:"
# @FunctionParams

<#
$ReturnHash = & $DesiredFunction @FunctionParams


Write-host "Values to return to caller."
$ReturnHash.Keys | ForEach-Object { Write-Host "   $_ : $($ReturnHash[$_])" }   
Write-host ""
Write-Host "SCRIPT: $ThisFileNameName | DESIRED FUNCTION: $DesiredFunction | PARAMS: $FunctionParams | END"

Return $ReturnHash

#Write-Host "End of script."
# Return something

#>

# Invoke the selected function and capture its result
$result = & $DesiredFunction @FunctionParams

# Write-host ""
# Write-Host "Function '$DesiredFunction' returned: "  
# $result
Write-host ""

# If the function indicates that we need to build the final hashtable, do so
if ($result -eq "BuildMe") {

    if ($Script:HashPattern -eq "InstallAppWithJSON") {
        Write-Host "Building return hashtable for InstallAppWithJSON..."

        $result = @{
            MainInstallCommand     = $script:GI_MainInstallCommand
            MainInstallCommandTXT  = $script:GI_MainInstallCommandTXT
            MainDetectCommand      = $script:GI_MainDetectCommand
            MainDetectCommandTXT   = $script:GI_MainDetectCommandTXT
            InstallAppScript       = $script:GI_InstallAppScript
            DetectAppScript        = $script:GI_DetectAppScript
        }


    } elseif($Script:HashPattern -eq "InstallPrinterByIP") {

        Write-Host "Building return hashtable for InstallPrinterByIP..."

        $result = @{
            MainInstallCommand     = $script:GI_MainInstallCommand
            MainInstallCommandTXT  = $script:GI_MainInstallCommandTXT
            MainDetectCommand      = $script:GI_MainDetectCommand
            MainDetectCommandTXT   = $script:GI_MainDetectCommandTXT
            InstallPrinterScript   = $script:GI_InstallPrinterScript
            DetectPrinterScript    = $script:GI_DetectPrinterScript
        }



    }else {

        Write-Host "Unknown HashPattern: $($Script:HashPattern). Cannot build return hashtable!" -ForegroundColor Red
        Exit 1

    }

    #Write-Host "SCRIPT: $ThisFileName | | START" -ForegroundColor Yellow

    Write-host ""


    Write-Host "Values to return to caller."
    foreach ($key in $result.Keys) {
        Write-Host "   $key : $($result[$key])"
    }

    #Write-Host "SCRIPT: $ThisFileName | FUNCTION: $($MyInvocation.MyCommand.Name) | END | Returning hashtable above to caller."
    Write-Host "SCRIPT: $ThisFileName | DESIRED FUNCTION: $DesiredFunction | PARAMS: $FunctionParams | END"

    return $result

}

Write-Host ""
Write-Host "SCRIPT: $ThisFileName | DESIRED FUNCTION: $DesiredFunction | PARAMS: $FunctionParams | END"

return $result
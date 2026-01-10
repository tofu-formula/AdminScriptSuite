<#

.SYNOPSIS
    Helper script to generate Intune commands and create custom Git Runners.

.DESCRIPTION
    This is the main script you will use to build your new infrastructure based on this suite.
    This script is called from the Setup.ps1 script. For most scenarios you will not use this script outside of that context.
    Currently the main exception is if you need to build Remedation scripts, but I will be adding that functionality to Setup.ps1 in the future.


.NOTES

    This specific script doesn't do logging, previously out of a desire to keep SAS keys out of logs. Now that log folders are locked down, this is less of a concern.

    Some old notes:

        Instructions:

        Build your command

        Open elevated cmd on the test machine

        navigate to the dir of git runner template (on mac VM you may need to do pushd)

#>



Param(

    [string]$DesiredFunction,
    [hashtable]$FunctionParams,
    [String]$RepoURL

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

# $RepoRoot = "C:\ProgramData\PowerDeploy\PowerDeploy-Repo"
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
    -RepoUrl "$RepoURL" `
    -WorkingDirectory "C:\ProgramData\Test7"

Write-Host "Update Only Command:" -ForegroundColor Green
Write-Host $updateCommand
Write-Host ""
#>



############################################################
### Example: Create Detect/Remediation Script for InTune ###
############################################################
Function RegRemediationScript {

    Param(

    $StorageAccountName = "powerdeploy",

    $PrinterDataJSONpath = "printers/PrinterData.json",
    $PrinterContainerSASkey,

    $ApplicationDataJSONpath = "applications/ApplicationData.json",
    $ApplicationContainerSASkey

    $CustomRepoURL=$NULL,
    $CustomRepoToken=$NULL





    )

    Write-Host "SCRIPT: $ThisFileName | FUNCTION: $($MyInvocation.MyCommand.Name) | START" -ForegroundColor Yellow

    Write-Host "Generating Detect/Remediation scripts for Registry changes..." -ForegroundColor Yellow
    # Choose the registry changes.

        # Declare as list to bypass the Git Runner's function of putting passed string params into double quotes. This breaks the pass to the remediation script.
        $RegistryChanges = @()

        <#
        # Registry Value 1
        $KeyPath = "HKEY_LOCAL_MACHINE\SOFTWARE\PowerDeploy-Test"
        $ValueName = "Test"
        $ValueType = "String"
        #$Value = "$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        $Value = "1"

        $RegistryChangesSTRING = "["+"-KeyPath ""$KeyPath"" -ValueName ""$ValueName"" -ValueType ""$ValueType"" -Value ""$Value"""+"]"+","


        # Registry Value 2
        $KeyPath = "HKEY_LOCAL_MACHINE\SOFTWARE\PowerDeploy-Test"
        $ValueName = "Test 2"
        $ValueType = "String"
        #$Value = "$(Get-Date -Format 'yyyyMMdd_HHmmss') 2"
        $Value = "2"

        $RegistryChangesSTRING += "["+"-KeyPath ""$KeyPath"" -ValueName ""$ValueName"" -ValueType ""$ValueType"" -Value ""$Value"""+"]" # no comma at the end cuz this is the end of the list
        #>


        $KeyPath = "HKEY_LOCAL_MACHINE\SOFTWARE\PowerDeploy\General"
        $ValueName = "StorageAccountName"
        $ValueType = "String"
        #$Value = "$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        $Value = "$StorageAccountName" # Modify this
        $RegistryChangesSTRING = "["+"-KeyPath ""$KeyPath"" -ValueName ""$ValueName"" -ValueType ""$ValueType"" -Value ""$Value"""+"]"+","

        $KeyPath = "HKEY_LOCAL_MACHINE\SOFTWARE\PowerDeploy\General"
        $ValueName = "CustomRepoURL"
        $ValueType = "String"
        #$Value = "$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        $Value = "$CustomRepoURL" # Modify this
        $RegistryChangesSTRING = "["+"-KeyPath ""$KeyPath"" -ValueName ""$ValueName"" -ValueType ""$ValueType"" -Value ""$Value"""+"]"+","

        $KeyPath = "HKEY_LOCAL_MACHINE\SOFTWARE\PowerDeploy\General"
        $ValueName = "CustomRepoToken"
        $ValueType = "String"
        #$Value = "$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        $Value = "$CustomRepoToken" # Modify this
        $RegistryChangesSTRING = "["+"-KeyPath ""$KeyPath"" -ValueName ""$ValueName"" -ValueType ""$ValueType"" -Value ""$Value"""+"]"+","


        $KeyPath = "HKEY_LOCAL_MACHINE\SOFTWARE\PowerDeploy\Printers"
        $ValueName = "PrinterDataJSONpath"
        $ValueType = "String"
        #$Value = "$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        $Value = "$PrinterDataJSONpath" # Modify this
        $RegistryChangesSTRING += "["+"-KeyPath ""$KeyPath"" -ValueName ""$ValueName"" -ValueType ""$ValueType"" -Value ""$Value"""+"]"+","

        $KeyPath = "HKEY_LOCAL_MACHINE\SOFTWARE\PowerDeploy\Printers"
        $ValueName = "PrinterContainerSASkey"
        $ValueType = "String"
        #$Value = "$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        $Value = "$PrinterContainerSASkey" # Modify this
        $RegistryChangesSTRING += "["+"-KeyPath ""$KeyPath"" -ValueName ""$ValueName"" -ValueType ""$ValueType"" -Value ""$Value"""+"]"+","



        $KeyPath = "HKEY_LOCAL_MACHINE\SOFTWARE\PowerDeploy\Applications"
        $ValueName = "ApplicationDataJSONpath"
        $ValueType = "String"
        #$Value = "$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        $Value = "$ApplicationDataJSONpath" # Modify this
        $RegistryChangesSTRING += "["+"-KeyPath ""$KeyPath"" -ValueName ""$ValueName"" -ValueType ""$ValueType"" -Value ""$Value"""+"]"+","

        $KeyPath = "HKEY_LOCAL_MACHINE\SOFTWARE\PowerDeploy\Applications"
        $ValueName = "ApplicationContainerSASkey"
        $ValueType = "String"
        #$Value = "$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        $Value = "$ApplicationContainerSASkey" # Modify this
        $RegistryChangesSTRING += "["+"-KeyPath ""$KeyPath"" -ValueName ""$ValueName"" -ValueType ""$ValueType"" -Value ""$Value"""+"]"


        # Make as many as you need

        # Create a passable object
        $RegistryChangesSTRING = ''''+$RegistryChangesSTRING+''''
        $RegistryChanges+=$RegistryChangesSTRING

    
        # This works too!
        # $RegistryChanges = @()
        # $RegistryChanges += '''[-KeyPath "HKEY_LOCAL_MACHINE\SOFTWARE\PowerDeploy-Test" -ValueName "Test" -ValueType "String" -Value "zz"],[-KeyPath "HKEY_LOCAL_MACHINE\SOFTWARE\PowerDeploy-Test" -ValueName "Test 2" -ValueType "String" -Value "zz 2"]'''

        Write-Host "Registry Changes to process: $RegistryChanges" #-ForegroundColor Yellow

    # Then compose the install command args and run for DETECT
    Write-Host ""
    Write-Host "DETECT SCRIPT" -ForegroundColor Yellow
    $CustomNameModifier = "Detect"
    $installCommand = New-IntuneGitRunnerCommand `
        -RepoNickName "PowerDeploy-Repo" `
        -RepoUrl "$RepoUrl" `
        -WorkingDirectory "C:\ProgramData\PowerDeploy" `
        -ScriptPath "Templates\General_RemediationScript-Registry_TEMPLATE.ps1" `
        -CustomNameModifier "$CustomNameModifier" `
        -ScriptParams @{
            RegistryChanges = $RegistryChanges
            RepoNickName = "PowerDeploy-Repo"
            WorkingDirectory = "C:\ProgramData\PowerDeploy"
            Function = "Detect"
        }

    # # Export the txt file
    # ExportTXT

    $DetectScript = $global:CustomScript
    # Export the txt file
    $DetectScriptCommandTXT = ExportTXT

    # Then compose the install command args and run for REMEDIATE
    Write-Host ""
    Write-Host "REMEDIATION SCRIPT" -ForegroundColor Yellow
    $CustomNameModifier = "Remediate"
    $installCommand = New-IntuneGitRunnerCommand `
        -RepoNickName "PowerDeploy-Repo" `
        -RepoUrl "$RepoUrl" `
        -WorkingDirectory "C:\ProgramData\PowerDeploy" `
        -ScriptPath "Templates\General_RemediationScript-Registry_TEMPLATE.ps1" `
        -CustomNameModifier "$CustomNameModifier" `
        -ScriptParams @{
            RegistryChanges = $RegistryChanges
            RepoNickName = "PowerDeploy-Repo"
            WorkingDirectory = "C:\ProgramData\PowerDeploy"
            Function = "Remediate"
            AlsoLockDown = $True
        }

    # # Export the txt file
    # ExportTXT

    $RemediationScript = $global:CustomScript
    # Export the txt file
    $RemediationScriptCommandTXT = ExportTXT

    <#

    Output for detect:
    %SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '.\Git-Runner_TEMPLATE.ps1' -RepoNickName 'PowerDeploy-Repo' -RepoUrl '$RepoURL' -WorkingDirectory 'C:\ProgramData\PowerDeploy' -ScriptPath 'Templates\General_RemediationScript-Registry_TEMPLATE.ps1' -ScriptParamsBase64 'eyJSZWdpc3RyeUNoYW5nZXMiOlsiXHUwMDI3Wy1LZXlQYXRoIFwiSEtFWV9MT0NBTF9NQUNISU5FXFxTT0ZUV0FSRVxcQWRtaW5TY3JpcHRTdWl0ZS1UZXN0XCIgLUtleU5hbWUgXCJUZXN0XCIgLUtleVR5cGUgXCJTdHJpbmdcIiAtVmFsdWUgXCIyMDI1MTExOF8xNTE3MzJcIl0sWy1LZXlQYXRoIFwiSEtFWV9MT0NBTF9NQUNISU5FXFxTT0ZUV0FSRVxcQWRtaW5TY3JpcHRTdWl0ZS1UZXN0XCIgLUtleU5hbWUgXCJUZXN0IDJcIiAtS2V5VHlwZSBcIlN0cmluZ1wiIC1WYWx1ZSBcIjIwMjUxMTE4XzE1MTczMiAyXCJdXHUwMDI3Il0sIkZ1bmN0aW9uIjoiRGV0ZWN0IiwiUmVwb05pY2tOYW1lIjoiQWRtaW5TY3JpcHRTdWl0ZS1SZXBvIiwiV29ya2luZ0RpcmVjdG9yeSI6IkM6XFxQcm9ncmFtRGF0YVxcQWRtaW5TY3JpcHRTdWl0ZSJ9'"

    Output for remediate
    #>


     # Store results in script-scoped variables so the main script can package them up

    $script:GI_DetectScript = $DetectScript
    $script:GI_DetectScriptCommandTXT = $DetectScriptCommandTXT
    $script:GI_RemediationScript = $RemediationScript
    $script:GI_RemediationScriptCommandTXT = $RemediationScriptCommandTXT

    # Just for visibility, still log what we *think* we produced
    Write-Host "Return values prepared."


    Write-Host "script:GI_DetectScript = $script:GI_DetectScript"
    Write-Host "script:GI_DetectScriptCommandTXT = $script:GI_DetectScriptCommandTXT"
    Write-Host "script:GI_RemediationScript = $script:GI_RemediationScript"
    Write-Host "script:GI_RemediationScriptCommandTXT = $script:GI_RemediationScriptCommandTXT"



    Write-Host "SCRIPT: $ThisFileName | FUNCTION: $($MyInvocation.MyCommand.Name) | END"
    Write-host ""



    $Script:HashPattern = "RegRemediation"

    return "BuildMe"
}
###


####################################################################
### Example: Install Dell Command Update (custom install script) ###
####################################################################

<#
$installCommand = New-IntuneGitRunnerCommand `
    -RepoNickName "PowerDeploy-Repo" `
    -RepoUrl "$RepoURL" `
    -WorkingDirectory "C:\ProgramData\PowerDeploy" `
    -ScriptPath "Installers\Install-DellCommandUpdate-FullClean.ps1"
#>


#################################################################
### Example: Install Zoom Workplace (standard WinGet install) ###
#################################################################

<#
$installCommand = New-IntuneGitRunnerCommand `
    -RepoNickName "PowerDeploy-Repo" `
    -RepoUrl "$RepoURL" `
    -WorkingDirectory "C:\ProgramData\PowerDeploy" `
    -ScriptPath "Installers\General_WinGet_Installer.ps1" `
    -ScriptParams @{
        AppName = "Zoom.Zoom.EXE"
        AppID = "Zoom.Zoom.EXE"
        WorkingDirectory = "C:\ProgramData\PowerDeploy"
    }
#>


##############################################################
### Example: Install Printer by IP (custom install script) ###
##############################################################
function InstallPrinterByIP {

    Param(

        [hashtable]$FunctionParams, # NOTE: This works for my intended use case but this with the param received snippet below are NOT done according to intent...
        [String]$PrinterName="zz" # Didn't want to set to $false or $null for eval purposes. If printername is contained inside functionparams this gets overwritten. If I set default as $True, $False, or $Null it will be difficult to evaluate that no printername was passed either way, hence I made it "zz" as a dummy value.

    )
    Write-Host "SCRIPT: $ThisFileName | FUNCTION: $($MyInvocation.MyCommand.Name) | START" -ForegroundColor Yellow

    Write-Host "Generating Install script for Printer by IP..." -ForegroundColor Yellow

    Write-Host "Function parameters received:"
    # Check the returned hashtable
    # TODO: May want to replace this with the method from InstallAppWithJSON function that checks for specific keys instead of just any keys. This method here can produce errors.
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
        -RepoNickName "PowerDeploy-Repo" `
        -RepoUrl "$RepoURL" `
        -WorkingDirectory "C:\ProgramData\PowerDeploy" `
        -ScriptPath "Installers\General_IP-Printer_Installer.ps1" `
        -CustomNameModifier "$CustomNameModifier" `
        -ScriptParams @{
            PrinterName = "$PrinterName"
            WorkingDirectory = "C:\ProgramData\PowerDeploy"
        }

    $InstallPrinterScript = $global:CustomScript
    # Export the txt file
    $InstallCommandTXT = ExportTXT

    # Detection script command:
    Write-Host ""
    Write-Host "DETECT SCRIPT" -ForegroundColor Yellow
    $CustomNameModifier = "Detect-Printer.$PrinterName"
    $detectCommand = New-IntuneGitRunnerCommand `
        -RepoNickName "PowerDeploy-Repo" `
        -RepoUrl "$RepoURL" `
        -WorkingDirectory "C:\ProgramData\PowerDeploy" `
        -ScriptPath "Templates\Detection-Script-Printer_TEMPLATE.ps1" `
        -CustomNameModifier "$CustomNameModifier" `
        -ScriptParams @{
            PrinterName = "$PrinterName"
            WorkingDirectory = "C:\ProgramData\PowerDeploy"
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
    $script:GI_MainInstallCommand    = $installCommand # I don't remember why I named these "main"
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

##################################################################
### Example: Uninstall Printer by name (custom install script) ###
##################################################################
function UninstallPrinterByName {

    Param(

        [hashtable]$FunctionParams, # NOTE: This works for my intended use case but this with the param received snippet below are NOT done according to intent...
        [String]$PrinterName="zz" # Didn't want to set to $false or $null for eval purposes. If printername is contained inside functionparams this gets overwritten. If I set default as $True, $False, or $Null it will be difficult to evaluate that no printername was passed either way, hence I made it "zz" as a dummy value.

    )

    Write-Host "SCRIPT: $ThisFileName | FUNCTION: $($MyInvocation.MyCommand.Name) | START" -ForegroundColor Yellow

    Write-Host "Generating Uninstall script for Printer by name..." -ForegroundColor Yellow

    ###

    Write-Host "Function parameters received:"
    # Check the returned hashtable
    # TODO: May want to replace this with the method from InstallAppWithJSON function that checks for specific keys instead of just any keys. This method here can produce errors.

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

    ###

    If ($PrinterName -eq "zz"){
        Write-Host "PrinterName is still the default 'zz'. Please specify a valid PrinterName. Exiting!" #"ERROR"
        Exit 1
    }


    #$PrinterName = "Auckland"

    # Main install command:
    Write-Host ""
    Write-Host "UNINSTALL COMMAND" -ForegroundColor Yellow
    $CustomNameModifier = "Uninstall-Printer-Name.$PrinterName"
    $InstallCommand = New-IntuneGitRunnerCommand `
        -RepoNickName "PowerDeploy-Repo" `
        -RepoUrl "$RepoURL" `
        -WorkingDirectory "C:\ProgramData\PowerDeploy" `
        -ScriptPath "Uninstallers\Uninstall-Printer.ps1" `
        -CustomNameModifier "$CustomNameModifier" `
        -ScriptParams @{
            PrinterName = "$PrinterName"
            WorkingDirectory = "C:\ProgramData\PowerDeploy"
        }

    $UninstallPrinterScript = $global:CustomScript
    # Export the txt file
    $UninstallCommandTXT = ExportTXT

    $UninstallCommand = $InstallCommand
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
    # $script:GI_MainInstallCommand    = $installCommand
    # $script:GI_MainInstallCommandTXT = $InstallCommandTXT

    $script:GI_UninstallCommand    = $UninstallCommand
    $script:GI_UninstallCommandTXT  = $UninstallCommandTXT
    $script:GI_UninstallPrinterScript      = $UninstallPrinterScript

    # Just for visibility, still log what we *think* we produced
    Write-Host "Return values prepared."
    Write-Host "   UninstallCommand     : $script:GI_UninstallCommand"
    Write-Host "   UninstallCommandTXT  : $script:GI_UninstallCommandTXT"
    Write-Host "   UninstallPrinterScript  : $script:GI_UninstallPrinterScript"

    Write-Host "SCRIPT: $ThisFileName | FUNCTION: $($MyInvocation.MyCommand.Name) | END"
    Write-host ""

    $Script:HashPattern = "UninstallPrinterByName"

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
        -RepoNickName "PowerDeploy-Repo" `
        -RepoUrl "$RepoURL" `
        -WorkingDirectory "C:\ProgramData\PowerDeploy" `
        -ScriptPath "Installers\General_JSON-App_Installer.ps1" `
        -CustomNameModifier "$CustomNameModifier" `
        -ScriptParams @{
            TargetAppName = "$ApplicationName"
            WorkingDirectory = "C:\ProgramData\PowerDeploy"
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
            -RepoNickName "PowerDeploy-Repo" `
            -RepoUrl "$RepoURL" `
            -WorkingDirectory "C:\ProgramData\PowerDeploy" `
            -ScriptPath "Templates\Detection-Script-Application_TEMPLATE.ps1" `
            -CustomNameModifier "$CustomNameModifier" `
            -ScriptParams @{
                WorkingDirectory = "C:\ProgramData\PowerDeploy"
                AppToDetect = $ApplicationName
                AppID = $AppID
                DetectMethod = $DetectMethod
            }

    } elseif ( $DetectMethod -eq "MSI_Registry" ) {

        Write-Host "Using MSI Registry detection method."

 
        $CustomNameModifier = "Detect-App.MSIRegistry.$ApplicationName"
        $detectCommand = New-IntuneGitRunnerCommand `
            -RepoNickName "PowerDeploy-Repo" `
            -RepoUrl "$RepoURL" `
            -WorkingDirectory "C:\ProgramData\PowerDeploy" `
            -ScriptPath "Templates\Detection-Script-Application_TEMPLATE.ps1" `
            -CustomNameModifier "$CustomNameModifier" `
            -ScriptParams @{
                WorkingDirectory = "C:\ProgramData\PowerDeploy"
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

##############################
### Example: Uninstall App ###
##############################
function UninstallApp {

    Param(

        [hashtable]$FunctionParams # NOTE: This works for my intended use case but this with the param received snippet below are NOT done according to intent...

    )

    Write-Host "SCRIPT: $ThisFileName | FUNCTION: $($MyInvocation.MyCommand.Name) | START" -ForegroundColor Yellow

    Write-Host "Generating Uninstall script for an application..." -ForegroundColor Yellow

    ###

    Write-Host "Function parameters received:"

    # Check the returned hashtable
    # if(($FunctionParams -eq $null) -or ($FunctionParams.Count -eq 0)){

    #     Write-Host "No data returned! Checking if a app was explicitly specified..." #"ERROR"

    #     if(-not $AppName){

    #         Write-Host "No app specified. Exiting!" #"ERROR"
    #         Exit 1

    #     } else {
    #         Write-Host "App specified as: $AppName"
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

    ###

    Write-Host "App specified as: $ApplicationName"
    Write-Host "UninstallType specified as: $UninstallType"
    Write-Host "Version specified as: $Version"
    Write-Host "UninstallString_DisplayName specified as: $UninstallString_DisplayName"
    Write-Host "WinGetID specified as: $WinGetID"


    If ($ApplicationName -eq $null -or $ApplicationName -eq ""){
        Write-Host "ApplicationName was not passed within the function parameters or explicityly set. Please specify a valid ApplicationName. Exiting!" #"ERROR"
        Exit 1
    }


    #$PrinterName = "Auckland"

    if(!($Version)){$Version = $null}
    # winget ID
    if(!($WinGetID)){ $WinGetID = $null }
    # Uninstaller String Display Name
    if(!($UninstallString_DisplayName)){ $UninstallString_DisplayName = $null }

    # Main install command:
    Write-Host ""
    Write-Host "UNINSTALL COMMAND" -ForegroundColor Yellow
    $CustomNameModifier = "Uninstall-App.$ApplicationName"
    $InstallCommand = New-IntuneGitRunnerCommand `
        -RepoNickName "PowerDeploy-Repo" `
        -RepoUrl "$RepoURL" `
        -WorkingDirectory "C:\ProgramData\PowerDeploy" `
        -ScriptPath "Uninstallers\General_Uninstaller.ps1" `
        -CustomNameModifier "$CustomNameModifier" `
        -ScriptParams @{
            AppName = "$ApplicationName"
            UninstallType = "$UninstallType"
            Version = "$Version"
            WinGetID = "$WinGetID"
            UninstallString_DisplayName = "$UninstallString_DisplayName"
            WorkingDirectory = "C:\ProgramData\PowerDeploy"
        }


    $UninstallAppScript = $global:CustomScript
    # Export the txt file
    $UninstallCommandTXT = ExportTXT

    $UninstallCommand = $InstallCommand
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
    # $script:GI_MainInstallCommand    = $installCommand
    # $script:GI_MainInstallCommandTXT = $InstallCommandTXT

    $script:GI_UninstallCommand    = $UninstallCommand
    $script:GI_UninstallCommandTXT  = $UninstallCommandTXT
    $script:GI_UninstallAppScript      = $UninstallAppScript

    # Just for visibility, still log what we *think* we produced
    Write-Host "Return values prepared."
    Write-Host "   UninstallCommand     : $script:GI_UninstallCommand"
    Write-Host "   UninstallCommandTXT  : $script:GI_UninstallCommandTXT"
    Write-Host "   UninstallAppScript  : $script:GI_UninstallAppScript"

    Write-Host "SCRIPT: $ThisFileName | FUNCTION: $($MyInvocation.MyCommand.Name) | END"
    Write-host ""

    $Script:HashPattern = "UninstallApp"

    return "BuildMe"

    #Write-Log "For WinGet functions to work, the supplied AppName must be a valid, exact AppID" "WARNING"
    #Write-Log "For UninstallerString method, using wildcard search the registry uninstall strings for DisplayName equal to the supplied AppName"



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

if ($DesiredFunction -eq $null -or $DesiredFunction -eq ""){

    $DesiredFunction = Read-Host "Please enter the name of your desired function (InstallAppWithJSON, InstallPrinterByIP, RemediationScript)"

}

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


    } elseif($Script:HashPattern -eq "UninstallPrinterByName") {

        Write-Host "Building return hashtable for UninstallPrinterByName..."

        $result = @{
            UninstallCommand     = $script:GI_UninstallCommand
            UninstallCommandTXT  = $script:GI_UninstallCommandTXT
            UninstallPrinterScript   = $script:GI_UninstallPrinterScript
        }


    } elseif($Script:HashPattern -eq "UninstallApp"){

        Write-Host "Building return hashtable for UninstallApp..."

        $result = @{
            UninstallCommand     = $script:GI_UninstallCommand
            UninstallCommandTXT  = $script:GI_UninstallCommandTXT
            UninstallAppScript   = $script:GI_UninstallAppScript
        }


    } elseif ($Script:HashPattern -eq "RegRemediation"){


        $result = @{

            DetectScript = $script:GI_DetectScript
            DetectScriptCommandTXT = $script:GI_DetectScriptCommandTXT
            RemediationScript = $script:GI_RemediationScript
            RemediationScriptCommandTXT = $script:GI_RemediationScriptCommandTXT
        }


    }Else{

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
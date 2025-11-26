# The Master Helper

# Write remediation / detection



$ThisFileName = $MyInvocation.MyCommand.Name
$LogRoot = "$WorkingDirectory\Logs\Suite_Logs"

$LogPath = "$LogRoot\$ThisFileName.$ValueName._Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

$WorkingDirectory = (Split-Path $PSScriptRoot -Parent)
$RepoRoot = $PSScriptRoot

# path of WinGet installer
$WinGetInstallerScript = "$RepoRoot\Installers\General_WinGet_Installer.ps1"
# path of General uninstaller
$UninstallerScript = "$RepoRoot\Uninstallers\General_Uninstaller.ps1"
# path of the DotNet installer
$DotNetInstallerScript = "$RepoRoot\Installers\Install-DotNET.ps1"
# path to Git Runner
$GitRunnerScript = "$RepoRoot\Templates\Git_Runner_TEMPLATE.ps1"
# path of General_RemediationScriptSuite-Registry-Detection_TEMPLATE
$General_RemediationScript_Registry_TEMPLATE = "$RepoRoot\Templates\General_RemediationScript-Registry_TEMPLATE.ps1"
# path of Organization_CustomRegistryValues-Reader_TEMPLATE
$OrgRegReader_ScriptPath = "$RepoRoot\Templates\Organization_CustomRegistryValues-Reader_TEMPLATE.ps1"
# path of Generate_Install-Command script
$GenerateInstallCommand_ScriptPath = "$RepoRoot\Other_Tools\Generate_Install-Command.ps1"

$ExamplePrinterJSON = @"
{
  "printers": [
    {
      "PrinterName": "OLD_Printer",
      "PortName": "010.020.030.040",
      "PrinterIP":"10.20.30.40",
      "DriverName":"HP Universal Printing PCL 6",
      "INFFile":"hpcu270u.inf",
      "DriverZip":"printers/Drivers/HP/testDrivers.zip"
    },
		{
      "PrinterName": "NEW_Printer",
      "PortName": "010.020.030.041",
      "PrinterIP":"10.20.30.41",
      "DriverName":"HP Universal Printing PCL 6",
      "INFFile":"hpcu345u.inf",
      "DriverZip":"printers/Drivers/HP/HP_Universal_Printing_PCL_6/upd-pcl6-x64-7.9.0.26347.zip"
    }
}
"@

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
        "INFO"    { Write-Host $logEntry -ForegroundColor Cyan }
        "INFO2"    { Write-Host $logEntry }

        default   { Write-Host $logEntry }
    }
    
    # Ensure log directory exists
    $logDir = Split-Path $LogPath -Parent
    if (!(Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    Add-Content -Path $LogPath -Value $logEntry
}

function Make-RemediationScript-Registry-Detect{

    Write-Log "We will now create a detection script that looks for specific registry values. This detection script is to be used with a remediation script in InTune."

    Write-Log "Would you like to use another pre-existing detection script to build off of?"

    $Answer = Read-Host "y/n"
    Write-Log "User answer: $Answer"

        if ($answer -eq "y"){

            Write-Log "Please enter the full path of the script you wish to use as a base"

            $PathForPreExistingScript = Read-Host "Enter full path:"
            Write-Log "User answer: $PathForPreExistingScript"

            Write-Log "Checking if script exists..."

            if(Test-Path $PathForPreExistingScript){
                
                Write-Log "Script exists!"

                # Consume the script

                Write-Log "Here are the values found within the script you provided:"

                Write-Log "Keep? Delete? Modify?"

                Write-Log "Would you like add additional entries?"

            
            } else {
                
                Write-Log "Script does not exist!"
            
            }




        }




    Write-Log "Please enter the values for the first registry entry the script will look for"

    Write-Log "Will you be looking for another registry entry?"


    Write-Log "This is what the current arg line looks like, is this acceptable?"

    Write-Log "Creating new drag and drop script..."

    Write-Log "We will now create the remediation script..."

    Write-Log "Testing..."

    Write-Log "The scripts have been created and tested locally. Here are you instructions for putting them into InTune..."


}

function Make-RemediationScript-Registry-Remediate{}

function Make-InTuneWin32app-WinGet{

    # Confirm existance of WinGet item

    # Create Install Command

    # Create intunewin file

    # Create detect script

    # Run tests

}

function Make-InTuneWin32app-MSI{}

function Make-InTuneWin32app-Printer_IP_AzureBlob{}

function Make-Azure-Printer{

    # vars

    $parts = $PrinterDataJSONpath -split '/', 2

    $PrinterData_JSON_ContainerName = $parts[0]      
    $PrinterData_JSON_BlobName = $parts[1]



    # main 

    Write-Log "To begin, we need to prepare the resources required to set up a printer deployment via Intune."
    Write-Log ""

    # User needs:
        # - Printer Name
        # - Printer IP and Port
        # - Printer Driver INF file
        # - Printer Driver Name
        # - Printer Driver Zip Location in Azure Blob
    Write-Log "Before proceeding, you need these 6 items figured out:"
    Write-Log ""
    Write-Log "     1 - Printer Name"
    Write-Log "     2 - Printer IP"
    Write-Log "     3 - Printer Port - (Could be same as IP but formatted as full length eg 000.000.000.000)"
    Write-Log ""
    Write-Log "     > You may need to do research to find the correct driver for your printer model. Make sure to do testing:"
    Write-Log "     4 - Printer Driver INF file"
    Write-Log "     5 - Printer Driver Name"
    Write-Log ""
    Write-Log "     > Finally, you will need to upload the printer driver files to Azure Blob Storage if the required driver is not there already. This script will assist with this part if you don't have it yet."
    Write-Log "     6 - Printer Driver Zip Location in Azure Blob"
    Write-Log ""
    Write-Log "Save these details, as you will need them shortly."
    Write-Log ""
    Pause
    Write-Log ""

    # Determine the location of the azure blob based off of registry values
        
        # Go to "https://portal.azure.com/#view/Microsoft_Azure_StorageHub/StorageHub.MenuView/~/StorageAccountsBrowse"
        # Select this storage account: $AzureStorageAccountName
        # Select "Containers" from the left menu
        # Select this container: $AzureBlobContainerName
    Write-Log "Next we will update our Azure Blob Storage container with the required resources."
    Write-Log ""
    Write-Log "Instructions for navigating to your Azure Blob Storage container as follows:"
    Write-Log ""
    Write-Log " 1 - Go to https://portal.azure.com/#view/Microsoft_Azure_StorageHub/StorageHub.MenuView/~/StorageAccountsBrowse"
    Write-Log ""
    Write-Log " 2 - Select this storage account: $StorageAccountName"
    Write-Log ""
    Write-Log " 3 - Select 'Containers' from the left menu"
    Write-Log ""
    Write-Log " 4 - Select this container: $PrinterData_JSON_ContainerName"
    Write-Log ""
    Pause
    Write-Log ""

    # Write-Log ""



    # Tell the user of the location to place the print drivers in Azure Blob
    Write-Log "Next we need to ensure the correct printer drivers are in our Azure Blob Storage."
    Write-Log ""
    Write-Log "The location of your printer driver ZIP files in your Azure Blob Storage is: $PrinterData_JSON_ContainerName\Drivers"
    Write-Log ""
    Write-Log "Tip: - Use the Drivers folder to keep a neat structure of general driver packs from the manufacturers." 
    Write-Log "     - Example: $PrinterData_JSON_ContainerName\Drivers\HP\HP_Universal_Printing_PCL_6\[latestVersion].zip" 
    Write-Log "     - These driver packs carry the INF file needed for installation for most of their printers."
    Write-Log "     - Most of the time you WILL NOT need to upload a new driver if you have pre-existing manufacturer driver packs here."
    Write-Log "     - You can download the ZIP from the blob and explore the INF files for your printer model."
    Write-Log ""    
    Write-Log "If your required printer driver is not already in Azure Blob, please upload it now. Record the path you upload it to for later use."
    Write-Log ""    
    Pause
    Write-Log ""

    # Tell the user what the possible location of the printerJSON is in Azure Blob
        # From within the container, the path to the printer JSON should be: $AzureBlobContainerPath\$PrinterJSONFileName
        # Click on the JSON and navigate to edit
    Write-Log "Next we need to edit the Printer Data JSON file that contains the details of all printers available for deployment."
    Write-Log ""    
    Write-Log "From within the container, the path to the printer JSON should be: $PrinterDataJSONpath"
    Write-Log ""
    Write-Log "Click on the JSON and select to ""edit"""
    Write-Log ""
    Write-Log "Here is an example of what the JSON should look like:"
    Write-Log ""
    Write-Host $ExamplePrinterJSON
    Write-Log ""
    Write-Log "Add your new printer details to the JSON now, following the existing format within."
    Write-Log ""

    Pause
    Write-Log ""


    # Add the printer to InTune
        # Create the win32app
        # Tell the user where it is and how to import it into InTune
        # Create the detection script
        # Tell the user where it is and how to import it into InTune
    Write-Log "Now we will create the Intune Win32 app package for deploying the printer."
    Make-InTuneWin -SourceFile "$GitRunnerScript" 
    $PrinterIntuneWinPath = $Global:intunewinpath
    Write-Log ""    
    Write-Log "The Intune Win32 app package has been created at: $PrinterIntuneWinPath"
    Write-Log ""    

    Write-Log "Next we will create the install commands/scripts, please enter the name of your printer:" "WARNING"
    $PrinterName = Read-Host "Printer Name"
    Write-Log "" "INFO2"

        [hashtable]$FunctionParams = @{
            PrinterName = $PrinterName
        }
        $ReturnHash2 = & $GenerateInstallCommand_ScriptPath -DesiredFunction "InstallPrinterByIP" -FunctionParams $FunctionParams

        # Check the returned hashtable
        if(($ReturnHash2 -eq $null) -or ($ReturnHash2.Count -eq 0)){
            Write-Log "No data returned!" "ERROR"
            Exit 1
        }
        Write-Log "Values retrieved:" "INFO2"
        foreach ($key in $ReturnHash2.Keys) {
            $value = $ReturnHash2[$key]
            Write-Log "   $key : $value" "INFO2"
        }    

        # Turn the returned hashtable into variables
        Write-Log "Setting values as local variables..." "INFO2"
        foreach ($key in $ReturnHash2.Keys) {
            Set-Variable -Name $key -Value $ReturnHash2[$key] -Scope Local
            # Write-Log "Should be: $key = $($ReturnHash[$key])"
            $targetValue = Get-Variable -Name $key -Scope Local
            Write-Log "Ended up as: $key = $($targetValue.Value)" "INFO2"

        }
    Write-Log ""
    Write-Log "Install command and detection script created."
    Write-Log ""
    Pause
    Write-Log ""           
    Write-Log "We will next create an application in InTune for this printer using the new .intunewin file. Here are your instructions:"
    Write-Log ""    
    Write-Log " 1 - Navigate to Microsoft Endpoint Manager admin center > Devices > Windows > Windows apps > + Create > App type: Windows app (Win32)"
    Write-Log "     - Alt url: https://intune.microsoft.com/#view/Microsoft_Intune_DeviceSettings/AppsWindowsMenu/~/windowsApps"
    Write-Log ""   
    Write-Log " 2 - Upload the .intunewin file located here: $PrinterIntuneWinPath"
    Write-Log ""    
    Write-Log " 3 - APP INFORMATION:"
    write-log "     - Name: follow your org naming conventions, E.g., 'Printer - [Printer Name]'"
    Write-Log "     - Description: Include printer name, IP, driver version, location, etc following a common naming convention for you organization."
    Write-Log "     - Publisher: Your organization name"
    Write-Log "     - Logo: Optional - You could create something with Canva using your organization logo, but standardize it"
    Write-Log ""    
    Write-Log " 4 - PROGRAM:"
    Write-Log "     - Install command: The install command has already been attached to your clipboard! Simply paste it in there!"
    Write-Log "         - Alternatively, use the install command found inside this file: $MainInstallCommandTXT"
    Write-Log "     - Uninstall command: I have not set up uninstallation for printers. Perhaps I will in the future if time allows. For a dummy command, just type: net"
    Write-Log "     - Install time: 15 minutes"
    Write-Log "     - Allow available uninstall: No"
    Write-Log "     - Install behavior: System"
    Write-Log "     - Device restart behavior: No specific action"
    Write-Log ""    
    Write-Log " 5 - REQUIREMENTS:"
    Write-Log "     - Check operating system architecture if needed (most printers will work on both x86 and x64 but not ARM64). You can skip if desired."
    Write-Log "     - Minimum operating system: Doesn't matter."
    Write-Log ""
    Write-Log " 6 - DETECTION:"
    Write-Log "     - Rules format: Use a custom detection script"
    Write-Log "     - Script File: Upload this script: $DetectPrinterScript"
    Write-Log "     - Run script as 32-bit process on 64-bit clients: Yes"
    Write-Log "     - Enforce script signature check: No"
    Write-Log ""
    Write-Log " 7 - DEPENDENCIES: None"
    Write-Log ""
    Write-Log " 8 - SUPERSEDENCE: None"
    Write-Log ""
    Write-Log " 9 - ASSIGNMENTS: Assign to the required groups/devices for your organization."
    Write-Log ""
    Pause
    Write-Log ""
    Write-Log "Printer deployment setup is complete! Please verify functionality on a test device. The printer will both be available from the Company Portal for the assigned devices AND from the local Printer Installer script in this repo." "SUCCESS"
    Write-Log ""    
    Pause


}

Function Make-Azure-WindowsApplication{

    Write-Log "This function is under construction." "ERROR"
    Exit 1


}

Function Make-InTuneWin {

    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFile,   # Path to your installer/script (exe, msi, ps1, etc.)

        [string]$IntuneToolsDir = "$WorkingDirectory\Temp\Tools",
        [string]$TempRoot       = "$WorkingDirectory\Temp\IntuneSource\$(Get-Date -Format 'yyyyMMdd_HHmmss')",
        [string]$OutputFolder   = "$WorkingDirectory\Temp\IntuneOutput\$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    )

    $ErrorActionPreference = 'Stop'

    # Ensure the existence of the Intune Win32 Content Prep Tool

        # Where we'll store IntuneWinAppUtil.exe
        $IntuneWinAppUtil = Join-Path $IntuneToolsDir "IntuneWinAppUtil.exe"

        # URL for the Intune Win32 Content Prep Tool (from Microsoft download center)
        $IntuneWinAppUtilUrl = "https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool/raw/master/IntuneWinAppUtil.exe"

        # Ensure tools directory exists
        if (-not (Test-Path $IntuneToolsDir)) {
            New-Item -Path $IntuneToolsDir -ItemType Directory -Force | Out-Null
        }

        # Download IntuneWinAppUtil.exe if missing
        if (-not (Test-Path $IntuneWinAppUtil)) {
            Write-Log "Downloading IntuneWinAppUtil.exe..." "INFO2"
            Invoke-WebRequest -Uri $IntuneWinAppUtilUrl -OutFile $IntuneWinAppUtil
            Write-Log "Downloaded IntuneWinAppUtil.exe to $IntuneWinAppUtil" "INFO2"
        }

        # Resolve and split the source file
        $sourceFileFull = (Resolve-Path $SourceFile).Path
        $sourceFileName = Split-Path $sourceFileFull -Leaf
        $packageName    = [IO.Path]::GetFileNameWithoutExtension($sourceFileName)

        # Create unique temp source dir
        $timeStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $workingDir = Join-Path $TempRoot "${packageName}_$timeStamp"

        New-Item -Path $workingDir -ItemType Directory -Force | Out-Null
        New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null

        # Copy target file into temp dir
        Copy-Item -Path $sourceFileFull -Destination $workingDir -Force
        #Write-Log "Source copied to: $workingDir"

        # Run Intune Win32 Content Prep Tool
        & $IntuneWinAppUtil `
            -c $workingDir `
            -s $sourceFileName `
            -o $OutputFolder `
            -q | Out-Null

        # Show the resulting .intunewin file
        # $intuneWin = Get-ChildItem -Path $OutputFolder -Filter '*.intunewin' -Recurse |
        #             Sort-Object LastWriteTime -Descending |
        #             Select-Object -First 1
        
        $intunewin = Get-ChildItem -path $outputfolder | Where-Object { $_.Extension -eq ".intunewin" }
        #$intunewin = Get-ChildItem -path $outputfolder | Where-Object { $_ -like "*.intunewin" }

        $Global:intunewin = $intunewin.name
        $Global:intunewinpath = "$outputfolder\$intunewin"
        # "intunewin file name: "

        # $intunewin


        if ($intuneWin) {
            #Write-Log "Created Intune package: $intuneWin"
            #return $intuneWin.FullName
        } else {
            Write-Log "No .intunewin file found in $OutputFolder." "ERROR"
            Throw "Intune package creation failed."
        }



    #Return $intuneWin

}

##########
## MAIN ##
########## 

# Setup 


Write-Log "SCRIPT: $ThisFileName | START"
Write-Log ""
Write-Log "================================="
Write-Log "===== Set Up Asset in Azure ====="
Write-Log "================================="
Write-Log ""
Write-Log "Welcome to Azure Asset Setup! This helper will guide you through creating various Azure-related assets for deployment via Azure/Intune."
Write-Log ""
Write-Log "When you are ready we will begin by checking pre-requisites..."
Write-Log ""
Pause
Write-Log "" "INFO2"

Try{
# Grab organization custom registry values
    Write-Log "Retrieving organization custom registry values..." "INFO2"
    $ReturnHash = & $OrgRegReader_ScriptPath #| Out-Null

    # Check the returned hashtable
    if(($ReturnHash -eq $null) -or ($ReturnHash.Count -eq 0)){
        Write-Log "No data returned from Organization Registry Reader script!" "ERROR"
        Exit 1
    }
    #Write-Log "Organization custom registry values retrieved:"
    foreach ($key in $ReturnHash.Keys) {
        $value = $ReturnHash[$key]
        Write-Log "   $key : $value" "INFO2"
    }    

    # Turn the returned hashtable into variables
    Write-Log "Setting organization custom registry values as local variables..." "INFO2"
    foreach ($key in $ReturnHash.Keys) {
        Set-Variable -Name $key -Value $ReturnHash[$key] -Scope Local
        Write-Log "Should be: $key = $($ReturnHash[$key])" "INFO2"
        $targetValue = Get-Variable -Name $key -Scope Local
        Write-Log "Ended up as: $key = $($targetValue.Value)" "INFO2"

    }
} Catch {
    Write-Log "Error retrieving organization custom registry values: $_" "ERROR"
    Exit 1
}

Write-Log ""
Write-Log "Pre-reqs check complete."
Write-Log ""
Pause
Write-Log ""
Write-Log "================================="
Write-Log ""

Write-Log "These are the functions currently available through this script:"
Write-Log ""

$methods = Get-Command -CommandType Function -Name "Make-Azure-*" | Select-Object -ExpandProperty Name

$AvailableTests = @{}

#Write-Log "Available Functions:" "INFO"
$COUNTER = 1
$methods | ForEach-Object { 
    
    Write-Log "$Counter - $_" "INFO"
    $AvailableTests.add($Counter,$_)
    $Counter++ 

}

Write-Log "================================="
Write-Log ""

Write-Log "Enter the # of your desired function:" "WARNING"
[int]$SelectedFunctionNumber = Read-Host "Please enter a #"

$SelectedFunction = $AvailableTests[$SelectedFunctionNumber]
Write-Log ""
Write-Log "You have selected: $SelectedFunction"
Write-Log "================================="
Write-Log ""
& $SelectedFunction
Write-Log "================================="
Write-Log ""
Write-Log "SCRIPT: $ThisFileName | END | Function $SelectedFunction complete" "SUCCESS"
Exit 0
# The Master Helper

# Write remediation / detection



$ThisFileName = $MyInvocation.MyCommand.Name
$LogRoot = "$WorkingDirectory\Logs\Setup_Logs"

$LogPath = "$LogRoot\$ThisFileName._Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

$WorkingDirectory = (Split-Path $PSScriptRoot -Parent)
$RepoRoot = $PSScriptRoot

# path of WinGet installer
$WinGetInstallerScript = "$RepoRoot\Installers\General_WinGet_Installer.ps1"
# path of General uninstaller
$UninstallerScript = "$RepoRoot\Uninstallers\General_Uninstaller.ps1"
# path of the DotNet installer
$DotNetInstallerScript = "$RepoRoot\Installers\Install-DotNET.ps1"
# path to Git Runner
$GitRunnerScript = "$RepoRoot\Templates\Git-Runner_TEMPLATE.ps1"
# path of General_RemediationScriptSuite-Registry-Detection_TEMPLATE
$General_RemediationScript_Registry_TEMPLATE = "$RepoRoot\Templates\General_RemediationScript-Registry_TEMPLATE.ps1"
# path of Organization_CustomRegistryValues-Reader_TEMPLATE
$OrgRegReader_ScriptPath = "$RepoRoot\Templates\OrganizationCustomRegistryValues-Reader_TEMPLATE.ps1"
# path of Generate_Install-Command script
$GenerateInstallCommand_ScriptPath = "$RepoRoot\Other_Tools\Generate_Install-Command.ps1"
# path of the Azure Blob SAS downloader script
$DownloadAzureBlobSAS_ScriptPath = "$RepoRoot\Downloaders\DownloadFrom-AzureBlob-SAS.ps1"
# Path to the printer install script
$InstallPrinterIP_ScriptPath = "$RepoRoot\Installers\General_IP-Printer_Installer.ps1"
# Path to JSON app install script
$JSONAppInstaller_ScriptPath = "$RepoRoot\Installers\General_JSON-App_Installer.ps1"


$PublicJSONpath = "$RepoRoot\Templates\ApplicationData_TEMPLATE.json"


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

$ExampleAppJSON = @"
{
  "Applications": [
  {
    "ApplicationName": "Visual_Studio_Code",
    "InstallMethod": "WinGet",
    "WinGetID":"Microsoft.VisualStudioCode"
  },
  {
    "ApplicationName": ".NET_3.5",
    "InstallMethod": "Custom_Script",
    "ScriptPathFromRepoRoot":"Installers\\Install-DotNET.ps1",
    "CustomScriptArgs":"-Version \"3.5\""
  },
  {
    "ApplicationName": "MSI-Private-AzureBlob_Example",
    "InstallMethod": "MSI-Private-AzureBlob",
    "MSIPathFromContainerRoot":"Adobe_Creative_Cloud/install.msi",
    "DisplayName":"Adobe Creative Cloud",
    "PreRequisites":".NET_3.5,Visual_Studio_Code"
  },
  ]
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

function Setup--Azure-Printer{

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
    Write-Log "Please enter the name of your printer:" "WARNING"
    $PrinterName = Read-Host "Printer Name"
    While ([string]::IsNullOrWhiteSpace($PrinterName)) {
        Write-Log "No printer name provided. Please enter a printer name." "ERROR"
        $PrinterName = Read-Host "Printer Name"
    }
    Write-Log "Printer Name set to: $PrinterName"




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
    Write-Log " 3 - Select 'Data Storage' > 'Containers' from the left menu"
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
    Write-Log "Please note the following"
    Write-Log "     - Use the Drivers folder to keep a neat structure of general driver packs from the manufacturers." 
    Write-Log "     - Example: $PrinterData_JSON_ContainerName\Drivers\HP\HP_Universal_Printing_PCL_6\[latestVersion].zip" 
    Write-Log "     - These driver packs carry the INF file needed for installation for most of the specific manufacturer's printers."
    Write-Log "     - Most of the time you WILL NOT need to upload a new driver if you have pre-existing manufacturer driver packs (PCL/PostScript) here."
    Write-Log "     - How do you determine the appropriate INF?"
    Write-Log "       - EXAMPLE: After looking up your specific Printer's driver for Windows Server..."
    Write-Log "       - If HP says an appropriate driver is ""HP Universal Print Driver for Windows PCL6 (64-bit)"", then the INF file that should end up being targetted is always hpcu***u.inf (the only INF in that pack with those drivers)"
    Write-Log "     - If you end up needing to download the driver, when you are looking for the driver online you may need to change the target OS to Windows Server in order to find the PCL/PostScript drivers."
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
    Write-Log "Add your new printer details to the JSON now, following the existing format within. Save when you are finished."
    Write-Log ""

    Pause
    Write-Log ""

    # Suggest testing the JSON with the local install script
    Write-Log "After updating the Printer Data JSON, it is highly recommended to test the installation of the new printer on a local machine before proceeding with Intune deployment."
    Write-Log "This will help ensure that all details are correct and the installation process works as expected."
    Write-Log ""
    Write-Log "Would you like this script to test this printer installation from the JSON on this local machine? (y/n)" "WARNING"
    $Answer = Read-Host "y/n"
    Write-Log ""


        if ($answer -eq "y"){

            Write-Log "Before proceeding, please make sure this printer is not already installed locally on this machine. If it is, please uninstall it first." "WARNING"
            Pause
            Write-Log "Proceeding with local installation test..."

            & Install--Local-Printer -PrinterName $PrinterName

            if($LASTEXITCODE -ne 0){
                Write-Log "Local printer installation test failed with exit code: $LASTEXITCODE" "ERROR"
                Write-Log "Please resolve any issues before proceeding with Intune deployment."
                Exit $LASTEXITCODE
            } else {
                Write-Log "Local printer installation test succeeded! This configuration for the JSON works!" "SUCCESS"
            }   

        } else {

            Write-Log "Skipping local installation test. Proceeding with Intune deployment setup."

        }

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

    Write-Log "Next we will automatically create the install commands/scripts"

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

        # $result = $ReturnHash2
        # foreach ($key in $result.Keys) {

        #     Write-Host "   $key : $($result[$key])"

        # }


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
    Write-Log "We will next create a Win32 application in InTune for this printer using the new .intunewin file. Here are your instructions:"
    Write-Log ""    
    Write-Log " 1 - Navigate to Microsoft Endpoint Manager admin center > Devices > Windows > Windows apps"
    Write-Log "     - Alt url: https://intune.microsoft.com/#view/Microsoft_Intune_DeviceSettings/AppsWindowsMenu/~/windowsApps"
    Write-Log "     - + Create > App type: Windows app (Win32)"
    Write-Log ""   
    Write-Log " 2 - Upload the .intunewin file located here: $PrinterIntuneWinPath"
    Write-Log ""    
    Write-Log " 3 - APP INFORMATION:"
    write-log "     - Name: follow your org naming conventions, E.g., 'PRINTER: [Printer Name]'"
    Write-Log "     - Description: Include printer name, IP, driver version, location, etc following a common naming convention for you organization."
    Write-Log "     - Publisher: Your organization name"
    Write-Log "     - Logo: Optional - You could create something with Canva using your organization logo, but standardize it"
    Write-Log ""    
    Write-Log " 4 - PROGRAM:"
    Write-Log "     - Install command: The install command has already been attached to your clipboard! Simply paste it in there!"
    Write-Log "         - Alternatively, use the install command found inside this file: $MainInstallCommandTXT"
    Write-Log "     - Uninstall command: I have not set up uninstallation for apps for Company Portal. Handle these externally or develop your own method. Perhaps I will integrate uninstallation with InTune in the future if time allows. For a dummy command, just type: net"
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
    Write-Log "     - Run script as 32-bit process on 64-bit clients: No"
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
    Write-Log "Printer deployment setup is complete! Please verify functionality on a test device. The printer will both be available from the Company Portal for the assigned devices AND from the local Printer Installer function in this script." "SUCCESS"
    Write-Log ""    
    Pause


}

Function Setup--Azure-WindowsApp{


    # vars

    $parts = $ApplicationDataJSONpath -split '/', 2

    $ApplicationData_JSON_ContainerName = $parts[0]      
    $ApplicationData_JSON_BlobName = $parts[1]



    # main 

    Write-Log "To begin, we need to prepare the resources required to set up an application deployment via Intune."
    Write-Log ""
    Write-Log "Application data is stored in one of two JSON files:"
    Write-Log " - Public JSON: $PublicJSONpath"
    Write-Log " - Private JSON: Accessible via your Azure Blob Storage container. We can determine this location later."

    # User needs:
        # If application IS in the public or private JSON...
            # - Application Name (that's it!!)
        # If application IS NOT in the public or private JSON...
            # - Application Name
            # - Install Method
                # if Winget:
                    # - Winget ID
                # if MSI-Online
                    # - URL
                    # - MSI name
                # if Custom_Script
                    # - Script Path from Repo Root
                    # - Custom Script Args (if any)
            # - PreRequisites (if any)


    Write-Log ""
    Write-Log "REQUIRED RESOURCES:"
    Write-Log ""
    Write-Log "If application IS ALREADY in the public or private JSON..."
    Write-Log "    1 - Application Name (that's it!!)"
    Write-Log ""
    Write-Log "If application IS NOT in the public or private JSON..."
    Write-Log "    1 - Application Name"
    Write-Log "    2 - Install Method"
    Write-Log "        if Winget:"
    Write-Log "            - Winget ID"
    Write-Log "        if MSI-Online"
    Write-Log "            - URL"
    Write-Log "            - MSI name"
    Write-Log "        if Custom_Script"
    Write-Log "            - Script Path from Repo Root"
    Write-Log "            - Custom Script Args (if any)"
    Write-Log "    3 - PreRequisites (if any)"
    Write-Log ""
    Write-Log "Save these details, as you will need them shortly."
    Write-Log ""

    Pause
    Write-Log ""
    Write-Log "Next we will see what applications are already available in the public and private JSON files."
    Write-Log ""

    Pause
    $TargetApp = $null
    $TargetApp = Select-ApplicationFromJSON

    Write-Log "" 

    If ($AppNameToFind -eq "" -or $AppNameToFind -eq $null) {
        Write-Log "Please enter the name of the application (as you want it to appear in the JSON) to set up for Intune deployment:" "WARNING"
        $AppNameToFind = Read-Host "Application Name"
        While ([string]::IsNullOrWhiteSpace($AppNameToFind) -or $AppNameToFind -eq "exit") {
            Write-Log "No application name provided. Please enter an application name." "ERROR"
            $AppNameToFind = Read-Host "Application Name"
        }

        $TargetApp = Select-ApplicationFromJSON -AppNameToFind $AppNameToFind
        Write-Log ""

        #Write-Log "Application Name set to: $AppNameToFind"
    } else {
        Write-Log "Using provided application name: $AppNameToFind"
    }

    Write-Log "" 


    if ($TargetApp -eq $null) {
        
        
        Write-Log "No pre-existing application entry for $AppNameToFind was selected from the JSON files. We will move forward with doing a new custom application entry in the private JSON."
        
        Write-Log ""

        Pause

        Write-Log ""

        Write-Log "Next we will navigate to our Azure Blob Storage container to edit the private JSON to add your new application."
        Write-Log ""
        Write-Log "Instructions for navigating to your Azure Blob Storage container as follows:"
        Write-Log ""
        Write-Log " 1 - Go to https://portal.azure.com/#view/Microsoft_Azure_StorageHub/StorageHub.MenuView/~/StorageAccountsBrowse"
        Write-Log ""
        Write-Log " 2 - Select this storage account: $StorageAccountName"
        Write-Log ""
        Write-Log " 3 - Select 'Data Storage' > 'Containers' from the left menu"
        Write-Log ""
        Write-Log " 4 - Select this container: $ApplicationData_JSON_ContainerName"
        Write-Log ""
        Pause

        Write-Log ""    
        Write-Log "Next we need to edit the private JSON file (ApplicationData.json) which contains the details of all custom applications available for deployment."
        Write-Log ""    
        Write-Log "From within the container, the path to the application JSON should be: $ApplicationDataJSONpath"
        Write-Log ""
        Write-Log "Click on the JSON and select to ""edit"""
        Write-Log ""
        Write-Log "Here is an example of what the JSON should look like:"
        Write-Log ""
        Write-Host $ExampleAppJSON
        Write-Log ""
        Write-Log "Add your new application details to the JSON now, following the existing format within. Save when you are finished."
        Write-Log ""

        Pause

        # Suggest testing the JSON with the local install script
        Write-Log "After updating the Application Data JSON, it is highly recommended to test the installation of the new application on a local machine before proceeding with Intune deployment."
        Write-Log "This will help ensure that all details are correct and the installation process works as expected."
        Write-Log ""
        Write-Log "Would you like this script to test this application installation from the JSON on this local machine? (y/n)" "WARNING"
        $Answer = Read-Host "y/n"
        Write-Log ""


            if ($answer -eq "y"){

                Write-Log "Before proceeding, please make sure this application is not already installed locally on this machine. If it is, please uninstall it first." "WARNING"
                Pause
                Write-Log "Proceeding with local installation test..."

                & Install--Local-Application -ApplicationName $ApplicationName
                if($LASTEXITCODE -ne 0){
                    Write-Log "Local application installation test failed with exit code: $LASTEXITCODE" "ERROR"
                    Write-Log "Please resolve any issues before proceeding with Intune deployment."
                    Exit $LASTEXITCODE
                } else {
                    Write-Log "Local application installation test succeeded! This configuration for the JSON works!" "SUCCESS"
                }   

            } else {

                Write-Log "Skipping local installation test. Proceeding with Intune deployment setup."

            }

        Write-Log ""
        Pause
        Write-Log ""

        Write-Log "Checking if you updated either JSON with the new application..."
        Write-Log ""

        Pause
        $TargetApp = Select-ApplicationFromJSON -AppNameToFind $AppNameToFind

        if ($TargetApp -eq $null){

            Write-Log "The application '$AppNameToFind' was still not found in either JSON. Please ensure you have added it correctly and re-run this setup process." "ERROR"
            Exit 1

        }
        Pause
    
    }


    Write-Log "Now we will create the Intune Win32 app package for deploying the application."
    Make-InTuneWin -SourceFile "$GitRunnerScript" 
    $ApplicationIntuneWinPath = $Global:intunewinpath
    Write-Log ""    
    Write-Log "The Intune Win32 app package has been created at: $ApplicationIntuneWinPath"
    Write-Log ""    

    Write-Log "Next we will automatically create the install commands/scripts"

    Write-Log ""    



    # If sufficient info is present from the JSON, we can generate the install command and detection script. Otherwise user needs to enter it manually and update their JSON.

    # Needed info:
            # - Install Method
                # if Winget:
                    # - Winget ID
                # if MSI-Online
                    # - URL
                    # - MSI name
                # if Custom_Script
                    # - Script Path from Repo Root
                    # - Custom Script Args (if any)
            # - PreRequisites (if any)


    While ($InstallMethod -eq $null -or ($InstallMethod -eq "")) {

        Write-Log "The application '$ApplicationName' does not have sufficient information for the InstallMethod var in the JSON to auto-generate install command and detection script." "WARNING"
        Write-Log "Please update your JSON and then continue this script." "WARNING"
        Pause   
        Select-ApplicationFromJSON -AppNameToFind $AppNameToFind

    }

    if ($InstallMethod -eq "WinGet" -or $DetectMethod -eq "WinGet") {

        if($WinGetID -eq $null -or $WinGetID -eq ""){
            Write-Log "The application '$ApplicationName' does not have a WinGet ID specified in the JSON. Please update your JSON with the required fields and re-run this setup process for automatic generation." "ERROR"
            Exit 1
        }

        [hashtable]$FunctionParams = @{
            ApplicationName = $ApplicationName
            AppID = $WinGetID
            DetectMethod = "WinGet"
        }

        Write-log "Detect method set as WinGet"

    } elseif ($InstallMethod -eq "MSI-Private-AzureBlob" -or $DetectMethod -eq "MSI_Registry") {

        if ($DisplayName -eq $null -or $DisplayName -eq "") {
            Write-Log "The application '$ApplicationName' does not have a Display Name specified in the JSON. Please update your JSON with the required fields and re-run this setup process for automatic generation." "ERROR"
            Exit 1
        }

        [hashtable]$FunctionParams = @{
            ApplicationName = $ApplicationName
            DisplayName = $DisplayName
            DetectMethod = "MSI_Registry"
        }

        Write-Log "Detect method set as MSI_Registry"

    } else {

        Write-Log "Unknown Install Method or missing Detect Method. Please correct this in the JSON and re-run this setup process." "ERROR"
        Write-Log "Install Method: $InstallMethod" 
        Write-Log "Detect Method: $DetectMethod" 

        Exit 1

    }

    Write-Log "" "INFO2"




    <#
    # Run the automation script to generate the install command and detection script
    $ReturnHash2 = & $GenerateInstallCommand_ScriptPath -DesiredFunction "InstallAppWithJSON" -FunctionParams $FunctionParams
    #$ReturnHash2 = & $GenerateInstallCommand_ScriptPath -DesiredFunction "InstallPrinterByIP" -FunctionParams $FunctionParams

    # Check the returned hashtable
    if(($ReturnHash2 -eq $null) -or ($ReturnHash2.Count -eq 0)){
        Write-Log "No data returned!" "ERROR"
        Exit 1
    }
    
    Write-Log "Values retrieved:" "INFO2"

    #$ReturnHash2
    foreach ($key in $ReturnHash2.Keys) {
        $value = $ReturnHash2[$key]
        Write-Log "   $key : $value" "INFO2"
    }    

    # Turn the returned hashtable into variables
    Write-Log "Setting values as local variables..." "INFO2"
    foreach ($key in $ReturnHash2.Keys) {

        $value = $ReturnHash2[$key]
        Write-Log "   $key : $value" "INFO2"


        Set-Variable -Name $key -Value $value -Scope Local

        # Write-Log "Should be: $key = $($ReturnHash[$key])"
        $targetValue = Get-Variable -Name $key -Scope Local
        Write-Log "Ended up as: $key = $($targetValue.Value)" "INFO2"

    }
    #>

    # Call the generator; this now returns the hashtable we want
    $installResult = @{}
    $installResult = & $GenerateInstallCommand_ScriptPath `
        -DesiredFunction "InstallAppWithJSON" `
        -FunctionParams $FunctionParams

    # Sanity check
    if (($installResult -eq $null) -or ($installResult.Count -eq 0)) {
        Write-Log "No data returned from Generate_Install-Command.ps1!" "ERROR"
        exit 1
    }

    Write-Log "Values retrieved:" "INFO2"
    foreach ($key in $installResult.Keys) {
        Write-Log "   $key : $($installResult[$key])" "INFO2"
    }

    Write-Log "Setting values as local variables..." "INFO2"
    foreach ($key in $installResult.Keys) {
        $value = $installResult[$key]
        Write-Log "   $key : $value" "INFO2"

        Set-Variable -Name $key -Value $value -Scope Local

        $targetValue = Get-Variable -Name $key -Scope Local
        Write-Log "Ended up as: $key = $($targetValue.Value)" "INFO2"
    }

    

    Write-Log ""
    Write-Log "Install command and detection script created."
    Write-Log ""
    Pause



    Write-Log ""           
    Write-Log "We will next create a Win32 application in InTune for this app using the new .intunewin file. Here are your instructions:"
    Write-Log ""    
    Write-Log " 1 - Navigate to Microsoft Endpoint Manager admin center > Devices > Windows > Windows apps"
    Write-Log "     - Alt url: https://intune.microsoft.com/#view/Microsoft_Intune_DeviceSettings/AppsWindowsMenu/~/windowsApps"
    Write-Log "     - + Create > App type: Windows app (Win32)"
    Write-Log ""   
    Write-Log " 2 - Upload the .intunewin file located here: $ApplicationIntuneWinPath"
    Write-Log ""    
    Write-Log " 3 - APP INFORMATION:"
    write-log "     - Name: follow your org naming conventions, E.g., 'APP: [App Name]'"
    Write-Log "     - Description: Up to your descretion. Copying the description from Windows Store, App website, etc could be beneficial.,"
    Write-Log "     - Version: Recommend to leave blank unless you are using a static installer."
    Write-Log "     - Logo: Optional - You could create something with Canva using your organization logo, but standardize it"
    Write-Log "     - Everything else on this page is up to your discretion."
    Write-Log ""    
    Write-Log " 4 - PROGRAM:"
    Write-Log "     - Install command: The install command has already been attached to your clipboard! Simply paste it in there!"
    Write-Log "         - Alternatively, use the install command found inside this file: $MainInstallCommandTXT"
    Write-Log "     - Uninstall command: I have not set up uninstallation for apps for Company Portal. Handle these externally or develop your own method. Perhaps I will integrate uninstallation with InTune in the future if time allows. For a dummy command, just type: net"
    Write-Log "     - Install time: 15 minutes"
    Write-Log "     - Allow available uninstall: No"
    Write-Log "     - Install behavior: System"
    Write-Log "     - Device restart behavior: No specific action"
    Write-Log ""    
    Write-Log " 5 - REQUIREMENTS:"
    Write-Log "     - Architecture: Unnecessary unless you know the app is specific to x86 or x64. WinGet apps will handle this automatically."
    Write-Log "     - Minimum operating system: Minimum available version unless you know otherwise."
    Write-Log ""
    Write-Log " 6 - DETECTION:"
    Write-Log "     - Rules format: Use a custom detection script"
    Write-Log "     - Script File: Upload this script: $DetectAppScript"
    Write-Log "     - Run script as 32-bit process on 64-bit clients: No"
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
    Write-Log "Application deployment setup is complete! Please verify functionality on a test device. The application will both be available from the Company Portal for the assigned devices AND from the local Application Installer function in this script." "SUCCESS"
    Write-Log ""    
    Pause


}

Function Make-InTuneWin {

    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFile,   # Path to your installer/script (exe, msi, ps1, etc.)

        [string]$IntuneToolsDir = "$WorkingDirectory\Temp\Tools",
        [string]$TempRoot       = "$WorkingDirectory\Temp\IntuneWin_Source\$(Get-Date -Format 'yyyyMMdd_HHmmss')",
        [string]$OutputFolder   = "$WorkingDirectory\Temp\IntuneWin_Output\$(Get-Date -Format 'yyyyMMdd_HHmmss')"
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

Function Install--Local-Printer{
    Param(

        $PrinterName=$null

    )

    Write-Log "To begin we will access the PrinterData.json file stored in Azure Blob Storage to show you the available printers."
    Write-Log ""

    Pause

    Write-Log "Now constructing URI for accessing PrinterData.json..." "INFO2"
    
    ## Show available printers from JSON ##

    # This snippet was taken from the Install-Printer-IP script

    $parts = $PrinterDataJSONpath -split '/', 2

    $PrinterData_JSON_ContainerName = $parts[0]      
    $PrinterData_JSON_BlobName = $parts[1]

    # $parts = $ApplicationDataJSONpath -split '\\', 2
    # $ApplicationData_JSON_ContainerName = $parts[0]      
    # $ApplicationData_JSON_BlobName = $parts[1]

    $SasToken = $PrinterContainerSASkey

    # Write-Log "Insufficient params. Each of these cannot be empty:" "ERROR"
    # Write-Log "StorageAccountName: $StorageAccountName"
    # Write-Log "SasToken: $SasToken"
    # Write-Log "PrinterData_JSON_ContainerName: $PrinterData_JSON_ContainerName"
    # Write-Log "PrinterData_JSON_BlobName: $PrinterData_JSON_BlobName"
    # Exit 1

    Write-Log "Final values to be used to build PrinterData.json URI:" "INFO2"
    Write-Log "StorageAccountName: $StorageAccountName" "INFO2"
    Write-Log "SasToken: $SasToken" "INFO2"
    Write-Log "PrinterData_JSON_ContainerName: $PrinterData_JSON_ContainerName" "INFO2"
    Write-Log "PrinterData_JSON_BlobName: $PrinterData_JSON_BlobName" "INFO2"

    $printerJSONUri = "https://$StorageAccountName.blob.core.windows.net/$PrinterData_JSON_ContainerName/$PrinterData_JSON_BlobName"+"?"+"$SasToken"


    Write-Log "Attempting to access PrinterData.json with this URI: $printerJSONUri" "INFO2"

    Try{

        # TODO: Try and create a snippet that can directly parse JSOn from web
        #$data = Invoke-RestMethod "$printerJSONUri"

        #$Result =Invoke-WebRequest -Uri $printerJSONUri -OutFile "$WorkingDirectory\temp\PrinterData.json" -UseBasicParsing

        Write-Log "Beginning download..." "INFO2"
        & $DownloadAzureBlobSAS_ScriptPath -WorkingDirectory $WorkingDirectory -BlobName $PrinterData_JSON_BlobName -StorageAccountName $StorageAccountName -ContainerName $PrinterData_JSON_ContainerName -SasToken $SasToken
        if($LASTEXITCODE -ne 0){Throw $LASTEXITCODE }

        Write-Log "Parsing JSON" "INFO2"
        $LocalJSONpath = "$WorkingDirectory\TEMP\Downloads\$PrinterData_JSON_BlobName"
        if (Test-Path $LocalJSONpath) {Write-Log "Local JSON found. Attempting to get content." "INFO2"} else { Write-Log "Local JSON not found" "ERROR"; throw "Local JSON not found" }
        #$jsonData = Get-Content -Raw $LocalJSONpath | ConvertFrom-Json
        try {
            $jsonText = Get-Content -LiteralPath $LocalJSONpath -Raw -Encoding UTF8
            $jsonData = $jsonText | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Log "ConvertFrom-Json failed: $($_.Exception.Message)" "ERROR"
            throw $_
        }

        # "Printers count: {0}" -f ($jsonData.printers.Count)
        # $jsonData.printers[0] | Format-List *
        Write-Log "" "INFO2"

        # Can comment out
        Write-Log "Here are all the printers we found from the JSON:"
        Write-Log ""
        $list = $jsonData.printers.PrinterName 
        Foreach ($item in $list) {
            Write-Log "$item"
        }
        Write-Log "" 


    }catch{

        Write-Log "Accessing JSON failed. Exit code returned: $_"
        Exit 1
        
    }

    ## Prompt user to select printer IF one was not provided ##
    if ($PrinterName -ne $null) {

        Write-Log "Printer name provided as parameter: $PrinterName"


    } else {

        Write-Log "Please enter the name of the printer you wish to install from the above list:" "WARNING"
        $PrinterName = Read-Host "Printer Name"
        While ([string]::IsNullOrWhiteSpace($PrinterName)) {
            Write-Log "No printer name provided. Please enter a printer name from the list above:" "ERROR"
            $PrinterName = Read-Host "Printer Name"
        }

    }


    Write-Log ""


    ## Install selected printer ##

        Write-Log "Here is all the data on Printer ($PrinterName):" "INFO2"
        $printer = $jsonData.printers | Where-Object { $_.PrinterName -eq $PrinterName }
        Write-Log "" "INFO2"

        if ($printer) {
            
            # Write-Log "Formatted list:"
            # $printer | Format-List *

            # Write-Log "This is the IP address"
            # $printer.PrinterIP


            # Write-Log "Attempting to digest data into PowerShell objects..." "INFO2"
            Set-VariablesFromObject -InputObject $printer -Scope Script
            # Write-Log "" "INFO2"
            # Write-Log "These are the obtained values that are now PowerShell objects:" "INFO2"
            Write-Log "Port Name: $PortName" "INFO2"
            Write-Log "Printer IP: $PrinterIP" "INFO2"
            Write-Log "Printer Name: $PrinterName" "INFO2"
            Write-Log "Driver Name: $DriverName" "INFO2"
            Write-Log "INF File: $INFFile" "INFO2"
            Write-Log "DriverZip: $DriverZip" "INFO2"
            # Write-Log "" "INFO2"

        } else {
            Write-Log "Printer '$PrinterName' not found. Your spelling may be incorrect." "ERROR"
            Exit 1
        }
    # Call the Install-Printer-IP script with the obtained values
    Write-Log "" "INFO2"
    Write-Log "Next we will attempt to install the selected printer ($PrinterName) using the install script."
    Write-Log ""
    Pause

    & $InstallPrinterIP_ScriptPath -PrinterName $PrinterName -WorkingDirectory $WorkingDirectory
    
    
    Write-Log "" 
    if($LASTEXITCODE -ne 0){
        Write-Log "Install-Printer-IP script failed with exit code: $LASTEXITCODE" "ERROR"
        Exit $LASTEXITCODE
    } else {
        Write-Log "Printer '$PrinterName' installed successfully!" "SUCCESS"
    }   

}   

Function Install--Local-Application{

    param(

        $ApplicationName=$null

    )


    Function ParseJSON {

        param(
            [string]$JSONpath
        )

        Write-Log "SCRIPT: $ThisFileName | FUNCTION: $($MyInvocation.MyCommand.Name) | START" "INFO2"
        
        if (Test-Path $JSONpath) {Write-Log "Local JSON found. Attempting to get content." "INFO2"} else { Write-Log "Local JSON not found" "ERROR" "INFO2"; throw "Local JSON not found" }

        try {
            $jsonText = Get-Content -LiteralPath $JSONpath -Raw -Encoding UTF8
            $jsonData = $jsonText | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Log "ConvertFrom-Json failed: $($_.Exception.Message)" "ERROR"
            Throw $_
        }


        Write-Log ""

        # Can comment out
        # Write-Log "Here are all the applications we found from the JSON:"
        # Write-Log ""
        # $list = $jsonData.applications.ApplicationName 
        # Foreach ($item in $list) {
        #     Write-Log "$item"
        # }
        # Write-Log "" 

        Write-Log "SCRIPT: $ThisFileName | FUNCTION: $($MyInvocation.MyCommand.Name) | END" "INFO2"
        Write-Log "" "INFO2"

        return $jsonData

    }


    Write-Log "To begin we will access the ApplicationData.json files, both public (local repo) and private (Azure Blob) to show you the available applications."
    Write-Log ""

    Pause

    $TargetApp = Select-ApplicationFromJSON

    if ($TargetApp -eq $null) {
        Write-Log "No application selected. Exiting." "ERROR"
        Exit 1
    } else {
        $AppNameToFind = $TargetApp
        Write-Log "Application selected for installation: $AppNameToFind"
    }
    
    Write-Log "Installation of requested application will now commence..."
    Write-Log "" 

    Pause

    & $JSONAppInstaller_ScriptPath -TargetAppName $AppNameToFind

    Write-Log "" 

    if($LASTEXITCODE -ne 0){
        Write-Log "Install app script failed with exit code: $LASTEXITCODE" "ERROR"
        Exit $LASTEXITCODE
    } else {
        Write-Log "Application '$AppNameToFind' installed successfully!" "SUCCESS"
    }   

    


}

function Select-ApplicationFromJSON {

    Param (

        $AppNameToFind=$null
    )

    Write-Log "Parsing Public JSON" "INFO2"

    $PublicJSONdata = ParseJSON -JSONpath $PublicJSONpath
    $list1 = $PublicJSONdata.applications.ApplicationName


    # if ($list -contains $AppNameToFind) {

    #     Write-Log "Found $AppNameToFind in public JSON data." "INFO2"
    #     $AppData = $PublicJSONdata.applications | Where-Object { $_.ApplicationName -eq $AppNameToFind }

    #     Write-log "Application data for $AppNameToFind retrieved from JSON:" "INFO2"
    #     Write-Log ($AppData | ConvertTo-Json -Depth 10) "INFO2"

    # } else {

        ### If nothing found, attempt to search the  JSON...

        #Write-Log "Application $AppNameToFind not found in public JSON data." "INFO2"

        ### Download the private JSON file from Azure Blob Storage

        Write-Log "Now constructing URI for accessing private json..." "INFO2"
        

        $parts = $ApplicationDataJSONpath -split '/', 2

        $ApplicationData_JSON_ContainerName = $parts[0]      
        $ApplicationData_JSON_BlobName = $parts[1]

        #$ApplicationContainerSASkey
        $SasToken = $ApplicationContainerSASkey
        #$SasToken

        #pause

        Write-Log "Final values to be used to build ApplicationData.json URI:" "INFO2"
        Write-Log "StorageAccountName: $StorageAccountName" "INFO2"
        Write-Log "SasToken: $SasToken" "INFO2"
        Write-Log "ApplicationData_JSON_ContainerName: $ApplicationData_JSON_ContainerName" "INFO2"
        Write-Log "ApplicationData_JSON_BlobName: $ApplicationData_JSON_BlobName" "INFO2"
        $applicationJSONUri = "https://$StorageAccountName.blob.core.windows.net/$ApplicationData_JSON_ContainerName/$ApplicationData_JSON_BlobName"+"?"+"$SasToken"


        Write-Log "Attempting to access ApplicationData.json with this URI: $applicationJSONUri" "INFO2"

        Try{


            Write-Log "Beginning download..." "INFO2"
            & $DownloadAzureBlobSAS_ScriptPath -WorkingDirectory $WorkingDirectory -BlobName $ApplicationData_JSON_BlobName -StorageAccountName $StorageAccountName -ContainerName $ApplicationData_JSON_ContainerName -SasToken $SasToken
            if($LASTEXITCODE -ne 0){Throw $LASTEXITCODE }

            ### Ingest the private JSON data

            Write-Log "Parsing Private JSON" "INFO2"
            $PrivateJSONpath = "$WorkingDirectory\TEMP\Downloads\$ApplicationData_JSON_BlobName"
            $JSONpath = $PrivateJSONpath

            $PrivateJSONdata = ParseJSON -JSONpath $JSONpath
            $list2 = $PrivateJSONdata.applications.ApplicationName 

        }catch{

            Write-Log "SCRIPT: $ThisFileName | FUNCTION: $($MyInvocation.MyCommand.Name) | END | Accessing JSON from private share failed. Exit code returned: $_" "ERROR"
            Exit 1
            
        }

        ### Show everything that was found
        Write-Log ""
        Write-Log "----------------------------------------------------------------"
        Write-Log "" 
        Write-Log "Applications found from the public JSON:"
        Write-Log ""
        #$list = $jsonData.applications.ApplicationName 
        Foreach ($item in $list1) {
            Write-Log "$item"
        }
        Write-Log "" 
        Write-Log "----------------------------------------------------------------"
        Write-Log "" 
        Write-Log "Applications found from the private JSON:"
        Write-Log ""
        #$list = $jsonData.applications.ApplicationName 
        Foreach ($item in $list2) {
            Write-Log "$item"
        }
        Write-Log "" 
        Write-Log "----------------------------------------------------------------"
        Write-Log ""
        if ($AppNameToFind -ne $null) {

            Write-Log "Application name provided as parameter: $AppNameToFind"
        } else {
            Write-Log "Please enter the name of the application you wish to select for installation from the above lists. If you wish to exit this selection, type 'exit'." "WARNING"
            $AppNameToFind = Read-Host "Application Name"
            if ($AppNameToFind -eq 'exit') {
            Return $null
            }
        }

        While ([string]::IsNullOrWhiteSpace($AppNameToFind)) {
            Write-Log "No application name provided. Please enter an application name from the list above. If you wish to exit this selection, type 'exit'." "ERROR"
            $AppNameToFind = Read-Host "Application Name"

            if ($AppNameToFind -eq 'exit') {
                Return $null
            }

        }
        
        #Set $AppNameToFind to global variable for use in other functions
        $Global:AppNameToFind = $AppNameToFind

        ### Search for the target application in the private JSON data
        Write-Log "" 

        if ($list1 -contains $AppNameToFind) {

            Write-Log "Confirmed valid application name: $AppNameToFind"


            Write-Log "Found $AppNameToFind in public JSON data."
            $AppData = $PublicJSONdata.applications | Where-Object { $_.ApplicationName -eq $AppNameToFind }

            Write-log "Application data for $AppNameToFind retrieved from public JSON:" "INFO2"
            Write-Log ($AppData | ConvertTo-Json -Depth 10)

            # Record the needed data as variables for use in other functions
            # Convert the JSON values into local variables for access later
            Write-Log "Setting application data values as local variables..." "INFO2"
            foreach ($property in $AppData.PSObject.Properties) {

                $propName = $property.Name
                $propValue = $property.Value
                Set-Variable -Name $propName -Value $propValue -Scope Script
                Write-Log "Should be: $propName = $propValue" "INFO2"
                $targetValue = Get-Variable -Name $propName -Scope Script
                Write-Log "Ended up as: $propName = $($targetValue.Value)" "INFO2"

            }

            Return $AppNameToFind


        } elseif($list2 -contains $AppNameToFind){

            Write-Log "Confirmed valid application name: $AppNameToFind"


            Write-Log "Found $AppNameToFind in private JSON data."
            $AppData = $PrivateJSONdata.applications | Where-Object { $_.ApplicationName -eq $AppNameToFind }

            Write-log "Application data for $AppNameToFind retrieved from private JSON:" "INFO2"
            Write-Log ($AppData | ConvertTo-Json -Depth 10)

            # Record the needed data as variables for use in other functions
            # Convert the JSON values into local variables for access later
            Write-Log "Setting application data values as local variables..." "INFO2"
            foreach ($property in $AppData.PSObject.Properties) {

                $propName = $property.Name
                $propValue = $property.Value
                Set-Variable -Name $propName -Value $propValue -Scope Script
                Write-Log "Should be: $propName = $propValue" "INFO2"
                $targetValue = Get-Variable -Name $propName -Scope Script
                Write-Log "Ended up as: $propName = $($targetValue.Value)" "INFO2"

            }

            Return $AppNameToFind


        } else {

            Write-Log "Application $AppNameToFind not found in either public or private JSON data." "ERROR"
            Return $null

        }

}

function Set-VariablesFromObject {
    param(
        [Parameter(Mandatory, ValueFromPipeline)] $InputObject,
        #[string]$Prefix = 'Printer_',
        [ValidateSet('Local','Script','Global')] [string]$Scope = 'Local'
    )
    process {
        foreach ($p in $InputObject.PSObject.Properties) {
            # sanitize to a valid PowerShell variable name
            $name = $p.Name -replace '[^A-Za-z0-9_]', '_'
            if ($name -notmatch '^[A-Za-z_]') { $name = "_$name" }

            #$varName = "$Prefix$name"
            $VarName= $Name
            Set-Variable -Name $varName -Value $p.Value -Scope $Scope -Force
        }
    }
}

Function ParseJSON {

    param(
        [string]$JSONpath
    )

    Write-Log "SCRIPT: $ThisFileName | FUNCTION: $($MyInvocation.MyCommand.Name) | START" "INFO2"
    
    if (Test-Path $JSONpath) {Write-Log "Local JSON found. Attempting to get content." "INFO2"} else { Write-Log "Local JSON not found" "ERROR" "INFO2"; throw "Local JSON not found" }

    try {
        $jsonText = Get-Content -LiteralPath $JSONpath -Raw -Encoding UTF8
        $jsonData = $jsonText | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Log "ConvertFrom-Json failed: $($_.Exception.Message)" "ERROR"
        Throw $_
    }


    Write-Log "" "INFO2"

    # Can comment out
    # Write-Log "Here are all the applications we found from the JSON:"
    # Write-Log ""
    # $list = $jsonData.applications.ApplicationName 
    # Foreach ($item in $list) {
    #     Write-Log "$item"
    # }
    # Write-Log "" 

    Write-Log "SCRIPT: $ThisFileName | FUNCTION: $($MyInvocation.MyCommand.Name) | END" "INFO2"
    return $jsonData

}


##########
## MAIN ##
########## 

# Setup 


Write-Log "SCRIPT: $ThisFileName | START"
Write-Log ""
Write-Log "========================"
Write-Log "===== Set Up Asset ====="
Write-Log "========================"
Write-Log ""
Write-Log "Welcome! This script can:"
Write-Log " - Install a printer/app on your local machine"
Write-Log " - Guide and help automate the process of making a printer/app available for deployment via Azure/Intune."
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

$methods = Get-Command -CommandType Function -Name "*--*" | Select-Object -ExpandProperty Name

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


While ($SelectedFunctionNumber -lt 1 -or $SelectedFunctionNumber -ge $COUNTER) {
    Write-Log "No function selected. Please enter a function number from the list above:" "ERROR"
    [int]$SelectedFunctionNumber = Read-Host "Please enter a #"
}


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
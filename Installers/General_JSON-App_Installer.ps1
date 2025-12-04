# Install app from JSON

Param(

    $TargetAppName="Flameshot"

)

##########
## VARS ##
##########



$RepoRoot = (Split-Path -Path $PSScriptRoot -Parent)

$WorkingDirectory = Split-Path -Path $RepoRoot -Parent

#$LocalJSONpath = "$WorkingDirectory\TEMP\Downloads\ApplicationData.json"

$PublicJSONpath = "$RepoRoot\Templates\ApplicationData_TEMPLATE.json"

$ThisFileName = $MyInvocation.MyCommand.Name

$LogRoot = "$WorkingDirectory\Logs\Installer_Logs"

$LogPath = "$LogRoot\$ThisFileName.$TargetAppName._Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"


$OrgRegReader_ScriptPath = "$RepoRoot\Templates\OrganizationCustomRegistryValues-Reader_TEMPLATE.ps1"

$General_WinGet_Installer_ScriptPath = "$RepoRoot\Installers\General_WinGet_Installer.ps1"

$DownloadAzureBlobSAS_ScriptPath = "$RepoRoot\Downloaders\DownloadFrom-AzureBlob-SAS.ps1"

$MSIinstallScriptPath = "$RepoRoot\Installers\General_MSI_Installer.ps1"

###############
## FUNCTIONS ##
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

Function InstallApp-via-WinGet {

    Write-Log "Calling General_WinGet_Installer script to install $TargetAppName via WinGet..."

    if ($Version){

        & $General_WinGet_Installer_ScriptPath -AppName $TargetAppName -AppID $WinGetID -WorkingDirectory $WorkingDirectory -Version $Version

    } else {

        & $General_WinGet_Installer_ScriptPath -AppName $TargetAppName -AppID $WinGetID -WorkingDirectory $WorkingDirectory

    }

}

Function InstallApp-via-MSI-Private-AzureBlob {

    # Works

    # Download the custom MSI from Azure Blob Storage
    Write-Log "Downloading MSI from Private Azure Blob Storage..."


    $MSIPathFromContainerRoot

    $MSIname = Split-Path $MSIPathFromContainerRoot -Leaf

    # Grab organization custom registry values
    Try{
    # Grab organization custom registry values
        Write-Log "Retrieving organization custom registry values..." 
        $ReturnHash = & $OrgRegReader_ScriptPath #| Out-Null

        # Check the returned hashtable
        if(($ReturnHash -eq $null) -or ($ReturnHash.Count -eq 0)){
            Write-Log "No data returned from Organization Registry Reader script!" "ERROR"
            Exit 1
        }
        #Write-Log "Organization custom registry values retrieved:"
        foreach ($key in $ReturnHash.Keys) {
            $value = $ReturnHash[$key]
            Write-Log "   $key : $value" 
        }    

        # Turn the returned hashtable into variables
        Write-Log "Setting organization custom registry values as local variables..." 
        foreach ($key in $ReturnHash.Keys) {
            Set-Variable -Name $key -Value $ReturnHash[$key] -Scope Local
            Write-Log "Should be: $key = $($ReturnHash[$key])" 
            $targetValue = Get-Variable -Name $key -Scope Local
            Write-Log "Ended up as: $key = $($targetValue.Value)" 

        }
    } Catch {
        Write-Log "Error retrieving organization custom registry values: $_" "ERROR"
        Exit 1
    }

    # Construct blob URI

    $parts = $ApplicationDataJSONpath -split '/', 2

    $ApplicationData_JSON_ContainerName = $parts[0]      
    $ApplicationData_JSON_BlobName = $parts[1]

    $SasToken = $ApplicationContainerSASkey

    Write-Log "Final values to be used to build $MSIname URI:" 
    Write-Log "StorageAccountName: $StorageAccountName"
    Write-Log "SasToken: $SasToken"
    Write-Log "ApplicationData_JSON_ContainerName: $ApplicationData_JSON_ContainerName"
    Write-Log "ApplicationData_JSON_BlobName: $ApplicationData_JSON_BlobName"

    $applicationJSONUri = "https://$StorageAccountName.blob.core.windows.net/$ApplicationData_JSON_ContainerName/$MSIPathFromContainerRoot"+"?"+"$SasToken"

    Write-Log "Attempting to access ApplicationData.json with this URI: $applicationJSONUri"

    Try{


        Write-Log "Beginning download..."
        & $DownloadAzureBlobSAS_ScriptPath -WorkingDirectory $WorkingDirectory -BlobName $MSIPathFromContainerRoot -StorageAccountName $StorageAccountName -ContainerName $ApplicationData_JSON_ContainerName -SasToken $SasToken
        if($LASTEXITCODE -ne 0){Throw $LASTEXITCODE }


    }catch{

        Write-Log "Download MSI failed. Exit code returned: $_"
        Exit 1
        
    }

    # Install the MSI

    Write-Log "Calling General_MSI_Installer script to install $MSIname..."

    $MSIPath2 = $MSIPathFromContainerRoot.Replace('/', '\')

    if ($InstallArgs) {
        Write-Log "Using custom install arguments: $InstallArgs"
        & $MSIinstallScriptPath -MSIPath "$WorkingDirectory\TEMP\Downloads\$MSIPath2" -InstallArgs $InstallArgs -WorkingDirectory $WorkingDirectory -AppName $TargetAppName -DisplayName $DisplayName

    } else {
        & $MSIinstallScriptPath -MSIPath "$WorkingDirectory\TEMP\Downloads\$MSIPath2" -WorkingDirectory $WorkingDirectory -AppName $TargetAppName -DisplayName $DisplayName

    }



}

Function InstallApp-via-CustomScript-AzureBlob {

}

Function InstallApp-via-MSI-Online {

}

Function InstallApp-via-CustomScript {

    Write-Log "Calling custom installation script: $ScriptPathFromRepoRoot"

    $CustomScriptPath = "$RepoRoot\$ScriptPathFromRepoRoot"




    if ($CustomScriptArgs)
    {
        Write-Log "Passing script arguments: $CustomScriptArgs"
        #"$CustomScriptPath -WorkingDirectory ""$WorkingDirectory"" $CustomScriptArgsList"
        #& $CustomScriptPath -WorkingDirectory "$WorkingDirectory" $ParsedArgs


            
            # Construct the full command string
            # We use single quotes around the path to handle spaces safely
            $Command = "& '$CustomScriptPath' -WorkingDirectory '$WorkingDirectory' $CustomScriptArgs"
            
            Write-Log "Constructed command: $Command"

            # Execute the string as code
            Invoke-Expression $Command


    } else {

        & $CustomScriptPath -WorkingDirectory $WorkingDirectory

    }


}

Function ParseJSON {

    param(
        [string]$JSONpath
    )
    
    if (Test-Path $JSONpath) {Write-Log "Local JSON found. Attempting to get content."} else { Write-Log "Local JSON not found" "ERROR"; throw "Local JSON not found" }

    try {
        $jsonText = Get-Content -LiteralPath $JSONpath -Raw -Encoding UTF8
        $jsonData = $jsonText | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "ConvertFrom-Json failed: $($_.Exception.Message)"
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

    return $jsonData

}

##########
## MAIN ##
##########

# Ingest the registry data

Write-Log "SCRIPT: $ThisFileName | START"
Write-Log ""

Write-Log "Target Application to install: $TargetAppName"

Write-Log "================================="

Try{
# Grab organization custom registry values
    Write-Log "Retrieving organization custom registry values..."
    $ReturnHash = & $OrgRegReader_ScriptPath #| Out-Null

    # Check the returned hashtable
    if(($ReturnHash -eq $null) -or ($ReturnHash.Count -eq 0)){
        Write-Log "No data returned from Organization Registry Reader script!" "ERROR"
        Exit 1
    }
    #Write-Log "Organization custom registry values retrieved:"
    foreach ($key in $ReturnHash.Keys) {
        $value = $ReturnHash[$key]
        Write-Log "   $key : $value"
    }    

    # Turn the returned hashtable into variables
    Write-Log "Setting organization custom registry values as local variables..."
    foreach ($key in $ReturnHash.Keys) {
        Set-Variable -Name $key -Value $ReturnHash[$key] -Scope Local
        Write-Log "Should be: $key = $($ReturnHash[$key])"
        $targetValue = Get-Variable -Name $key -Scope Local
        Write-Log "Ended up as: $key = $($targetValue.Value)"

    }
} Catch {
    Write-Log "Error retrieving organization custom registry values: $_" "ERROR"
    Exit 1
}


Write-Log ""
Write-Log "================================="

### Ingest the public JSON data


Write-Log "Parsing Public JSON"
$PublicJSONdata = ParseJSON -JSONpath $PublicJSONpath

$list = $PublicJSONdata.applications.ApplicationName

    ### Search for the target application in the JSON data

    if ($list -contains $TargetAppName) {

        Write-Log "Found $TargetAppName in public JSON data."
        $AppData = $PublicJSONdata.applications | Where-Object { $_.ApplicationName -eq $TargetAppName }



        Write-log "Application data for $TargetAppName retrieved from public JSON:"
        Write-Log ($AppData | ConvertTo-Json -Depth 10)

    } else {

        ### If nothing found, attempt to search the private JSON...

        Write-Log "Application $TargetAppName not found in public JSON data." "WARNING"

        ### Download the private JSON file from Azure Blob Storage

        Write-Log "Now constructing URI for accessing private json..." 
        

        $parts = $ApplicationDataJSONpath -split '/', 2

        $ApplicationData_JSON_ContainerName = $parts[0]      
        $ApplicationData_JSON_BlobName = $parts[1]

$ApplicationContainerSASkey
        $SasToken = $ApplicationContainerSASkey
$SasToken
pause

        Write-Log "Final values to be used to build ApplicationData.json URI:"
        Write-Log "StorageAccountName: $StorageAccountName"
        Write-Log "SasToken: $SasToken"
        Write-Log "ApplicationData_JSON_ContainerName: $ApplicationData_JSON_ContainerName" 
        Write-Log "ApplicationData_JSON_BlobName: $ApplicationData_JSON_BlobName" 
        $applicationJSONUri = "https://$StorageAccountName.blob.core.windows.net/$ApplicationData_JSON_ContainerName/$ApplicationData_JSON_BlobName"+"?"+"$SasToken"


        Write-Log "Attempting to access ApplicationData.json with this URI: $applicationJSONUri"

        Try{


            Write-Log "Beginning download..."
            & $DownloadAzureBlobSAS_ScriptPath -WorkingDirectory $WorkingDirectory -BlobName $ApplicationData_JSON_BlobName -StorageAccountName $StorageAccountName -ContainerName $ApplicationData_JSON_ContainerName -SasToken $SasToken
            if($LASTEXITCODE -ne 0){Throw $LASTEXITCODE }


            ### Ingest the private JSON data

            Write-Log "Parsing JSON"
            #$LocalJSONpath = "$WorkingDirectory\TEMP\$ApplicationData_JSON_BlobName"
            $JSONpath = $LocalJSONpath

            $PrivateJSONdata = ParseJSON -JSONpath $JSONpath
            $list = $PrivateJSONdata.applications.ApplicationName 



        }catch{

            Write-Log "Accessing JSON from private share failed. Exit code returned: $_"
            Exit 1
            
        }
        
        ### Search for the target application in the private JSON data

        if ($list -contains $TargetAppName) {
            Write-Log "Found $TargetAppName in private JSON data."
            $AppData = $PrivateJSONdata.applications | Where-Object { $_.ApplicationName -eq $TargetAppName }

            Write-log "Application data for $TargetAppName retrieved from private JSON:"
            Write-Log ($AppData | ConvertTo-Json -Depth 10)
        } else {
            Write-Log "Application $TargetAppName not found in either public or private JSON data." "ERROR"
            Exit 1
        }

    }

### If the script makes it this far, attempt to begin installation

        # Convert the JSON values into local variables for easier access later
        Write-Log "Setting application data values as local variables..."
        foreach ($property in $AppData.PSObject.Properties) {
            $propName = $property.Name
            $propValue = $property.Value
            Set-Variable -Name $propName -Value $propValue -Scope Local
            Write-Log "Should be: $propName = $propValue"
            $targetValue = Get-Variable -Name $propName -Scope Local
            Write-Log "Ended up as: $propName = $($targetValue.Value)"
        }

### Determine installation method
Write-Log "Requested installation method: $InstallMethod"

if($InstallMethod -eq "WinGet"){

    Write-Log "Beginning installation via WinGet..."
    InstallApp-via-WinGet

} elseif ($InstallMethod -eq "MSI-Private-AzureBlob") {

    Write-Log "Beginning installation via MSI from Private Azure Blob..."
    InstallApp-via-MSI-Private-AzureBlob

} elseif ($InstallMethod -eq "MSI-Online") {

    Write-Log "Beginning installation via MSI from Online source..."
    InstallApp-via-MSI-Online

} elseif ($InstallMethod -eq "Custom_Script") {

    Write-Log "Beginning installation via Custom Script..."
    InstallApp-via-CustomScript

} else {

    Write-Log "Unknown installation method specified: $InstallMethod" "ERROR"
    Exit 1

}

# Check for success/fail
if($LASTEXITCODE -ne 0){
    Write-Log "Installation script failed with exit code $LASTEXITCODE" "ERROR"
    Exit $LASTEXITCODE
} else {
    Write-Log "Installation script completed successfully." "SUCCESS"
    Exit 0
}

### Determine install variables from JSON data


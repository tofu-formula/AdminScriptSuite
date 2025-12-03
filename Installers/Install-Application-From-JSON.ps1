# Install app from JSON

Param(

    $TargetAppName,

)

## VARS ##



$RepoRoot = Split-Path -Path $PSScriptRoot -Parent
$WorkingDirectory = Split-Path -Path $RepoRoot -Parent
$LocalJSONpath = "$WorkingDirectory\TEMP\ApplicationData.json"

$PublicJSONpath = "$RepoRoot\Templates\ApplicationData_TEMPLATE.json"

## FUNCTIONS ##

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

}

Function InstallApp-via-MSI-Private-AzureBlob {

}

Function InstallApp-via-MSI-Online {

}

Function InstallApp-via-CustomScript {

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

## MAIN ##

# Ingest the registry data

Write-Log "SCRIPT: $ThisFileName | START"
Write-Log ""

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

Write-Log "Target Application to install: $TargetAppName"

Write-Log "Parsing Public JSON"
$PublicJSONdata = ParseJSON -JSONpath $PublicJSONpath

$list = $PublicJSONdata.applications.ApplicationName

    ### Search for the target application in the JSON data

    if ($list -contains $TargetAppName) {
        Write-Log "Found $TargetAppName in private JSON data."
        $AppData = $PrivateJSONdata.applications | Where-Object { $_.ApplicationName -eq $TargetAppName }

        Write-log "Application data for $TargetAppName retrieved from private JSON:"
        Write-Log ($AppData | ConvertTo-Json -Depth 10)
    } else {

        ### If nothing found, attempt to search the private JSON...

        Write-Log "Application $TargetAppName not found in either public JSON data." "ERROR"

        ### Download the private JSON file from Azure Blob Storage

        Write-Log "Now constructing URI for accessing ApplicationData.json..." 
        

        $parts = $ApplicationDataJSONpath -split '/', 2

        $ApplicationData_JSON_ContainerName = $parts[0]      
        $ApplicationData_JSON_BlobName = $parts[1]


        $SasToken = $ApplicationDataContainerSASkey


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

            Write-Log "Accessing JSON failed. Exit code returned: $_"
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

### Determine installation method

### Determine install variables from JSON data

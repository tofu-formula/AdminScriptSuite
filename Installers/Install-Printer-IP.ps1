<#

Based on a script by Ben Whitmore

NOTES: 
# Download methods
# Install methods

supply just the name would be best

then the JSON tells the script what files are needed

OR

yes to the JSON
BUT
the script will download everything as a last resort instead of just individual files, perhaps as a lost resort


#>

[CmdletBinding()]
Param (


    [String]$PortName,


    [String]$PrinterIP,

    [Parameter(Mandatory = $True)]
    [String]$PrinterName,


    [String]$DriverName,


    [String]$INFFile,

    [string]$DriverZip, # Should contain the full path, equal to what's in the JSON

    [Parameter(Mandatory=$true)]
    [string]$WorkingDirectory, # Recommended param: "C:\ProgramData\COMPANY_NAME"


    # TODO: Add a switch for driver download method (Add Google Drive, maybe local file server, in the future)

    # Optional params to pass to DownloadFrom-AzureBlob-SAS.ps1

    #[Parameter(Mandatory=$true)]
    #[string]$BlobName,
    [string]$PrinterData_JSON_BlobName = "PrinterData.json",
    [string]$PrinterData_JSON_ContainerName = "printers",

    # Scenario A: Full URL supplied
    [string]$BlobSASurl,

    # Scenario B: Individual pieces of URL supplied
    [string]$StorageAccountName,
    #[string]$DriverZip_ContainerName, # Ex: "applications\7-zip" if file you are targetting is "applications\7-zip\7zip.exe"
    [string]$SasToken # Config tested: Signing method: Account key - Signing Key: key 1 - permissions: read - Allowed Protocols: HTTPS only


)

##########
## Vars ##
##########

$LogRoot = "$WorkingDirectory\Logs\Installer_Logs"
$ThisFileName = $MyInvocation.MyCommand.Name
$LogPath = "$LogRoot\$ThisFileName.$PrinterName._Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$RepoRoot = Split-Path -Path $PSScriptRoot -Parent

$DownloadAzureBlobSAS_ScriptPath = "$RepoRoot\Downloaders\DownloadFrom-AzureBlob-SAS.ps1"

$PrinterData_JSON_BlobName = "PrinterData.json"
$PrinterData_JSON_ContainerName = "printers"

###############
## Pre-Check ##
###############

# Reset Error catching variable
$Throwbad = $Null

# Run script in 64bit PowerShell to enumerate correct path for pnputil
If ($ENV:PROCESSOR_ARCHITEW6432 -eq "AMD64") {
    Try {
        &"$ENV:WINDIR\SysNative\WindowsPowershell\v1.0\PowerShell.exe" -File $PSCOMMANDPATH -PortName $PortName -PrinterIP $PrinterIP -DriverName $DriverName -PrinterName $PrinterName -INFFile $INFFile
    }
    Catch {
        Write-Error "Failed to start $PSCOMMANDPATH"
        Write-Warning "$($_.Exception.Message)"
        $Throwbad = $True
    }
}


###############
## Functions ##
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

##########
## Main ##
##########



Write-Log "##################################"
Write-Log "Installation started"
Write-Log "##################################"
Write-Log "Install Printer using the following values..."
Write-Log "Port Name: $PortName"
Write-Log "Printer IP: $PrinterIP"
Write-Log "Printer Name: $PrinterName"
Write-Log "Driver Name: $DriverName"
Write-Log "INF File: $INFFile"
Write-Log "DriverZip: $DriverZip"

Write-Log "##################################"

# TODO: Determine if SAS key was provided an if not, obtain from the registry 


# Determine if params were sufficient for PRINTER info or if Printer JSON is needed
$GetJSON = $False

Write-Log "Determining if enough printer data was supplied or if reaching out for the JSON is needed..."
if($PortName -ne "" -and $PortName -ne $null -and $PrinterIP -ne "" -and $PrinterIP -ne $null -and $DriverName -ne "" -and $DriverName -ne $null -and $INFFile -ne "" -and $INFFile -ne $null -and $DriverZip -ne "" -and $DriverZip -ne $null){

    Write-Log "Printer info confirmed present"
    
} else {

    Write-Log "Insufficient data, attempting to access JSON"
    $GetJSON = $True

}


if($GetJSON -eq $True) {

    # Scenario A: Get the JSON URI from the registry


    # Scenario B: Get JSON from Azure
    Write-Log "Determining URI for the PrinterData.json based on supplied params"
    if($StorageAccountName -ne "" -and $StorageAccountName -ne $null -and $SasToken -ne "" -and $SasToken -ne $null -and $PrinterData_JSON_ContainerName -ne "" -and $PrinterData_JSON_ContainerName -ne $null -and $PrinterData_JSON_BlobName -ne "" -and $PrinterData_JSON_BlobName -ne $null){

        $printerJSONUri = "https://$StorageAccountName.blob.core.windows.net/$PrinterData_JSON_ContainerName/$PrinterData_JSON_BlobName"+"?"+"$SasToken"

    } else {

        Write-Log "Insufficient params. Each of these cannot be empty:" "ERROR"
        Write-Log "StorageAccountName: $StorageAccountName"
        Write-Log "SasToken: $SasToken"
        Write-Log "PrinterData_JSON_ContainerName: $PrinterData_JSON_ContainerName"
        Write-Log "PrinterData_JSON_BlobName: $PrinterData_JSON_BlobName"
        Exit 1

    }


    Write-Log "Attempting to access PrinterData.json with this URI: $printerJSONUri"

    Try{

        # TODO: Try and create a snippet that can directly parse JSOn from web
        #$data = Invoke-RestMethod "$printerJSONUri"

        #$Result =Invoke-WebRequest -Uri $printerJSONUri -OutFile "$WorkingDirectory\temp\PrinterData.json" -UseBasicParsing

        Write-Log "Beginning download..."
        & $DownloadAzureBlobSAS_ScriptPath -WorkingDirectory $WorkingDirectory -BlobName $PrinterData_JSON_BlobName -StorageAccountName $StorageAccountName -ContainerName $PrinterData_JSON_ContainerName -SasToken $SasToken
        if($LASTEXITCODE -ne 0){Throw $LASTEXITCODE }

        Write-Log "Parsing JSON"
        $LocalJSONpath = "$WorkingDirectory\TEMP\$PrinterData_JSON_BlobName"
        if (Test-Path $LocalJSONpath) {Write-Log "Local JSON found"} else { Write-Log "Local JSON not found"}
        #$jsonData = Get-Content -Raw $LocalJSONpath | ConvertFrom-Json
        try {
            $jsonText = Get-Content -LiteralPath $LocalJSONpath -Raw -Encoding UTF8
            $jsonData = $jsonText | ConvertFrom-Json -ErrorAction Stop
        } catch {
            throw "ConvertFrom-Json failed: $($_.Exception.Message)"
        }

        # "Printers count: {0}" -f ($jsonData.printers.Count)
        # $jsonData.printers[0] | Format-List *

        # Can comment out
        Write-Log "Here are all the printers we found from the JSON:"
        $jsonData.printers.PrinterName


        Write-Log "This run as asking to install this printer: $PrinterName. Here is all the data on that printer:"
        $printer = $jsonData.printers | Where-Object { $_.PrinterName -eq $PrinterName }

        if ($printer) {
            
            # Write-Log "Formatted list:"
            # $printer | Format-List *

            # Write-Log "This is the IP address"
            # $printer.PrinterIP


            Write-Log "Attempting to digest data into PowerShell objects..."
            Set-VariablesFromObject -InputObject $printer -Scope Script

            Write-Log "These are the obtained values that are now PowerShell objects:"
            Write-Log "Port Name: $PortName"
            Write-Log "Printer IP: $PrinterIP"
            Write-Log "Printer Name: $PrinterName"
            Write-Log "Driver Name: $DriverName"
            Write-Log "INF File: $INFFile"
            Write-Log "DriverZip: $DriverZip"


        } else {
            Write-Log "Printer '$PrinterName' not found." "ERROR"
            Exit 1
        }
        # Store the result
        #$foundPrinter = $data.printers | Where-Object { $_.PrinterName -eq "Example-Printer-02" }


    }catch{

        Write-Log "Accessing JSON failed. Exit code returned: $_"
        Exit 1
        
    }


}



# Verify the data from the JSON is good and get the vars needed to invoke the download

#If ($DriverZip -ne "" -and $DriverZip -ne $null -and ($DriverZip_ContainerName -eq "" -or $DriverZip_ContainerName -eq $null)){
If ($DriverZip -ne "" -and $DriverZip -ne $null){

    Write-Log "Inferring the following:"


    $DriverZip_BlobName = Split-Path -Path $DriverZip -Leaf

    Write-Log "DriverZip_BlobName: $DriverZip_BlobName"

    $DriverZip_ContainerName  = Split-Path -Path $DriverZip -Parent # For some reason this converts / into \ and breaks things
    $DriverZip_ContainerName = ($DriverZip_ContainerName -replace '\\','/') -replace '(?<!:)/{2,}','/'

    Write-Log "DriverZip_ContainerName: $DriverZip_ContainerName"

    # if ($DriverZip_ContainerName -match "/" -or $DriverZip_ContainerName -match "\"){


    # } else {


    # }

} else {
    
    Write-Log "Format issue for DriverZip variable. It should be formatted like (DriverZip_ContainerName/Zip.zip). Current value: $DriverZip" "ERROR"
    Exit 1
}

# Download and extract the DriverZip

Try {

    Write-Log "Downloading the DriverZip"
    & $DownloadAzureBlobSAS_ScriptPath -WorkingDirectory $WorkingDirectory -BlobName $DriverZip_BlobName -StorageAccountName $StorageAccountName -ContainerName $DriverZip_ContainerName -SasToken $SasToken
    if($LASTEXITCODE -ne 0){Throw $LASTEXITCODE }

    $LocalDriverZipPath = "$WorkingDirectory\TEMP\$DriverZip_BlobName"
    $EXTRACTED_LocalDriverZipPath = "$LocalDriverZipPath-EXTRACTED"

    # Extract the zip

    Write-Log "Extracting the zip"
    if(Test-path $EXTRACTED_LocalDriverZipPath) {Write-Log "File already exists at $EXTRACTED_LocalDriverZipPath. Will attempt to overwrite." "WARNING"}

    Expand-Archive -Path "$LocalDriverZipPath" -DestinationPath "$EXTRACTED_LocalDriverZipPath" -Force -ErrorAction Stop

    Write-Log "Unzipping completee. Files live at $EXTRACTED_LocalDriverZipPath."
    #Pause


    # TODO: Identify the needed files from within the zip




} catch {


    Write-Log "Download/extract of DriverZip failed. Exit code returned: $_"

}




#Pause


<#
# Determine the BlobURI to be used to download the printer files. Currently only supports Azure Blob.

# Determine if this is scenario A or B



    $BlobName = $INFFile


    If($BlobSASurl -ne "" -and $BlobSASurl -ne $null){

        # Scenario A
        Write-Log "Scenario A: Full URL supplied"

        $BlobUri = $BlobSASurl


    } elseif ($StorageAccountName -ne "" -and $StorageAccountName -ne $null -and $ContainerName -ne "" -and $ContainerName -ne $null -and $SasToken -ne "" -and $SasToken -ne $null){

        # Scenario B
        Write-Log "Scenario B: Individual pieces of URL supplied"

        If ($ContainerPath -ne ""){

            $BlobUri = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$ContainerPath/$BlobName"+"?"+"$SasToken"

        } else {

            $BlobUri = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$BlobName"+"?"+"$SasToken"

        }



    

    } else {

        # Failed
        Write-Log "Not enough information supplied. Please make sure that you supplied enough/correct data." "ERROR"
        exit 1
        # Write-Log "Insufficient data, attempting to access JSON"
        # $GetJSON = $True

    }


Write-Log "Target URL: $BlobUri"

########################




# Download the INF file

& $DownloadAzureBlobSAS_ScriptPath -WorkingDirectory $WorkingDirectory -BlobSASurl $BlobUri -BlobName $INFFile
if ($LASTEXITCODE -ne 0){Write-Log "Could not download file. Please check Azure Blob Downloader script logs." "ERROR"; Exit 1}


$TargetDirectory = "$WorkingDirectory\TEMP"
$LocalDestinationPath = "$TargetDirectory\$INFFile"

# Test if download was successful
if ((Test-Path $LocalDestinationPath)){

    Write-Log "Confirmed INF file exists at specified location: $LocalDestinationPath" 

} else {

    Write-Log "Cannot find INF file at specified location: $LocalDestinationPath" "ERROR"
    Exit 1

}


$INFFilePath = $LocalDestinationPath


# Download/Read the JSON


#>
#############################

# Everything above here is working as intended in my limited test scenario

#############################


# $INFARGS = @(
#     "/add-driver"
#     "$INFFile"
# )


# $INFFile = "hpcu345u.inf"
# $DriverName = "HP Universal Printing PCL 6"

If (-not $ThrowBad) {

    Try {

        # Stage driver to driver store
        Write-Log "Staging Driver to Windows Driver Store using INF ""$($INFFile)"""
        #Write-Log "Running command: Start-Process pnputil.exe -ArgumentList $($INFARGS) -wait -passthru"
        #Push-Location $TargetDirectory
        #Push-Location $EXTRACTED_LocalDriverZipPath


        $INFpath = "$EXTRACTED_LocalDriverZipPath\$INFFile"

        # Check for the INF File
        If (Test-Path $INFpath){
            Write-Log "INF File found here: $EXTRACTED_LocalDriverZipPath"
        } else {
            Throw "INF File NOT found here: $EXTRACTED_LocalDriverZipPath"
        }

        #Start-Process pnputil.exe -ArgumentList $INFARGS -wait -passthru
        #pnputil /add-driver "`"$INFPath`"" /install #| Out-Null

        $result = pnputil /a $INFPath
        Foreach ($line in $result){Write-Log "pnputil.exe : $Line"}

        # Write-Log "Refining INF path..." # This may not be necessary but this is where I got it from: https://serverfault.com/questions/968120/unable-to-add-printer-driver-using-add-printerdriver-on-2012-r2-print-server

        # Write-Log "Old INFpath: $INFPath"

        # $INFPath = Get-WindowsDriver -All -Online | Where-Object {$_.OriginalFileName -like '*hpcu345u.inf'} | Select-Object -ExpandProperty OriginalFileName #-OutVariable infPath
        # Write-Log "New INFpath: $INFPath"
        
        #$INFPath
        # $yy = Get-Content -Path $infPath
        # Foreach ($line in $yy){Write-Log "$INFPath : $Line"}

        #Pause
        # $driver = Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue
        # if (-not $driver) {
        #     throw "Driver '$DriverName' still not found after installing INF. Check the exact model name inside the INF."
        # }

            # New method
                # Start-Process pnputil.exe -ArgumentList @("/add-driver", "`"$INFFilePath`"", "/subdirs", "/install") -Wait -PassThru

                # Write-Log "Checking if driver is staged"
                # pnputil /enum-drivers | Select-String -Pattern "DriverName" -ErrorAction SilentlyContinue

        #Pop-Location

    }
    Catch {
        Write-Log "Error staging driver to Driver Store" "ERROR"
        Write-Log "$($_.Exception.Message)" "ERROR"
        # Write-Log "Error staging driver to Driver Store" "ERROR"
        # Write-Log "$($_.Exception)" "ERROR"
        $ThrowBad = $True
    }
}


If (-not $ThrowBad) {
    Try {
    

        # Check if the required driver is already installed

        Write-Log "Checking if driver ($DriverName) is already installed"
        $DriverExist = Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue


        # Install driver

        if (-not $DriverExist) {
            Write-Log "Driver is not already installed."
            Write-Log "Adding Printer Driver: $DriverName"

            ###
            ###
            # Try { 


                #Add-PrinterDriver -Name $DriverName -Confirm:$false -ErrorAction Stop
                Write-Log "Running this command: Add-PrinterDriver -Name $DriverName -ErrorAction Stop"
                $Result = Add-PrinterDriver -Name $DriverName -ErrorAction Stop
                Foreach ($line in $result){Write-Log "Add-PrinterDriver : $Line"}

                    # New method
                        #Add-PrinterDriver -Name $DriverName -InfPath $INFFile -ErrorAction Stop


                
            # }Catch{
            #     "Uh oh stinky"
            #     $ThrowBad = $True
            #     Throw $_
            # }
        }
        else {
            Write-Log "Print Driver ""$($DriverName)"" already exists. Skipping driver installation." "WARNING"
        }
    }
    Catch {
        Write-Log "Error installing Printer Driver" "ERROR"
        Write-Log "$($_.Exception.Message)" "ERROR"
        Write-Log "Make sure the architecture of driver/machine matches!!!"
        # Write-Log "Error installing Printer Driver" "ERROR"
        # Write-Log "$($_.Exception)" "ERROR"
        $ThrowBad = $True
    }
}

If (-not $ThrowBad) {
    Try {

        # Create Printer Port
        $PortExist = Get-Printerport -Name $PortName -ErrorAction SilentlyContinue
        if (-not $PortExist) {
            Write-Log "Adding Port ""$($PortName)"""
            Add-PrinterPort -name $PortName -PrinterHostAddress $PrinterIP -Confirm:$false -ErrorAction Stop
        }
        else {
            Write-Log "Port ""$($PortName)"" already exists. Skipping Printer Port installation." "WARNING"
        }
    }
    Catch {
        Write-Log "Error creating Printer Port" "ERROR"
        Write-Log "$($_.Exception.Message)" "ERROR"
        # Write-Log "Error creating Printer Port" "ERROR"
        # Write-Log "$($_.Exception)" "ERROR"
        $ThrowBad = $True
    }
}

If (-not $ThrowBad) {
    Try {

        # Add Printer
        $PrinterExist = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
        if (-not $PrinterExist) {
            Write-Log "Adding Printer ""$($PrinterName)"""
            Add-Printer -Name $PrinterName -DriverName $DriverName -PortName $PortName -Confirm:$false -ErrorAction Stop
        }
        else {
            Write-Log "Printer ""$($PrinterName)"" already exists. Removing old printer..." "WARNING"
            Remove-Printer -Name $PrinterName -Confirm:$false -ErrorAction Stop
            Write-Log "Adding Printer ""$($PrinterName)"""
            Add-Printer -Name $PrinterName -DriverName $DriverName -PortName $PortName -Confirm:$false -ErrorAction Stop
        }

        $PrinterExist2 = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue
        if ($PrinterExist2) {
            Write-Log "Printer ""$($PrinterName)"" added successfully"
        }
        else {
            Write-Log "Error creating Printer" "ERROR"
            Write-Log "Printer ""$($PrinterName)"" error creating printer" "ERROR"
            $ThrowBad = $True
        }
    }
    Catch {
        Write-Log "Error creating Printer" "ERROR"
        Write-Log "$($_.Exception.Message)" "ERROR"
        # Write-Log "Error creating Printer" "ERROR"
        # Write-Log "$($_.Exception)" "ERROR"
        $ThrowBad = $True
    }
}

If ($ThrowBad) {
    Write-Log "An error was thrown during installation. Installation failed. Refer to the log file at ($LogPath) for details" "ERROR"
    Write-Log "Installation Failed" "ERROR"
    Exit 1
} else {

    Write-Log "Installation success!" "SUCCESS"
    Exit 0

}
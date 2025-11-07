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

    [Parameter(Mandatory=$true)]
    [string]$WorkingDirectory, # Recommended param: "C:\ProgramData\COMPANY_NAME"


    # TODO: Add a switch for driver download method (Add Google Drive, maybe local file server, in the future)

    # Optional params to pass to DownloadFrom-AzureBlob-SAS.ps1

    #[Parameter(Mandatory=$true)]
    [string]$BlobName,

    # Scenario A: Full URL supplied
    [string]$BlobSASurl,

    # Scenario B: Individual pieces of URL supplied
    [string]$StorageAccountName,
    [string]$ContainerName, # Include path! Ex: "applications\7-zip" if file you are targetting is "applications\7-zip\7zip.exe"
    [string]$SasToken # Config tested: Signing method: Account key - Signing Key: key 1 - permissions: read - Allowed Protocols: HTTPS only


)

##########
## Vars ##
##########

$LogRoot = "$WorkingDirectory\Logs\Git_Logs"
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

function Write-LogEntry {
    param (
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Value,
        [parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$FileName = "$($PrinterName).log",
        [switch]$Stamp
    )

    #Build Log File appending System Date/Time to output
    $LogFile = Join-Path -Path $env:SystemRoot -ChildPath $("Temp\$FileName")
    $Time = -join @((Get-Date -Format "HH:mm:ss.fff"), " ", (Get-WmiObject -Class Win32_TimeZone | Select-Object -ExpandProperty Bias))
    $Date = (Get-Date -Format "MM-dd-yyyy")

    If ($Stamp) {
        $LogText = "<$($Value)> <time=""$($Time)"" date=""$($Date)"">"
    }
    else {
        $LogText = "$($Value)"   
    }
	
    Try {
        Out-File -InputObject $LogText -Append -NoClobber -Encoding Default -FilePath $LogFile -ErrorAction Stop
    }
    Catch [System.Exception] {
        Write-Warning -Message "Unable to add log entry to $LogFile.log file. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
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
Write-Log "##################################"

# Determine if params were sufficient for PRINTER info or if a JSON is needed
$GetJSON = $False

Write-Log "Determining if enough printer data was supplied or if reaching out for the JSON is needed..."
if($PortName -ne "" -and $PortName -ne $null -and $PrinterIP -ne "" $PrinterIP -ne $null -and $DriverName -ne "" -and $DriverName -ne $null -and $INFFile -ne "" -and $INFFile -ne $null){

    Write-Log "Printer info confirmed present"
    

} else {

    Write-Log "Insufficient data, attempting to access JSON"
    $GetJSON = $True

}


# Determine the BlobURI to be used to download the printer files. Currently only supports Azure Blob.

# Determine if this is scenario A or B

Write-Log "Determining the BlobURI. Ascertaining if Scenario A or B was invoked based on supplied variables..."
$BlobName = $INFFile

If($BlobSASurl -ne "" -and $BlobSASurl -ne $null){

    # Scenario A
    Write-Log "Scenario A: Full URL supplied"

    $BlobUri = $BlobSASurl


} elseif ($StorageAccountName -ne "" -and $StorageAccountName -ne $null -and $ContainerName -ne "" -and $ContainerName -ne $null -and $SasToken -ne "" -and $SasToken -ne $null){

    # Scenario B
    Write-Log "Scenario B: Individual pieces of URL supplied"

    $BlobUri = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$BlobName"+"?"+"$SasToken"


   

} else {

    # Failed
    Write-Log "Not enough information supplied. Please make sure that you supplied enough/correct data." "ERROR"
    exit 1
    # Write-Log "Insufficient data, attempting to access JSON"
    # $GetJSON = $True

}


Write-Log "Target URL: $BlobUri"

###

# Get the JSON

 # Also create the URI for the JSON, or grab it from the registry

if($GetJSON -eq $True) {

    Try{

        $data = Invoke-RestMethod "https://azurebloblocation/thisfile.json"
        
        # Store the result
        $foundPrinter = $data.printers | Where-Object { $_.PrinterName -eq "Example-Printer-02" }

        # Access properties
        $foundPrinter.PrinterName  # Returns: "Example-Printer-02"
        $foundPrinter.PortName     # Returns: "IP_192.168.1.101"


    }catch{



    }


}


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



###


$INFARGS = @(
    "/add-driver"
    "$INFFile"
)

If (-not $ThrowBad) {

    Try {

        # Stage driver to driver store
        Write-Log "Staging Driver to Windows Driver Store using INF ""$($INFFile)"""
        #Write-Log "Running command: Start-Process pnputil.exe -ArgumentList $($INFARGS) -wait -passthru"
        Push-Location $TargetDirectory


        Start-Process pnputil.exe -ArgumentList $INFARGS -wait -passthru

            # New method
                # Start-Process pnputil.exe -ArgumentList @("/add-driver", "`"$INFFilePath`"", "/subdirs", "/install") -Wait -PassThru

                # Write-Log "Checking if driver is staged"
                # pnputil /enum-drivers | Select-String -Pattern "DriverName" -ErrorAction SilentlyContinue

        Pop-Location

    }
    Catch {
        Write-Log "Error staging driver to Driver Store" "ERROR"
        Write-Log "$($_.Exception.Message)" "ERROR"
        Write-Log "Error staging driver to Driver Store" "ERROR"
        Write-Log "$($_.Exception)" "ERROR"
        $ThrowBad = $True
    }
}

If (-not $ThrowBad) {
    Try {
    
        # Install driver
        $DriverExist = Get-PrinterDriver -Name $DriverName -ErrorAction SilentlyContinue
        if (-not $DriverExist) {
            Write-Log "Adding Printer Driver: $DriverName"
            # Try { 


                Add-PrinterDriver -Name $DriverName -Confirm:$false -ErrorAction Stop

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
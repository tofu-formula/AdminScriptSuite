<#

INSTRUCTIONS:
To run the script, you'll need to:
- run with administrator privileges 
- run directly on the print server.

This script will:
Get all TCP/IP printers from the print server
Collect detailed information about each printer's port and driver
Export the data to both a CSV file and display it in the console

#>

$ThisFileName = $MyInvocation.MyCommand.Name
$RepoRoot = (Split-Path $PSScriptRoot -Parent)
$WorkingDirectory = (Split-Path $RepoRoot -Parent)

if (!(Test-Path "$WorkingDirectory\TEMP")) {

    $WorkingDirectory = $PSScriptRoot
    
}

$PrintServerName = $ENV:computername
# $alreadyThere = $False


# Start 

#$PrintServerName = Read-host "Enter the print server you wish to connect to"

#$cred = Get-Credential -message "Enter the creds for connecting to PrinterServer: $PrintServerName"

Try {


    # $trustedHosts = Get-Item WSMan:\localhost\Client\TrustedHosts | Select-Object -ExpandProperty Value

    # if ($trustedHosts -match $PrintServerName) { 


    #     Write-Host "Looks like the PrintServer is already on your list of trusted hosts, going to skip adding to list"

    #     $alreadyThere = $True

    # } else {

    #     write-Host "PrintServer not found on TrustedHosts list, attempting to add."

    #     winrm set winrm/config/client @{TrustedHosts="$PrintServerName"}
    #     #Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value "$PrintServerName" -Concatenate -Force

    # }


    # $cim  = New-CimSession -ComputerName $PrintServerName -Credential $cred

    $printers = Get-Printer #-CimSession $cim

    $ExportPath = "$WorkingDirectory\TEMP\PrintServer_Exports\$PrintServerName.Export.$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    if(!(Test-Path $ExportPath)){new-item -ItemType File -Path $ExportPath -Force}

    # Get all printers from print server
    #$printers = Get-Printer -ComputerName "Davinci" #| Where-Object { $_.Type -eq "TCPIPPrinter" }

    # Create empty array to store results
    $results = @()

    foreach ($printer in $printers) {
        # Get printer port information
        $port = Get-PrinterPort -Name $printer.PortName
    
        # Get printer driver information
        $driver = Get-PrinterDriver -Name $printer.DriverName
    
        # Create custom object with required properties
        $printerInfo = [PSCustomObject]@{
            PortName = $printer.PortName
            PrinterIP = $port.PrinterHostAddress
            PrinterName = $printer.Name
            DriverName = $printer.DriverName
            INFFile = $driver.InfPath
        }
    
        # Add to results array
        $results += $printerInfo
    }

    # Export results to CSV file
    $results | Export-Csv -Path "$ExportPath" -NoTypeInformation
    write-Host "Exported results to CSV at $ExportPath"

    # Display results in console
    $results | Format-Table -AutoSize
} Catch {

    Write-Warning "Process failed: $_"

} Finally {

    # Clean up

    # if ($alreadyThere -eq $true){

    #     Write-Host "Attempting to remove the PrintServer from the TrustedHosts list"
    #     $trustedHosts = Get-Item WSMan:\localhost\Client\TrustedHosts | Select-Object -ExpandProperty Value
    #     $trustedHosts = $trustedHosts -split ',' | Where-Object { $_ -ne "$PrintServerName" }
    #     Set-Item WSMan:\localhost\Client\TrustedHosts -Value ($trustedHosts -join ',') -Force

    # }

    # Write-Host "Attempting to remove CIM session containing the creds you entered."
    # Remove-CimSession $cim


}



Write-Host "Finished"
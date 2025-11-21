# Detection-Script-Printer_TEMPLATE.ps1


Param(

    [string]$PrinterName,
    [string]$WorkingDirectory="C:\ProgramData\AdminScriptSuite"
)




##########
## VARS ##

$LogRoot = "$WorkingDirectory\Logs\Detection_Logs"
$ThisFileName = $MyInvocation.MyCommand.Name
$LogPath = "$LogRoot\$ThisFileName.$PrinterName._Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$RepoRoot = Split-Path -Path $PSScriptRoot -Parent

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

##########
## MAIN ##
##########

Write-Log "SCRIPT: $ThisFileName | START"

# Try modern method
Write-log "SCRIPT: $ThisFileName | Checking (using Get-Printer) for printer named: $PrinterName"
if(get-command -name Get-Printer -erroraction silentlyContinue){

    $Result = get-printer | where name -eq $PrinterName
    $result = $Result.name
    Write-Log "Result: $result"



} else {

    # Try old school method
    Write-Log "SCRIPT: $ThisFileName | Get-Printer cmdlet not found, falling back to CIM method for printer named: $PrinterName"
    $Result = Get-CIMInstance -classname Win32_Printer | Where-Object Name -EQ "Snake" -erroraction silentlyContinue
    #$result = $result | select-object "$PrinterName"
    $result = $Result.name
    Write-Log "Result: $result"
    

}


#Write-Log "SCRIPT: $ThisFileName | Result of search: $result"

If($result -eq $PrinterName){
    

    Write-Log "SCRIPT: $ThisFileName | END | Printer named: $PrinterName FOUND" "SUCCESS"
    #$Result | Format-List | Out-String | ForEach-Object { Write-Log "SCRIPT: $ThisFileName | Printer Property: $_" }
    Exit 0

} else {
    
    Write-Log "SCRIPT: $ThisFileName | END | Printer named: $PrinterName NOT FOUND" "WARNING"
    Exit 1

}   

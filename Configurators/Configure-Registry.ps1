# Windows Registry modifier

# WARNING: All three functions are tested and working so far, but, I HIGHLY recommend testing your use-case before deploying to enterprise


Param(

    [ValidateSet("Backup", "Modify", "Read","Read-All")]
    [string]$Function="Modify", # Backup, Modify, Read, or Read-All

    #[Parameter(Mandatory=$true)]
    [string]$KeyPath,

    #[Parameter(Mandatory=$true)]
    [string]$ValueName, # Change to ValueName
    
    [ValidateSet("String", "DWord", "QWord", "Binary", "MultiString", "ExpandString")]
    [string]$ValueType, # Change to ValueType

    [string]$Value, # Change to ValueData
    
    [Parameter(Mandatory=$true)]
    [string]$WorkingDirectory

    # [ValidateSet('Auto','Reg32','Reg64')]
    # [string]$RegistryView = 'Auto'

)

$ThisFileName = $MyInvocation.MyCommand.Name
$LogRoot = "$WorkingDirectory\Logs\Config_Logs"

$LogPath = "$LogRoot\$ThisFileName.$ValueName._Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

$BackupPath = "$WorkingDirectory\temp\Registry_Backups\RegBackup.$ValueName._$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"



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
        default   { Write-Host $logEntry }
    }
    
    # Ensure log directory exists
    $logDir = Split-Path $LogPath -Parent
    if (!(Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    Add-Content -Path $LogPath -Value $logEntry
}


# ============================================
# REGISTRY OPERATIONS
# ============================================



Function Reg-Read{
    param(

        [string]$registryPath = "$KeyPath",
        [string]$ValueName = "$ValueName"

    )

    Write-Log "Function: $($MyInvocation.MyCommand.Name) | Begin"


    # Check if the key exists
    if (Test-Path $registryPath) {

        Try {

            $ThisValue = Get-ItemProperty -Path $registryPath -Name $ValueName -ErrorAction SilentlyContinue
            $ReturnValue = $($ThisValue.$ValueName)
            Write-Log "Current value: $ReturnValue"
            Write-Log "Function: $($MyInvocation.MyCommand.Name) | End"

            Return $ReturnValue


        } catch {

            Write-Log "Could not read key: ($ValueName) at key path: ($registryPath)"
            Write-Log "Function: $($MyInvocation.MyCommand.Name) | End"

            Return "Could not read"

        }


    } else {

        Write-Log "KeyPath does not exist: $registryPath"
        Write-Log "Function: $($MyInvocation.MyCommand.Name) | End"
        Return "Could not read"

    }

}


Function Reg-Backup {

    Write-Log "Function: $($MyInvocation.MyCommand.Name) | Begin"

    # Ensure backup directory exists
    $backupDir = Split-Path -Parent $BackupPath
    Write-Log "Checking if backup file directory exists at $backupDir..."
    if (-not (Test-Path $backupDir)) { Write-Log "Directory not found. Creating..."; New-Item -ItemType Directory -Path $backupDir -Force | Out-Null } else {Write-Log "Path exists."}


    Write-Log "Backing registry value $KeyPath to $backupPath"
    Try {

            # Map of full hive names to abbreviations to fix for reg backups
            # $hiveMap = @{
            #     'HKLM:' = 'HKLM'
            #     'HKCU:' = 'HKCU'
            #     'HKU:'  = 'HKU'
            #     'HKCR:' = 'HKCR'
            #     'HKCC:' = 'HKCC'
            # }

            # $output = $KeyPath

            # foreach ($fullName in $hiveMap.Keys) {
            #     # Case-insensitive replacement of the full hive with its abbreviation
            #     $pattern = [regex]::Escape($fullName)
            #     $output  = $output -replace $pattern, $hiveMap[$fullName]
            # }


            # Convert HK??:\… -> HK??\… for reg.exe

        $RegExePath = $KeyPath `
        -replace '^HKLM:\\', 'HKLM\' `
        -replace '^HKCU:\\', 'HKCU\' `
        -replace '^HKCR:\\', 'HKCR\' `
        -replace '^HKU:\\',  'HKU\'  `
        -replace '^HKCC:\\', 'HKCC\'

        #$backupPath = "$env:TEMP\registry-backup.reg"

        # Run export with proper quoting; optionally pick registry view
        $RegViewSwitch = if ($env:PROCESSOR_ARCHITECTURE -eq 'x86') { '/reg:32' } else { '/reg:64' }
        $result = & reg.exe export "$RegExePath" "$BackupPath" /y $RegViewSwitch


        # $result = reg export "$output" $backupPath /y

        foreach ($line in $result){Write-Log "reg export: $_"}
        Write-Log "Registry backed up to: $backupPath"


        Write-Log "Checking if backup was successful..."

        if ((Test-Path $backupPath) -and ((Get-Item $backupPath).Length -gt 0)) {

            Write-Log "Backup file created successfully"
            Return $True

        } else {

            Throw "Backup file empty or nonexistant"

        }


    } catch {

        Write-Log "Could not do backup. Error code/message: $_"
        Exit 1

    }

}


function Reg-Modify {

    Write-Log "Function: $($MyInvocation.MyCommand.Name) | Begin"

    Write-Log "Attempting to modify key"

    try {

        # Create the key if it doesn't exist

        Write-Log "Checking if key exists at: $KeyPath"

        if (-not (Test-Path $KeyPath)) {
            Write-Log "Key does not exist. Attempting to create."
            New-Item -Path $KeyPath -Force | Out-Null
            Write-Log "Key created."
        }
        
        # Set the value
        Write-Log "Attempting to set the following:"
        Write-Log "KeyPath: $KeyPath"
        Write-Log "ValueName: $ValueName"
        Write-Log "Value: $Value"       
        Write-Log "Type: $ValueType"

        Set-ItemProperty -Path $KeyPath -Name $ValueName -Value $Value -Type $ValueType

        Write-Log "Successfully set $ValueName in $KeyPath" "SUCCESS"
        Write-Log "Function: $($MyInvocation.MyCommand.Name) | End"

        return $true
    }
    catch {
        Write-Log "Error: $($_.Exception.Message)" "ERROR"
        Write-Log "Function: $($MyInvocation.MyCommand.Name) | End"

        return $false
    }
}

function Get-RegistryTreeHashtable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    # Example of use from another script:
    <#
    Write-Host "Requesting read of all registry values under: $RegistryRoot`n"
    $RegData = & $RegEditScriptPath `
        -Function "Read-All" `
        -WorkingDirectory $WorkingDirectory `
        -KeyPath $RegistryRoot

    Write-Host "`nTesting access to specific registry values:"

    $RegData["HKLM:\Software\AdminScriptSuite-Test\Applications"]["ApplicationContainerSASkey"]
    #>

    # Master hashtable:
    #   Key   = registry key path (HKLM:\Software\...)
    #   Value = hashtable of value-name/value-data for that key
    $result = @{}

    # Resolve the root key and all child keys
    $keys = @()

    try {
        $rootKey = Get-Item -LiteralPath $Path -ErrorAction Stop
        $keys += $rootKey
    }
    catch {
        Write-Error "Could not open root key '$Path': $_"
        return $null
    }

    $keys += Get-ChildItem -LiteralPath $Path -Recurse -ErrorAction SilentlyContinue

    foreach ($key in $keys) {
        # $key is a Microsoft.Win32.RegistryKey
        try {
            $valueNames = $key.GetValueNames()
        }
        catch {
            # Some keys are protected / weird, just skip them
            Write-Log "Values not found for key: $key. Continuing anyways." "WARNING"
            continue
        }

        if (-not $valueNames -or $valueNames.Count -eq 0) { continue } else {

            Write-Log "Values not found for key: $key. Continuing anyways." "WARNING"
            Continue

        }

        $keyTable = @{}

        foreach ($name in $valueNames) {
            $value = $key.GetValue($name)
            $keyTable[$name] = $value
        }

        if ($keyTable.Count -eq 0) { continue }

        # Convert .Name (e.g. 'HKEY_LOCAL_MACHINE\SOFTWARE\AdminScriptSuite')
        # into a friendly PS-style path (HKLM:\SOFTWARE\AdminScriptSuite)
        $rawName = $key.Name
        $psPath  = switch -Regex ($rawName) {
            '^HKEY_LOCAL_MACHINE\\(.*)'    { "HKLM:\$($Matches[1])"; break }
            '^HKEY_CURRENT_USER\\(.*)'     { "HKCU:\$($Matches[1])"; break }
            '^HKEY_CLASSES_ROOT\\(.*)'     { "HKCR:\$($Matches[1])"; break }
            '^HKEY_USERS\\(.*)'            { "HKU:\$($Matches[1])"; break }
            '^HKEY_CURRENT_CONFIG\\(.*)'   { "HKCC:\$($Matches[1])"; break }
            default                        { $rawName }
        }

        # Normalize backslashes after the drive
        $psPath = $psPath -replace '\\', '\'

        $result[$psPath] = $keyTable
    }

    return $result

}

function Convert-RegistryRootToAbbrev {
    param(
        [Parameter(Mandatory)]
        [string]$InputString
    )

    # Map of full hive names to abbreviations
    $hiveMap = @{
        'HKEY_LOCAL_MACHINE' = 'HKLM:'
        'HKEY_CURRENT_USER'  = 'HKCU:'
        'HKEY_USERS'         = 'HKU:'
        'HKEY_CLASSES_ROOT'  = 'HKCR:'
        'HKEY_CURRENT_CONFIG'= 'HKCC:'
    }

    $output = $InputString

    foreach ($fullName in $hiveMap.Keys) {
        # Case-insensitive replacement of the full hive with its abbreviation
        $pattern = [regex]::Escape($fullName)
        $output  = $output -replace $pattern, $hiveMap[$fullName]
    }

    return $output
}


# ============================================
# COMMON REGISTRY PATHS
# ============================================

<#
HKEY_CLASSES_ROOT (HKCR:)  - File associations and COM registrations
HKEY_CURRENT_USER (HKCU:)  - Current user settings
HKEY_LOCAL_MACHINE (HKLM:) - System-wide settings (requires admin)
HKEY_USERS (HKU:)          - All user profiles
HKEY_CURRENT_CONFIG (HKCC:)- Hardware profile information

Common paths:
- HKCU:\Software - User application settings
- HKLM:\Software - System-wide application settings
- HKCU:\Control Panel - User control panel settings
- HKLM:\System\CurrentControlSet\Services - Windows services
- HKCU:\Environment - User environment variables
- HKLM:\System\CurrentControlSet\Control - System control settings
#>


##########
## MAIN ##
##########

## Pre-Check
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX PRE-CHECK for SCRIPT: $ThisFileName"
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX NOTE: PRE-CHECK is not logged"

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX ERROR: Administrator privileges required for registry modifications" -ForegroundColor Red
    Exit 1
}
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX Administrator check: PASSED"


Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX Checking if supplied paths have valid syntax"

# Test the paths syntax
$KeyPathsToValidate = @{
    'WorkingDirectory' = $WorkingDirectory
    'LogRoot' = $LogRoot
    'LogPath' = $LogPath
    'BackupPath' = $BackupPath
}
Test-PathSyntaxValidity -Paths $KeyPathsToValidate -ExitOnError

# Test the paths existance
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX Checking if supplied paths exist"
$KeyPathsToTest = @{
    'WorkingDirectory' = $WorkingDirectory
}
Foreach ($KeyPathToTest in $KeyPathsToTest.keys){ 

    $TargetPath = $KeyPathsToTest[$KeyPathToTest]

    if((test-path $TargetPath) -eq $false){
        Write-Host "ERROR: Required path $KeyPathToTest does not exist at $TargetPath" -ForegroundColor Red
        Exit 1
    }

}

Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX Checking if supplied ValueType is valid format"
Try {

    switch ($ValueType) {
    'DWord'    { if ($Value -notmatch '^\d+$') { Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX Value must be an integer for DWord. Attempting to convert." -ForegroundColor Yellow}; $Value = [int]$Value }
    'QWord'    { if ($Value -notmatch '^\d+$') { Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX Value must be an integer for QWord. Attempting to convert." -ForegroundColor Yellow}; $Value = [long]$Value }
    'MultiString' { if (-not ($Value -is [string[]])) { $Value = @($Value -split ';') } }
    'Binary'   { if (-not ($Value -is [byte[]])) { throw "Provide a byte[] for Binary" } }
    }
    Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX Check complete."

} catch {

    Write-Host "ERROR: Issue with ValueType: $_" -ForegroundColor Red
    Exit 1

}

# Can use this in the future for forcing to run 64-bit
# if (-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem) {
#     # Relaunch in 64-bit PowerShell
#     $sysnativePs = "$env:WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
#     & $sysnativePs -ExecutionPolicy Bypass -File $PSCommandPath @args
#     exit $LASTEXITCODE
# }


Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX Path validation successful - all exist"

# Replace reg loc with appropriate abbreviation
$KeyPath = Convert-RegistryRootToAbbrev -InputString $KeyPath

Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
Write-Log "===== Registry Configurator ====="
Write-Log "Function: $Function"
Write-Log "Targetted registry key:"
Write-Log "  KeyPath: $KeyPath"
Write-Log "  ValueName: $ValueName"
Write-Log "  Value: $Value"       
Write-Log "  Type: $ValueType"
Write-log "================================="

Write-Log "SCRIPT: $ThisFileName | START "



# addition checks that should be logged

if ($KeyPath -notmatch '^HK(LM|CU|CR|U|CC):\\') {
    Write-Log "SCRIPT: $ThisFileName | END | KeyPath must start with registry hive (HKLM:\, HKCU:\, etc.)" "ERROR"
    Exit 1
}

if ($function -ne "Read-All" -and [string]::IsNullOrWhiteSpace($KeyPath)) {
    Write-Log "SCRIPT: $ThisFileName | END | ValueName and KeyPath parameter is required unless Function is 'Read-All'" "ERROR"
    Exit 1
}

if ($Function -eq "Modify") {
    if ([string]::IsNullOrWhiteSpace($Value)) {
        Write-Log "SCRIPT: $ThisFileName | END | Value parameter is required when Function is 'Modify'" "ERROR"
        Exit 1
    }
    if ([string]::IsNullOrWhiteSpace($ValueType)) {
        Write-Log "SCRIPT: $ThisFileName | END | ValueType parameter is required when Function is 'Modify'" "ERROR"
        Exit 1
    }
}
# 
if ($function -eq "Read-All"){

    Write-Log "SCRIPT: $ThisFileName | Read-All function selected. Reading entire registry tree at $KeyPath"

    $RegData = Get-RegistryTreeHashtable -Path $KeyPath

    Write-Log = "SCRIPT: $ThisFileName | Registry tree read complete. Here are the found results:"

    # Check first if data is empty or invalid
    if((!$RegData) -or ($RegData.Count -eq 0)) {
        Write-Log "SCRIPT: $ThisFileName | END | No data returned from registry read!" "ERROR"
        return $null
    }

    $regData.GetEnumerator() | ForEach-Object {
        $keyPath = $_.Key
        $values  = $_.Value  # this is a hashtable

        Write-log "[$keyPath]"
        $values.GetEnumerator() | ForEach-Object {
            Write-Host "  $($_.Key) = $($_.Value)"
        }
    }

    Write-Log "SCRIPT: $ThisFileName | END | Returning registry tree hashtable to runner." "SUCCESS"

    Return $RegData

}


# Do a read (check)
Write-Log "---------------------------------"
Write-Log "SCRIPT: $ThisFileName | STEP 1: Read Registry Key"
Write-Log "---------------------------------"

$ReturnValue = Reg-Read
$NoFoundValue = $False

if ($ReturnValue -eq "Could not read"){

    Write-Log "SCRIPT: $ThisFileName | No returnable value at ($KeyPath\$ValueName). Check logs above for reason why." "WARNING"
    $NoFoundValue = $True

} else {

    Write-Log "SCRIPT: $ThisFileName | Current value of ($KeyPath\$ValueName) is: $ReturnValue"

}

#Write-Log "SCRIPT: $ThisFileName | "

if ($function -eq "Read"){

    if($ReturnValue -eq "Could not read"){

        Write-Log "SCRIPT: $ThisFileName | END | Returning ""Could not read"" to runner." "WARNING"
        return "Could not read"
    
    }else{
        
        Write-Log "SCRIPT: $ThisFileName | END | Returning value to runner." "SUCCESS"
        return $Returnvalue
    
    }

}

Write-Log "---------------------------------"


if ($function -eq "Modify" -or $function -eq "backup"){

    # Do a backup 
    Write-Log "---------------------------------"
    Write-Log "SCRIPT: $ThisFileName | STEP 2: Backup Registry Key"
    Write-Log "---------------------------------"
    if($NoFoundValue -eq $True){

        Write-Log "There was no found local value, so backup is being skipped." "WARNING"

    } else {

        Reg-Backup

    }

    Write-Log "---------------------------------"


    if ($function -eq "Modify"){

        if($ReturnValue -eq $Value){

            Write-Log "SCRIPT: $ThisFileName | END | Local registry key's value is already as desired." "SUCCESS"
            Exit 0

        } else {

            Write-Log "SCRIPT: $ThisFileName | Local registry key's value is not as desired. Now attempting modification of registry"

            # Do a modification
            Write-Log "---------------------------------"

            Write-Log "SCRIPT: $ThisFileName | STEP 3: Modify Local Registry Key"

            Write-Log "---------------------------------"

            Reg-Modify 

            Write-Log "---------------------------------"


            # Do a final read

            Write-Log "---------------------------------"
            Write-Log "SCRIPT: $ThisFileName | STEP 4: Final Check of Local Registry Key"
            Write-Log "---------------------------------"


            $FinalValue = Reg-Read

            Write-Log "---------------------------------"


            Write-Log "SCRIPT: $ThisFileName | Final local value of key $ValueName : $FinalValue"

            if($FinalValue -eq $Value){

                Write-Log "SCRIPT: $ThisFileName | END | Confirmed local registry value is now as desired." "SUCCESS"
                Exit 0

            }else{

                Write-Log "SCRIPT: $ThisFileName | END | Local registry value still not as expected." "ERROR"
                Exit 1

            }


        }

    } 

    Write-Log "SCRIPT: $ThisFileName | END | Backup complete" "SUCCESS"
    Exit 0

}


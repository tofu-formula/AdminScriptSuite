# General Uninstaller

# Example run
# General_uninstaller.ps1 -AppName "AdobeCC" -UninstallType "Remove-App-MSI-QN"

# TODO
<#

- add descriptions to each method
- install winget
- sometimes the command outputs are blank; remove if so?


#>

<#

Known working uninstall types

7-zip, Remove-App-EXE-S
Chrome, Remove-App-EXE-S





#>

Param(

    [Parameter(Mandatory=$true)]
    [String]$AppName,

    [Parameter(Mandatory=$true)]
    [String]$UninstallType,

    [Parameter(Mandatory=$true)]
    [String]$WorkingDirectory, # Recommended param: "C:\ProgramData\COMPANY_NAME"

    [Boolean]$VerboseLogs = $True,

    [Boolean]$SupremeErrorCatching = $True, 
    
    [int]$timeoutSeconds = 900 # Timeout in seconds (300 sec = 5 minutes)
)



############
### Vars ###
############

# Log folder location. Recommend not to change.
$LogRoot = "$WorkingDirectory\Logs\Uninstaller_Logs"

# Don't Change these
$SafeAppID = $AppName -replace '[^\w]', '_'
$LogPath = "$LogRoot\$SafeAppID.$UninstallType._MainUninstallLog_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$uninstallSuccess = $False



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

Function Extreme-ErrorCatchingRunner {

    param(
        [String]$UninstallCommand_App,
        [String]$UninstallCommand_Args,
        [String]$DetectMethod
    )

    Write-Log "-----------------------------------------"
    Write-Log "Sub-Function: Extreme-ErrorCatchingRunner | Begin | Summary: Now attempting to run uninstall command with extreme error catching."

    try { 

        $UnInstallationOutputLog = "$LogRoot\$SafeAppID.$UninstallType.UninstallationCommandOutputLog_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
        $UnInstallationErrorLog = "$LogRoot\$SafeAppID.$UninstallType.UnistallationCommandErrorLog_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

        # Configure process args, capture as object $proc

            $proc = Start-Process `
            -FilePath $UninstallCommand_App `
            -ArgumentList $UninstallCommand_Args `
            -WindowStyle Hidden `
            -PassThru `
            -RedirectStandardOutput "$UnInstallationOutputLog" `
            -RedirectStandardError "$UnInstallationErrorLog"

        # Default to view success as not successfully uninstalled yet
        $UnInstallSuccess = $false

        # Get the start time to determine low long to give process to run before timeout
        $startTime = Get-Date

        # Run the target process in the background ($proc runs when it gets evaluated as -not $proc.HasExited)...
        # While waiting for the process to exit...
        While (-not $proc.HasExited){ # Do...

            Start-Sleep -Seconds 10 # Wait 10 seconds
            $elapsed = (Get-Date) - $startTime # Check how much time is left
            Write-Log "Time elapsed: $elapsed / $TimeoutSeconds seconds" # Record to screen and log the time elapsed


            # If time has run out...
            if ($elapsed.TotalSeconds -ge $timeoutSeconds) {

                Write-Log "Timeout reached ($timeoutSeconds seconds) for Uninstallation. Killing process..." "WARNING"

                # Try killing the process...
                try {

                    $proc.Kill() # Attempt to kill process... (exits to the catch statement if it fails)
                    Write-Log "UnInstallation process killed due to timeout" "ERROR"

                } catch { # Catch the error if it fails to end the process...

                    Write-Log "Failed to kill process : $_" "ERROR" # Write and log the error
                }

                break # Break the loop once time runs out
                
            }

        }

        # After the $proc has ran out of time and the loops has been exited it is time to run some checks...

        # If the $proc has exited and $proc returned a success code...
        if ($proc.HasExited -and $proc.ExitCode -eq 0) {


            Write-Log "Process return success exit code" "INFO"
            

        }elseif(-not $proc.HasExited){
            
            
            Write-Log "Process still running after timeout, unexpected behavior" "ERROR"

        
        # If the process $proc is still running OR the exit code was not 0 (success code)
        } else {
            Write-Log "Uninstall process returned non-zero exit code ($($proc.ExitCode)) for $AppName" "WARNING" ## THIS IS WHERE THE EXIT CODE IS CAPTURED
            $UnInstallSuccess = $false
        }           

    
    } Catch {

        # If installation fails, return error
            
        Write-Log "Process Failed. Error: $_" "ERROR"
        $UnInstallSuccess = $false

    }


    # Final Check
    <#
    Write-Log "Attempting final check of application installation."

    $detect = App-Detector -AppName $AppName -DetectMethod $DetectMethod

    if ($detect -eq $false){

        Write-Log "Application not detected. Uninstall reported success." "SUCCESS"
        $UnInstallSuccess = $True

    } Else {

        Write-Log "Application  detected. Uninstall failed." "ERROR"
        $UnInstallSuccess = $False

    }
    #>

    
    Write-Log "Sub-Function: Extreme-ErrorCatchingRunner | End"
    Write-Log "-----------------------------------------"

    # Return true/false to the function call
    if ($UnInstallSuccess -eq $true){

        Return $True

    } Else {

        Return $False

    }

    # Write-Log "End of uninstall command function with superior logging."
    # Write-Log "-----------------------------------------"

}

Function Command-Runner {
    param(
        [String]$UninstallCommand_App,
        [String]$UninstallCommand_Args,
        [String]$DetectMethod
    )

    Write-Log "-----------------------------------------"
    Write-Log "Function: Command-Runner | Begin | Summary: Now attempting to run uninstall command."

    If($SupremeErrorCatching -eq $True){

        Write-Log "SupremeErrorCatching enabled. Using more complex logic."

        # Run the Extreme-ErrorCatchingRunner
        if ((Extreme-ErrorCatchingRunner -UninstallCommand_App $UninstallCommand_App -UninstallCommand_Args $UninstallCommand_Args -DetectMethod $DetectMethod) -eq $true){

            $UnInstallSuccess = $True

        } Else {

            $UnInstallSuccess = $False

        }


    } Else {


        # Run the regular uninstall command
        Try {

            $UninstallCommand = "$UninstallCommand_App $UninstallCommand_Args"
            Write-Log "Running this command: $UninstallCommand"

            & $UninstallCommand_App $UninstallCommand_Args

        } Catch {

            Write-Log "Command failed. Here is error message: $_" "ERROR"
            $uninstallSuccess = $False

        }

    }

    # After attempting uninstaller...

    Write-Log "Waiting for system to update..."
    # Registry cache refresh.  TODO: This may not work. Remove?
    [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Default).Close()
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    Start-Sleep -Seconds 10


    ## Final Check ##

    Write-Log "Function: Command-Runner | Attempting final check of application installation."
    <#
    $maxAttempts = 3
    $attemptCount = 0
    $detect = $true  # Assume it's there until proven otherwise

    while ($attemptCount -lt $maxAttempts -and $detect) {
        $attemptCount++
        Write-Log "Detection attempt $attemptCount of $maxAttempts"
        
        $detect = App-Detector -AppName $AppName -DetectMethod $DetectMethod
        
        if ($detect -and $attemptCount -lt $maxAttempts) {
            Write-Log "App still detected, waiting 2 seconds before retry..."
            Start-Sleep -Seconds 2
        }
    }
        #>

    
    # This part tries to detect if an uninstall string is still present in the registry
    $detect = App-Detector -AppName $AppName -DetectMethod $DetectMethod

    # If detection returns an object (for UninstallerString method), verify the uninstaller exists 
    if ($detect -and $DetectMethod -eq 'UninstallerString') {

        # Extract the uninstaller path (handle quoted and unquoted paths)
            $uninstallerPath = if ($detect.UninstallString -match '"([^"]+)"') {

                $matches[1]

        } else {

            $detect.UninstallString.Split(' ')[0]

        }
        
        if (-not (Test-Path $uninstallerPath)) {

            Write-Log "Ghost registry entry detected - uninstaller doesn't exist" "WARNING"
            $detect = $null  # Treat as not detected

        }

    }


    if ($detect -eq $false -or $detect -eq $null){
        Write-Log "Function: Command-Runner | Final Check: Application not detected. Uninstall reported success." "SUCCESS"
        $UnInstallSuccess = $True
    } Else {
        Write-Log "Function: Command-Runner | Final Check: Application detected. Uninstall failed." "ERROR"
        $UnInstallSuccess = $False
    }


    # Return true/false to the function call
    if ($UnInstallSuccess -eq $true){

        Write-Log "Function: Command-Runner | End | Final Result: Uninstall Success!" "SUCCESS"
        Write-Log "-----------------------------------------"
        Return $True

    } Else {

        Write-Log "Function: Command-Runner | End | Final Result: Result of uninstall command: Failure!" "ERROR"
        Write-Log "-----------------------------------------"
        Return $False

    }    


}

# Detection Checkers to add in the future?
Function App-Detector {
    Param (

        [String]$AppName,
        [String]$DetectMethod

    )

    Write-Log "-----------------------------------------"
    Write-Log "Function: App-Detector | Begin | Summary: Checking for App: $AppName using Method: $DetectMethod"


    # TODO: Convert to a switch?

    If ($DetectMethod -eq 'Win_Get'){

        Write-Log "Checking if WinGet is installed"
        if (!(Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Log "WinGet not found, beginning installation..."
            # Install and run the winget installer script
            # NOTE: This requires PowerShellGet module
            Try{

                Install-Script -Name winget-install -Force -Scope CurrentUser
                winget-install

            } Catch {

                Write-Log "Install of WinGet failed. Please investigate." "ERROR"
                return $false
            }
            
        } else {
            Write-Log "Winget is already installed"
        }


        $Detection = winget list --id "$AppName" --exact --accept-source-agreements| Out-String

        if ($Detection -match "$AppName") {
            #Write-Log "Installation detected of $ID"
            return $true
        } else {
            #Write-Log "Installation not detected of $ID"
            return $false
        }

    }

    If ($DetectMethod -eq 'UninstallerString'){
        $Detection = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall, 
                                        HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall -ErrorAction SilentlyContinue | 
                    Get-ItemProperty | 
                    Where-Object {$_.DisplayName -like "*$appName*"} | # Changed to use wildcard
                    Select-Object -Property DisplayName,UninstallString -First 1
        


        # Return the object directly for UninstallerString method
        return $Detection
    }    

    If ($DetectMethod -eq 'AppxPackage'){

        #Write-Log "Running detection"
        $Detection = Get-AppxPackage -AllUsers $appName

    }

    If ($DetectMethod -eq 'AppPackage'){

       $Detection = Get-AppPackage -AllUsers $appName

    }

    If ($DetectMethod -eq 'CIM'){

        $Detection = Get-CimInstance -ClassName Win32_Product | Where-Object { $_.Name -like "$Appname*"} | Select-object name

    }

    If ($DetectMethod -eq 'Uninstallertring2'){

        $Detection = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where {$_.DisplayName -like $appName} | Select UninstallString

    }

    # If ($DetectMethod -eq 'UninstallerString'){

    #     $Detection = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall | Get-ItemProperty | Where-Object {$_.DisplayName -eq $appName } | Select-Object -Property DisplayName,UninstallString

    # }

    # Run detection
    # NEED TO DO: check this verbose vs non-verbose

    # if ($VerboseLogs -eq $true){

    #     $Detection

    # } Else {

    #     If($Detection){
    #         return $True
    #     } else {
    #         return $False
    #     }

    # }
    


    If($Detection){

        Write-Log "Function: App-Detector | End | $AppName was detected" "WARNING"
        Write-Log "-----------------------------------------"

        return $Detection

    } else {

            Write-Log "Function: App-Detector | End | $AppName was not detected" "SUCCESS"
            Write-Log "-----------------------------------------"

            return $null

    }
}

Function Test-AllDetectionMethods {
    Param (
        [Parameter(Mandatory=$true)]
        [String]$AppName,
        [Switch]$IncludeCIM  # Optional flag since CIM is slow and problematic
    )
    
    #Write-Log "========================================="
    Write-Log "========================================="
    Write-Log "Function: Test-AllDetectionMethods | Begin | Summary: Testing ALL detection methods for: $AppName"
    #Write-Log "========================================="
    
    # Get all available detection methods from the switch statement
    $detectionMethods = @(
        'Win_Get',
        'AppxPackage', 
        'AppPackage',
        'UninstallString',
        'UninstallString2'
    )
    
    if ($VerboseLogs -eq $true){

        Write-Log "Available detection methods:"
        $detectionMethods | ForEach-Object { Write-Log "  - $_" "INFO" }
    }
    

    # Only include CIM if specifically requested
    #if ($IncludeCIM) {
        $detectionMethods += 'CIM'
        Write-Log "WARNING: Including CIM method - this may be slow and trigger repairs" "WARNING"
    #}
    
    $results = @{}
    
    foreach ($method in $detectionMethods) {
        Write-Log "Function: Test-AllDetectionMethods | Testing method: $method" "INFO"
        
        try {
            $detected = App-Detector -AppName $AppName -DetectMethod $method
            $results[$method] = $detected
            
            if ($detected) {
                Write-Log "Function: Test-AllDetectionMethods | $method : Application FOUND" "WARNING"
            } else {
                Write-Log "Function: Test-AllDetectionMethods | $method : Application NOT found" "SUCCESS"
            }
        }
        catch {
            Write-Log "Function: Test-AllDetectionMethods | $method : Method failed with error: $_" "ERROR"
            $results[$method] = "ERROR"
        }
    }
    
    # Summary
    #Write-Log "========================================="
    Write-Log "Function: Test-AllDetectionMethods | Detection Methods Summary for $AppName" "INFO"
    #Write-Log "========================================="
    
    $successfulMethods = @()
    $failedMethods = @()
    
    foreach ($method in $results.Keys) {
        if ($results[$method] -eq $true) {
            $successfulMethods += $method
        } elseif ($results[$method] -eq $false) {
            $failedMethods += $method
        }
    }
    
    if ($successfulMethods.Count -gt 0) {
        Write-Log "Function: Test-AllDetectionMethods | End | $AppName was detected. Methods that detected: $($successfulMethods -join ', ')" "WARNING"
        Write-Log "========================================="
        Return $True
    } else {

        Write-Log "Function: Test-AllDetectionMethods | End | No detections of $AppName" "SUCCESS"
        Write-Log "========================================="
        Return $False
    }
    
    # if ($failedMethods.Count -gt 0) {
    #     Write-Log "Methods that did NOT detect the app: $($failedMethods -join ', ')" "INFO"
    #     Write-Log "========================================="
    #     #Return

    # }
    


    #Write-Log "========================================="
    
    #return $results
}


################################
## Uninstall Method Functions ##
################################

Function Remove-App-MSI-QN([String]$appName)
{
    Write-Log "========================================="
    

    Write-Log "Function: $($MyInvocation.MyCommand.Name) | Begin"
    Write-Log "Target app: $appName"

    # Check for app
    $appCheck = App-Detector -AppName $AppName -DetectMethod 'UninstallerString'
    
    # If App was found...
    if($appCheck -ne $null){

        Write-Log "Function: $($MyInvocation.MyCommand.Name) | Application Detected. Now running uninstaller for: $($appCheck.DisplayName)" "WARNING"

        # Build uninstall string
        $uninst = $appCheck.UninstallString + " /qn /norestart"
        $UninstallCommand_App = "cmd" 
        $UninstallCommand_Args = "/c $uninst"

        # Run uninstaller
        if((Command-Runner -UninstallCommand_App $UninstallCommand_App -UninstallCommand_Args $UninstallCommand_Args -DetectMethod 'UninstallerString') -eq $true){

            Write-Log "Function: $($MyInvocation.MyCommand.Name) | Uninstall runner returned success!" "SUCCESS"
            $uninstallSuccess = $True

        } Else {

            Write-Log "Function: $($MyInvocation.MyCommand.Name) | Uninstall runner returned failure!" "ERROR"
            $uninstallSuccess = $False

        }
    } else {

        Write-Log "Function: $($MyInvocation.MyCommand.Name) | $appName is not installed on this computer!" "WARNING"

    }

    Write-Log "Function: $($MyInvocation.MyCommand.Name) | End"
    Write-Log "========================================="
    if ($uninstallSuccess -eq $True){

        Return $True

    } else {

        Return $False

    }
}

Function Remove-App-EXE-SILENT([String]$appName)
{

    Write-Log "========================================="

    Write-Log "Function: $($MyInvocation.MyCommand.Name) | Begin"
    Write-Log "Target app: $appName"

    # Check for app
    #$appCheck = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall | Get-ItemProperty | Where-Object {$_.DisplayName -eq $appName } | Select-Object -Property DisplayName,UninstallString
    $appCheck = App-Detector -AppName $AppName -DetectMethod 'UninstallerString'
    
    # If App was found...
    if($appCheck -ne $null){

        Write-Log "Function: $($MyInvocation.MyCommand.Name) | Application Detected. Now running uninstaller for: $($appCheck.DisplayName)" "WARNING"

        $uninst = $appCheck.UninstallString + " -silent"
        $UninstallCommand_App = "cmd" 
        $UninstallCommand_Args = "/c $uninst"
        

        # Run uninstaller
        if((Command-Runner -UninstallCommand_App $UninstallCommand_App -UninstallCommand_Args $UninstallCommand_Args -DetectMethod 'UninstallerString') -eq $true){

            Write-Log "Function: $($MyInvocation.MyCommand.Name) | Uninstall runner returned success!" "SUCCESS"
            $uninstallSuccess = $True

        } Else {

            Write-Log "Function: $($MyInvocation.MyCommand.Name) | Uninstall runner returned failure!" "ERROR"
            $uninstallSuccess = $False

        }

    } else {

        Write-Log "Function: $($MyInvocation.MyCommand.Name) | $appName is not installed on this computer!!" "WARNING"
    }


    Write-Log "Function: $($MyInvocation.MyCommand.Name) | End"
    Write-Log "========================================="
    if ($uninstallSuccess -eq $True){

        Return $True

    } else {

        Return $False

    }

}


Function Remove-App-CIM([string]$appName)
{
    # This method is like a last resort:
    <#
        When you query Win32_Product, Windows Installer performs a consistency check on ALL installed MSI products on the system, not just the ones you're targeting. This can:
            - Trigger repair operations on other products if Windows Installer detects any issues (missing files, registry keys, etc.)
            - Cause significant delays - it can take several minutes to enumerate all products
            - Generate event logs - you'll see entries in the Application event log for each product being verified
            - Potentially disrupt users - if a repair is triggered, users might see unexpected installer dialogs
    #>

    Write-Log "========================================="

    Write-Log "Function: $($MyInvocation.MyCommand.Name) | Begin"
    Write-Log "Target app: $appName"

    # Check for app
    #$appcheck = Get-CimInstance -ClassName Win32_Product | Where-Object { $_.Name -like "$Appname*"} | Select-object name
    $appCheck = App-Detector -AppName $AppName -DetectMethod 'CIM'

    # If App was found...
    if($appcheck -ne $null){

        Write-Log "Function: $($MyInvocation.MyCommand.Name) | Application Detected. Now running uninstaller for: $AppName" "WARNING"
        <#
        $uninst = {
            
            Get-CimInstance -ClassName Win32_Product | Where-Object {
                $_.Name -like "*$appName*"
            } | ForEach-Object {
                Invoke-CimMethod -InputObject $_ -MethodName Uninstall
            }

        }

        $UninstallCommand_App = "powershell.exe" 
        $UninstallCommand_Args = "-Command $uninst"
        #>

        $uninstCommand = "Get-CimInstance -ClassName Win32_Product | Where-Object { `$_.Name -like '*$appName*' } | ForEach-Object { Invoke-CimMethod -InputObject `$_ -MethodName Uninstall }"
    
        $UninstallCommand_App = "powershell.exe"
        $UninstallCommand_Args = "-Command `"$uninstCommand`""
        
        # Run uninstaller
        if((Command-Runner -UninstallCommand_App $UninstallCommand_App -UninstallCommand_Args $UninstallCommand_Args -DetectMethod 'CIM') -eq $true){
            Write-Log "Function: $($MyInvocation.MyCommand.Name) | Uninstall runner returned success!" "SUCCESS"
            $uninstallSuccess = $True
            
        } Else {
            Write-Log "Function: $($MyInvocation.MyCommand.Name) | Uninstall runner returned failure!" "ERROR"
            $uninstallSuccess = $False
            
        }


    }else{
        Write-Log "Function: $($MyInvocation.MyCommand.Name) | $appName is not installed on this computer!!!!!!!!!!" "WARNING"
    }


    Write-Log "Function: $($MyInvocation.MyCommand.Name) | End"
    Write-Log "========================================="
    if ($uninstallSuccess -eq $True){

        Return $True

    } else {

        Return $False

    }
    
}

Function Remove-App-EXE-S([String]$appName)
{
    Write-Log "========================================="
    Write-Log "Function: $($MyInvocation.MyCommand.Name) | Begin"
    Write-Log "Target app: $appName"

    # Check for app
    $appCheck = App-Detector -AppName $AppName -DetectMethod 'UninstallerString'
    
    # If App was found...
    if($appCheck -ne $null){
        Write-Log "Function: $($MyInvocation.MyCommand.Name) | Application Detected. Now running uninstaller for: $($appCheck.DisplayName)" "WARNING"

        # Build uninstall string with /S flag (capital S)
        $uninst = $appCheck.UninstallString + " /S"
        $UninstallCommand_App = "cmd" 
        $UninstallCommand_Args = "/c $uninst"

        # Run uninstaller
        if((Command-Runner -UninstallCommand_App $UninstallCommand_App -UninstallCommand_Args $UninstallCommand_Args -DetectMethod 'UninstallerString') -eq $true){
            Write-Log "Function: $($MyInvocation.MyCommand.Name) | Uninstall runner returned success!" "SUCCESS"
            $uninstallSuccess = $True
        } Else {
            Write-Log "Function: $($MyInvocation.MyCommand.Name) | Uninstall runner returned failure!" "ERROR"
            $uninstallSuccess = $False
        }
    } else {
        Write-Log "Function: $($MyInvocation.MyCommand.Name) | $appName is not installed on this computer!" "WARNING"
    }

    Write-Log "Function: $($MyInvocation.MyCommand.Name) | End"
    Write-Log "========================================="
    
    if ($uninstallSuccess -eq $True){
        Return $True
    } else {
        Return $False
    }
}

<#
Function Remove-App-MSI_EXE-Quiet([String]$appName)
{
    Write-Log "Now starting: $($MyInvocation.MyCommand.Name)"
    Write-Log "Target app: $appName"

    $appCheck = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall | Get-ItemProperty | Where-Object {$_.DisplayName -eq $appName } | Select-Object -Property DisplayName,UninstallString
    if($appCheck -ne $null){
        Write-Log "Uninstalling "$appCheck.DisplayName
        $uninst = $appCheck.UninstallString[1] +  " /qn /restart"
        cmd /c $uninst

    }
    else{
        Write-Log "$appName is not installed on this computer!!!" "WARNING"
    }
}

Function Remove-App-MSI_EXE-S([String]$appName)
{
    Write-Log "Now starting: $($MyInvocation.MyCommand.Name)"
    Write-Log "Target app: $appName"

    $appCheck = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall | Get-ItemProperty | Where-Object {$_.DisplayName -eq $appName } | Select-Object -Property DisplayName,UninstallString
    if($appCheck -ne $null){
        Write-Log "Uninstalling "$appCheck.DisplayName
        $uninst = $appCheck.UninstallString[1] +  " /S"
        cmd /c $uninst

    }
    else{
        Write-Log "$appName is not installed on this computer!!!!" "WARNING"
    }

    ""

}

Function Remove-App-MSI-I-QN([String]$appName)
{
    Write-Log "Now starting: $($MyInvocation.MyCommand.Name)"
    Write-Log "Target app: $appName"

    $appCheck = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall | Get-ItemProperty | Where-Object {$_.DisplayName -eq $appName } | Select-Object -Property DisplayName,UninstallString
    if($appCheck -ne $null){
        Write-Log "Uninstalling "$appCheck.DisplayName
        $uninst = $appCheck.UninstallString.Replace("/I","/X") + " /qn /norestart"
        cmd /c $uninst
    }
    else{
        Write-Log "$appName is not installed on this computer!!!!!" "WARNING"
    }

    ""

}


Function Remove-AppxPackage([String]$appName){
    Write-Log "Now starting: $($MyInvocation.MyCommand.Name)"
    Write-Log "Target app: $appName"

    $app = Get-AppxPackage -AllUsers $appName
    if($app -ne $null){
        $packageFullName = $app.PackageFullName
        Write-Log "Uninstalling $appName"
        Remove-AppxPackage -package $packageFullName -AllUsers
        $provApp = Get-AppxProvisionedPackage -Online 
        $proPackageFullName = (Get-AppxProvisionedPackage -Online | where {$_.Displayname -eq $appName}).DisplayName
        if($proPackageFillName -ne $null){
            Write-Log "Uninstalling provisioned $appName"
            Remove-AppxProvisionedPackage -online -packagename $proPackageFullName -AllUsers
        }
    }
    else{
        Write-Log "$appName is not installed on this computer!!!!!!" "WARNING"
    }

    ""

}

Function Remove-App-M365([String]$appName)
{
    Write-Log "Now starting: $($MyInvocation.MyCommand.Name)"
    Write-Log "Target app: $appName"
    
    $uninstall = (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where {$_.DisplayName -like $appName} | Select UninstallString)
    if($uninstall -ne $null){
        Write-Log "Uninstalling $appName"
        $uninstall = $uninstall.UninstallString + " DisplayLevel=False"
        cmd /c $uninstall
    }
    else{
        Write-Log "$appName is not installed on this computer!!!!!!!" "WARNING"
    }

    ""

}

Function Check-UninstallString([String]$appName)
{
    Write-Log "Now starting: $($MyInvocation.MyCommand.Name)"
    Write-Log "Target app: $appName"
    
    $appCheck = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall | Get-ItemProperty | Where-Object {$_.DisplayName -eq $appName } | Select-Object -Property DisplayName,UninstallString
    if($appCheck -ne $null){
        Write-Log $appCheck.DisplayName $appCheck.UninstallString
    }
    else{
        Write-Log "$appName is not installed on this computer!!!!!!!!" "WARNING"
    }

    ""

}

Function Remove-App-EXE-S-QUOTES([String]$appName)
{
    Write-Log "Now starting: $($MyInvocation.MyCommand.Name)"
    Write-Log "Target app: $appName"
    
    $appCheck = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall | Get-ItemProperty | Where-Object {$_.DisplayName -eq $appName } | Select-Object -Property DisplayName,UninstallString
    if($appCheck -ne $null){
        Write-Log "Uninstalling "$appCheck.DisplayName
        $uninst ="`""+$appCheck.UninstallString+"`"" + " /S"
        cmd /c $uninst
    }
    else{
        Write-Log "$appName is not installed on this computer!!!!!!!!!" "WARNING"
    }

    ""

}

# NEEDS TESTING
Function Remove-App-CIM([string]$appName)
{

    Write-Log "Now starting: $($MyInvocation.MyCommand.Name)"
    Write-Log "Target app: $appName"

    $appcheck = Get-CimInstance -ClassName Win32_Product | Where-Object { $_.Name -like "$Appname*"} | Select-object name
    if($appcheck -ne $null){
        Write-Log "Uninstalling $appName"
        Get-CimInstance -ClassName Win32_Product | Where-Object {
            $_.Name -like "*$appName*"
        } | ForEach-Object {
            Invoke-CimMethod -InputObject $_ -MethodName Uninstall
        }
    } 
    else{
        Write-Log "$appName is not installed on this computer!!!!!!!!!!" "WARNING"
    }

    ""
}

#>

#####################################################
## Uninstall Methods to test and add in the future ##
#####################################################

<#
function Remove-App-GetPackage {

    $package = Get-Package -Name "*$appName*" -Provider msi -ErrorAction SilentlyContinue
    if ($package) {
        $package | Uninstall-Package -Force
    }

}

function Remove-App-CIM3{

    # Less problematic, but not available on all systems
    Get-CimInstance -ClassName Win32_InstalledWin32Program | 
    Where-Object {$_.Name -like "*$appName*"}
}

#>

############
### MAIN ###
############

## Pre-Check
$ThisFileName = $MyInvocation.MyCommand.Name
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX PRE-CHECK for SCRIPT: $ThisFileName"
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX NOTE: PRE-CHECK is not logged"
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX Checking if supplied paths are valid"
# Test the paths
$pathsToValidate = @{
    'WorkingDirectory' = $WorkingDirectory
    'LogRoot' = $LogRoot
    'LogPath' = $LogPath
}
Test-PathSyntaxValidity -Paths $pathsToValidate -ExitOnError
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"



Write-Log "===== General Uninstallation Script ====="

Write-Log "TARGET APP: $AppName"
Write-Log "TARGET UNINSTALL METHOD: $UninstallType"
Write-Log "LOG PATH: $LogPath"
Write-Log "VERBOSE LOGGING ENABLED: $VerboseLogs"
Write-Log "SUPERIOR ERROR CATCHING LOGIC: $SupremeErrorCatching"

Write-Log "========================================="

## Function invoke

# List available uninstall functions
$methods = Get-Command -CommandType Function -Name "Remove-App*" | Select-Object -ExpandProperty Name


# If reporting is verbose, just spit out the available methods
if ($VerboseLogs -eq $True){

    Write-Log "Available uninstall methods:" "INFO"
    
    $methods | ForEach-Object { Write-Log "  - $_" "INFO" }

    Write-Log "You may also use -UninstallType 'All' to run through all these methods"
    Write-Log "========================================="

}

# Check for missing requirements
if ([string]::IsNullOrEmpty($AppName) -or [string]::IsNullOrEmpty($UninstallType)){

    Write-Log "SCRIPT: $ThisFileName | END | Missing required input parameters. Now exiting script." "ERROR"
    Exit 1

}

Write-Log "Now beginning work."

# Check if the function is legit first
if (Get-Command $UninstallType -ErrorAction SilentlyContinue) {

    Write-Log "Requested uninstall method found: $UninstallType"
    Write-Log "Attempting to call this method."
    $result = & $UninstallType -appName $AppName
    
    # Now run the uninstaller!!
    if ($result) {
        Write-Log "Uninstallation completed successfully using the called method ($UninstallType)" "SUCCESS"
        $uninstallSuccess = $True
    } else {
        Write-Log "Uninstallation failed using the called method ($UninstallType) failed" "ERROR"
        $uninstallSuccess = $False
    }

# If the method is set to 'All', run through all available methods...
} elseif ($UninstallType -eq 'All') {


    Write-Log "Attempting to do all uninstall methods." "WARNING"
    $successfulMethods = @()

    #$methods | ForEach-Object { Write-Log "  - $_" "INFO" }
    Foreach ($ChosenMethod in $Methods){

        Write-Log "Attempting to call uninstall method: $ChosenMethod"
        $result = & $ChosenMethod -appName $AppName

            if ($result) {
                Write-Log "Uninstallation completed successfully" "SUCCESS"
                $successfulMethods += $ChosenMethod
                $uninstallSuccess = $True

            } else {
                Write-Log "Uninstallation attempt with $ChosenMethod failed" "ERROR"
                
            }
        Write-Log "Moving to next method."
        Write-Log "========================================="


    }

    if ($successfulMethods.Count -gt 0) {
    Write-Log "Succeeded with methods: $($successfulMethods -join ', ')" "SUCCESS"
}

    Write-Log "End of available methods."
    Write-Log "========================================="


# If no matching methods...
} else {

    Write-Log "Unknown or undefined uninstall type: $UninstallType" "ERROR"
    # Write-Log "Available methods: Remove-App-MSI-QN" "INFO"

    Write-Log "Available uninstall methods:" "INFO"
    #$methods | ForEach-Object { Write-Log "  - $_" "INFO" }

    $methods | ForEach-Object { Write-Log "  - $_" "INFO" }

    Write-Log "========================================="

}



# Return final verdict with appropriate exit code]

# TODO: Return a final ultra check using all methods
Write-Log "Final check"
if((Test-AllDetectionMethods -AppName $AppName) -eq $True){

    Write-Log "Detect all method found the target app" "ERROR"
    $uninstallSuccess = $False

} else {

    Write-Log "Detect all method did NOT find the target app" "SUCCESS"
    
    If ($uninstallSuccess -eq $False){

        $NeverInstalled = $true

        $uninstallSuccess = $True

    }


}

Write-Log "========================================="


Write-Log "Final Verdict:"
If($uninstallSuccess -eq $True){

    if ($neverInstalled -eq $True){

        Write-Log "SCRIPT: $ThisFileName | END | $AppName was never installed to begin with! Returning success code!" "WARNING"

    } Else {

        Write-Log "SCRIPT: $ThisFileName | END | Uninstallation of $AppName successful!" "SUCCESS"

    }
    
    exit 0

} else {

    Write-Log "SCRIPT: $ThisFileName | END | Uninstallation of $AppName failed!" "ERROR"
    exit 1

}
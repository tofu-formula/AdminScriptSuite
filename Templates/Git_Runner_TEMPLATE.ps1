
<#

.SYNOPSIS
    Pull the latest commit from your target repo, and run a powershell script within, even passing parameters to that powershell script.

.DESCRIPTION
    This template...
        - can be used to pull the latest commit from your target repo, and run a powershell script within, even passing parameters to that powershell script.
        - was intended to be used as the primary component in this project: https://github.com/tofu-formula/AdminScriptSuite and interacts with the scripts within
        - can be ran as-is, or set up to be ran independently by removing the parameters.
        - will not be updated much so safe to keep and run. If used as a part of the github repo above, it can update itself.

    Why is it just a "template?"
        - Using with tools like InTune, Datto, Crowdstrike... etc that don't have direct GitHub integration may need to have a script uploaded
            - These tools may not play nice or at all with the script natively, and you may need to modify this script to accept the needed variables in a specific way, such as by environment variables, config files, or directly written to the script

    Can this script be ran as it?
        - Yes absolutely! It may not work for every scenario as explained above, but it can be ran with params to do whatever you want!

.PARAMETER RepoNickName
    Name to call the repo, for logging/local file path ($LocalRepoPath = "$WorkingDirectory\Git_Repos\$RepoNickName")
    EXAMPLE
        Win-AdminScriptSuite

.PARAMETER RepoUrl
    Link to the target repo
    EXAMPLE
        https://github.com/tofu-formula/AdminScriptSuite.git

.PARAMETER UpdateLocalRepoOnly
    If $true, forces script to exit early right after it finishes pulling the latest commit.
    NOTE: There is no need to inlcude "ScriptPath" args if this is $true

.PARAMETER ScriptPath
    Path from repo root to the target script
    EXAMPLE
        Uninstallers\General_Uninstaller.ps1

.PARAMETER WorkingDirectory
    Path to directory on the host machine that will be used to hold the repo and logs
    NOTE: Recommended path "C:\ProgramData\YourCompanyName"  - Useful because user does not have visibility to this unless they enable it
    NOTE: The directory will be created if it does not already exist
    NOTE: A seperate WorkingDirectory path will need to be provided in the params passed to the target script
    EXAMPLE
        C:\ProgramData\COMPANY_NAME

.PARAMETER ScriptParams
    Params to pass to the target script
    NOTE: You will need to check the target script's description to see what params are needed
    NOTE: Enclose in single brackets
    EXAMPLE 
        for General_Uninstaller.ps1: 
            '-AppName "7-zip" -UninstallType "All" -WorkingDirectory "C:\ProgramData\COMPANY_NAME"'


.EXAMPLE
    .\Git_Runner_TEMPLATE.ps1 -RepoNickName "Win-AdminScriptSuite" -RepoURL "https://github.com/tofu-formula/AdminScriptSuite.git" -ScriptPath "Uninstallers\General_Uninstaller.ps1" -WorkingDirectory "C:\ProgramData\COMPANY_NAME" -ScriptParams '-AppName "7-zip" -UninstallType "All" -WorkingDirectory "C:\ProgramData\COMPANY_NAME"'
    
    Template: .\Git_Runner_TEMPLATE.ps1 -RepoNickName "" -RepoURL "" -ScriptPath "" -WorkingDirectory "" -ScriptParams ""


.NOTES
    TODO:
        - Maybe add a timeout feature for the script?

    SOURCE:
        https://github.com/tofu-formula/AdminScriptSuite

#>


param(
    [Parameter(Mandatory=$true)]
    [string]$RepoNickName, # Name to call the local repo directory. Recommended name: REPO_(name of repo)

    [Parameter(Mandatory=$true)]
    [string]$RepoUrl,
    
    [boolean]$UpdateLocalRepoOnly, # If true, script exits early after just updating

    [string]$ScriptPath, # Path from repo root to the target script

    [Parameter(Mandatory=$true)]
    [string]$WorkingDirectory, # Recommended param: "C:\ProgramData\COMPANY_NAME"

    [Boolean]$forcemachinecontext,
    
    [Parameter(ValueFromRemainingArguments=$true)]
    $ScriptParams # Params to pass to the target script. Example for General_Uninstaller.ps1: -ScriptParams '-AppName "7-zip" -UninstallType "All" -WorkingDirectory "C:\ProgramData\COMPANY_NAME\Logs"'

)

##########
## Vars ##
##########

# Uncomment this part if you don't want to use params
# $RepoNickName = zz
# $RepoUrl = zz
# $UpdateLocalRepoOnly = zz
# $ScriptPath = zz
# $WorkingDirectory = zz
# $ScriptParams = zz

#$LocalRepoPath = "$WorkingDirectory\Git_Repos\$RepoNickName"
$LocalRepoPath = "$WorkingDirectory\$RepoNickName"
$LogRoot = "$WorkingDirectory\Logs\Git_Logs"
#$LogPath = "$LogRoot\$RepoNickName._Git_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$ThisFileName = $MyInvocation.MyCommand.Name

#$forcemachinecontext = $true

# Evaluate vars based on whether this run is just an update only
if(!($UpdateLocalRepoOnly -eq $true)) {
    
    $UpdateLocalRepoOnly = $False
    $LogPath = "$LogRoot\$RepoNickName._Git_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"


} else {

    $LogPath = "$LogRoot\Update_Local_Repo_Only._Git_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"


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

Function TestWinGet {

    Try {

        Write-Log "Current WinGet command: $WinGet"
        $whoami = [Environment]::UserName
        Write-Log "Current user: $whoami"
        Write-Log "Running test..."
        & $WinGet --info | out-null

        Write-Log "WinGet working at target destination."
        Return $True

    } catch {

        Write-Log "WinGet not working. Error: $_" "WARNING"
        Return "WinGet not working. Error: $_"

    }


}

Function Check-WinGet{

    #$NeedToInstallWinGet = $False


    # Determine if/where WinGet is 
    
    # Default path
    Write-Log "--- Checking if WinGet exists in PATH ---"
    Try {

        $winget = "winget.exe"
        $Test = TestWinGet
        if ($Test -ne $True){Throw $Test}


    } Catch {

        Write-Log "WinGet not accessible via path. Error: $_"
        # Write-Log "Assumed that it is not installed. Proceeding to install."
        # $NeedToInstallWinGet = $True
    }

    # Program Files location
    Write-Log "--- Checking if WinGet exists in Program Files location ---"
    $WinGetSystemFilesLocation = $Null
    $ProgramFilesLocationSuccess = $False
    Try {

            $resolveWingetPath = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*__8wekyb3d8bbwe"
            
            if ($resolveWingetPath) {
                $wingetPath = $resolveWingetPath[-1].Path
                $wingetPath = $wingetPath + "\winget.exe"
                Write-Log "Found WinGet path: $wingetPath"
                $winget = $wingetPath

                $Test = TestWinGet
                if ($Test -ne $True){Throw $Test} else {

                    Write-Log "WinGet is present and working in Program Files at: $winget"
                    $WinGetSystemFilesLocation = $Winget
                    $ProgramFilesLocationSuccess = $True

                }

            
            } else {

                Throw "Could not resolve WinGet path."

            }

    } Catch {

        Write-Log "WinGet at Program Files location could not be used. This could be because access to the path was denied. Return message: $_" "WARNING"

    }

    # AppData location
    Write-Log "--- Checking if WinGet exists in an AppData location ---"
    $AppDataLocationSuccess = $False
    $SuccessfulPaths = @()
    Try {

        # Paths to test
        $WinGetPaths = @(
            "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
            "$env:LOCALAPPDATA\Microsoft\WindowsApps\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\winget.exe"
        )

        ForEach ($WinGetPath in $WinGetPaths) {

            Write-Log "Testing WinGet path at: $WinGetPath"
            
            Try {

                if (Test-Path ($WinGetPath)) {

                    Write-Log "Confirmed WinGet exists at: $WinGetPath"
                    Write-Log "Now checking if this path is callable"

                    $WinGet = $WinGetPath
                    $Test = TestWinGet
                    if ($Test -ne $True){
                        
                        Throw "WinGet found at $WinGetPath but not working: $Test"
                    
                    } else {

                        Write-Log "Confirmed this path for WinGet is callable: $WinGetPath"
                        $SuccessfulPaths += $WinGetPath
                        $AppDataLocationSuccess = $True

                    }


                } else {

                    Throw "Could not find WinGet at $WinGetPath"
                }

            } Catch {

                Write-Log "Could not use path: $WinGetPath"
                Write-Log "Error received: $_"

            }



        }

        if ($SuccessfulPaths[0] -eq ""){

            Throw "No successful paths"

        } else {

            Write-Log "Here are our successful AppData paths for WinGet: $SuccessfulPaths"

        }
    } Catch {

        Write-Log "Could not resolve any AppData paths for WinGet. Error message: $_" "WARNING"

    }

    # Return failure if nothing works so far
    if ($AppDataLocationSuccess -eq $False -and $ProgramFilesLocationSuccess -eq $False){

        Write-Log "No Successful intances of WinGet found." "WARNING"
        Return "Failure"

    }

    #Determine if running in system or user context
    Write-Log "--- Checking if what context the script is being ran in ---"
    Try {
    
        if ($env:USERNAME -like "*$env:COMPUTERNAME*" -or $forcemachinecontext -eq $true) {
            Write-Log "Running in System Context"
            $Context = "Machine"

            # Use Program Files location
            $WinGet = $WinGetSystemFilesLocation


        } else {

            Write-Log "Running in User Context"
            $Context = "User"



            # Use AppData location
            $winget = $SuccessfulPaths[0] 

        }

        Write-Log "Final WinGet path: $WinGet"
        Write-Log "Running final check if winget works"
        # Final check?
        $Test = TestWinGet
        if ($Test -ne $True){ 


            return "Failure"

        } else {

            return $WinGet
        }

    } Catch {

        Write-Log "Could not get WinGet running in config for $context context. Error: $_" "WARNING"
        return "Failure"

    }

    

    # default
    #$winget = "winget.exe"



    ###
    # Write-Log "We are going to pretend that WinGet is not working for testing purposes." "WARNING"
    # $Result = $False
    ###

    # This snippet will attempt to have WinGet run as System. Currently can't fully test because a bunch of Microsoft services are offline (10/29/25)
    <#
    If ($result -ne $True){

        Try {

            Write-Log "Installing module: Invoke-CommandAs"
            Write-Log "Installing pre-reqs first."

            Write-Log "Installing NuGet"
            # 1) Install NuGet package provider silently if missing
            if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false
            } else { Write-Log "NuGet already present"}

            Write-Log "Trusting PowerShell Gallery"
            # 2) Trust the PowerShell Gallery to avoid the "Untrusted repository" prompt
            if ((Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue).InstallationPolicy -ne 'Trusted') {
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
            } else {Write-Log "PowerShell Gallery already trusted"}

            Write-Log "Installing module: Invoke-CommandAs"
            # 3) Install the module without prompts
            # Use -Scope CurrentUser if you don't have admin rights; otherwise AllUsers is fine.
            Install-Module -Name Invoke-CommandAs -Repository PSGallery -AcceptLicense -Force -Confirm:$false -Scope AllUsers


            Write-Log "Attempting to test if WinGet runs"
            Invoke-CommandAs -ScriptBlock { TestWinGet } -AsSystem

            if ($LASTEXITCODE -ne 0) { Throw $LASTEXITCODE}

        } Catch {

            Write-Log "Failed to use Invoke-CommandAs. Error: $_"


        }


        Pause

    }
    #>

    

}

Function CheckAndInstall-NuGet{

    Write-Log "Installing NuGet"
    # 1) Install NuGet package provider silently if missing
    if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false
    } else { Write-Log "NuGet already present"}

    Write-Log "Trusting PowerShell Gallery"
    # 2) Trust the PowerShell Gallery to avoid the "Untrusted repository" prompt
    if ((Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue).InstallationPolicy -ne 'Trusted') {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    } else {Write-Log "PowerShell Gallery already trusted"}

}

Function Install-WinGet {

    # Method 1
    Function Install-WinGet-1-AsherotoScript{

        # NOTE: In theory this shouldn't work. In practice it might.
        # METHOD: Asheroto installer script
        Write-Log "Function: $($MyInvocation.MyCommand.Name) | Begin"

        # Pre Reqs
        Write-Log "Running pre-reqs"
        CheckAndInstall-NuGet

        Try{

            Write-Log "Now installing WinGet via Asheroto script"
            Install-Script -Name winget-install -Force -Scope CurrentUser 2>&1
            # Refresh environment variables
            Start-Sleep 3
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            Start-Sleep 3
            #$result = 
            winget-install -force # More options to try: https://github.com/asheroto/winget-install
            #ForEach ($line in $result) { Write-Log "WINGET-INSTALL: $line" } #; if ($LASTEXITCODE -ne 0) {Write-Log "SCRIPT: $ThisFileName | END | Failed. Exit code: $LASTEXITCODE" "ERROR"; Exit 1 }

            Write-Log "WinGet installed successfully."

        } Catch {
            
            Write-Log "Provisioning failed: $_" "ERROR"
            throw "$_"

        }

        # Start-Sleep -Seconds 5
        # $winget = Get-WingetPath
    }

    # Method 2
    Function Install-WinGet-2-Offline-installer--Add-AppxProvisionedPackage-Online{
        # TODO: NEEDS TESTING
        # METHOD: Offline-installer--Add-AppxProvisionedPackage-Online 
        Write-Log "Function: $($MyInvocation.MyCommand.Name) | Begin"

        try {

            Write-Log "Attempting to provision App Installer (offline)..."
            $temp = join-path $WorkingDirectory "Temp\AppInstaller"
            #y$temp = Join-Path $env:TEMP "AppInstaller"
            $Temp
            Write-Log 'Attempting to do this: New-Item $temp @newItemSplat'
            New-Item -path $temp -ItemType "Directory" -Force
            Write-Log 'Attempting to do this: $bundle = Join-Path $temp "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"'
            $bundle = Join-Path $temp "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
            
            # Use official shortlink which redirects to the current App Installer bundle
            Write-Log 'Invoking web requesty'
            $url = "https://aka.ms/getwinget"
            Invoke-WebRequest -Uri $url -OutFile $bundle -UseBasicParsing

            Add-AppxProvisionedPackage -Online -PackagePath $bundle -SkipLicense | Out-Null
            Write-Log "Provisioned App Installer."

        } catch {

            #throw "Provisioning failed: $($_.Exception.Message)"
            Write-Log "Provisioning failed: $_" "ERROR"
            throw "$_"

        }

    }

    # Method 3
    Function Install-WinGet-3-AppXpackage-latestWingetMsixBundle{
    
        # TODO: NEEDS TESTING
        # AppXpackage from latestWingetMsixBundle. SOURCE: https://stackoverflow.com/questions/74166150/install-winget-by-the-command-line-powershell
        Write-Log "Function: $($MyInvocation.MyCommand.Name) | Begin"

        Try {
            $progressPreference = 'silentlyContinue'
            $latestWingetMsixBundleUri = $(Invoke-RestMethod https://api.github.com/repos/microsoft/winget-cli/releases/latest).assets.browser_download_url | Where-Object {$_.EndsWith(".msixbundle")}
            $latestWingetMsixBundle = $latestWingetMsixBundleUri.Split("/")[-1]
            Write-Information "Downloading winget to artifacts directory..."
            Invoke-WebRequest -Uri $latestWingetMsixBundleUri -OutFile "./$latestWingetMsixBundle"
            Invoke-WebRequest -Uri https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx -OutFile Microsoft.VCLibs.x64.14.00.Desktop.appx
            Add-AppxPackage Microsoft.VCLibs.x64.14.00.Desktop.appx
            Add-AppxPackage $latestWingetMsixBundle
        } Catch {

            Write-Log "Provisioning failed: $_" "ERROR"
            throw "$_"

        }
    }

    # Method 4
    Function Install-WinGet-4-OfficialMethod{

        # TODO: NEEDS TESTING
        # Use official MS Sandbox snippet (modified): https://learn.microsoft.com/en-us/windows/package-manager/winget/#install-winget
        Write-Log "Function: $($MyInvocation.MyCommand.Name) | Begin"
        
        # Pre Reqs?
        Write-Log "Running pre-reqs"
        CheckAndInstall-NuGet
        
        Try {
            
            $progressPreference = 'silentlyContinue'
            Write-Log "Installing WinGet PowerShell module from PSGallery..."
            # Install-PackageProvider -Name NuGet -Force | Out-Null
            Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery | Out-Null
            # Write-Host "Using Repair-WinGetPackageManager cmdlet to bootstrap WinGet..."
            # Repair-WinGetPackageManager -AllUsers
            # Write-Host "Done."
            
        } Catch {

            Write-Log "Provisioning failed: $_" "ERROR"
            throw "$_"

        }

    }

    ## Main Mini ##
    $InstallSuccess = $False
    $Counter = 0
    $MethodsToUse = @()
    $methods = Get-Command -CommandType Function -Name "Install-WinGet-*" | Select-Object -ExpandProperty Name
    $methods | ForEach-Object {$MethodsToUse+=$_}
    $max = $MethodsToUse.count
    $counterMax = $max - 1 
    # Run each method until success
    Do {

        $TargetMethod = $MethodsToUse[$Counter]


        Try {

            Write-Log "--- Now doing: $TargetMethod ---"
            & $TargetMethod

            Write-Log "Resolving path of WinGet"
            $WinGet = Check-WinGet

            Write-Log "Testing method: $TargetMethod"
            $result = Check-WinGet
            If ($result -eq $True) {
                $InstallSuccess -eq $True
            } else {
                Throw $Result
            }

        } Catch {

            Write-Log "Failed at install winget method: $TargetMethod with the following error: $_" "WARNING"

        }

        $Counter++

    } while ($InstallSuccess -eq $False -or $counter -ne $counterMax) finally {

        Write-Log "--- Install of WinGet reported success by using method: $TargetMethod"

    }


    If($InstallSuccess -eq $False){

        Write-Log "Could not install WinGet" "ERROR"
        Exit 1

    } 


    # Post-Install

        # Prep sources (first-run) and install packages
        Write-Log "Prepping WinGet source"
        $result = & $winget source reset --force | Out-String
        ForEach ($line in $result) { Write-Log "WINGET: $line" } #; if ($LASTEXITCODE -ne 0) {Write-Log "SCRIPT: $ThisFileName | END | Failed. Exit code: $LASTEXITCODE" "ERROR"; Exit 1 }
        $result = & $winget source update | Out-String
        ForEach ($line in $result) { Write-Log "WINGET: $line" } #; if ($LASTEXITCODE -ne 0) {Write-Log "SCRIPT: $ThisFileName | END | Failed. Exit code: $LASTEXITCODE" "ERROR"; Exit 1 }

    Write-Log "Install success"
    Return $WinGet

}

# Not in use
Function CheckAndInstall-WinGet-Portable {

    $wingetPath = "$WorkingDirectory\WinGet"
    $WinGet = "$wingetPath\winget.exe"
    $InstallWinGetPortable = $False

    # Run a check to see if any work needs to be down

    Function TestWinGetPortable {

        # Write-Log "Looking for WinGet portable at location: $Winget"

        # If(Test-Path $WinGet){

            # Write-Log "Winget.exe found. Now testing."

            Try {

                & $WinGet --info | out-null

                Write-Log "WinGet working at target destination."
                Return $True

            } catch {

                Write-Log "WinGet not working" "WARNING"
                Return "WinGet not working"

            }


        # } else {

        #         Write-Log "WinGet not found at target destination" "WARNING"
        #         Return "WinGet not found at target destination"

        # }


    }


    $InstallWinGetPortable = TestWinGetPortable

    if ($InstallWinGetPortable -ne $true){

        Try {



            if ($LASTEXITCODE -ne 0) { Throw $LASTEXITCODE}

            $WinGetFinalCheck = TestWinGetPortable

            If ($WinGetFinalCheck -eq $False){

                Write-Log "Could not install WinGet portable. " "ERROR"

            } else  {

                Throw "$WinGetFinalCheck"
            } 



        } Catch {

            Write-Log "Could not install WinGet portable. Error: $_" "ERROR"
            Exit 1

        }

        

    }

    Return $WinGet

}

# Not in use
Function CheckAndInstall-WinGet-OLD {

    Try {

        
        

        # 1) Ensure winget (App Installer) is provisioned for SYSTEM
        <#
        function Get-WingetPath {
            
            #$base = "${Env:ProgramFiles}\WindowsApps"

            # if (Test-Path $base) {
            #     $candidates = Get-ChildItem $base -Filter "Microsoft.DesktopAppInstaller_*x64__8wekyb3d8bbwe" -ErrorAction SilentlyContinue | Sort-Object Name -Descending
            #     foreach ($c in $candidates) {
            #     $p = Join-Path $c.FullName 'winget.exe'
            #     if (Test-Path $p) { return $p }
            #     }
            # }

            ## Got some ideas for this snippet from here, all rights to go original writer: https://github.com/SorenLundt/WinGet-Wrapper/blob/main/WinGet-Wrapper.ps1
            $resolveWingetPath = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*__8wekyb3d8bbwe"
            
            if ($resolveWingetPath) {
                $wingetPath = $resolveWingetPath[-1].Path
                $wingetPath = $wingetPath + "\winget.exe"
                Write-Log "WinGet path: $wingetPath"
                return $wingetPath

            
            } else {

                return $null

            }
            

        }
        #>

        Function TestWinGetOld{

            #Write-Log "Looking for WinGet portable at location: $Winget"

            #If(Test-Path $WinGet){

                Write-Log "Winget.exe found. Now testing."

                Try {

                    & $WinGet --info | out-null

                    Write-Log "WinGet working at target destination."
                    Return $True

                } catch {

                    Write-Log "WinGet not working" "WARNING"
                    Return "WinGet not working"

                }


            #} else {

                    #Write-Log "WinGet not found at target destination" "WARNING"
                    #Return "WinGet not found at target destination"

            #}


        }

        
        #Determine if running in system or user context
        if ($env:USERNAME -like "*$env:COMPUTERNAME*" -or $forcemachinecontext -eq $true) {
            Write-Log "Running in System Context"
            $Context = "Machine"

            $winget = Get-WingetPath


        }else {
            Write-Log "Running in User Context"
            $Context = "User"

            $winget = "winget.exe" 

            # Determine if winget is available to current script user
                $NeedToInstall = TestWinGet
                # If not, from here I have 2 options 
                if ($NeedToInstall -ne $True){

                    
                    # 1 - Create a profile for the current script user and install winget there
                    $TargetUser = whoami
                    Write-Log "Creating a Windows Profile for: $TargetUser"
                    Write-Log "Is that okay?"
                    Pause
                    runas /user:$TargetUserB "cmd /c echo Profile Created for $TargetUser"

                    # 2 - run every instance of WinGet from the Windows user not the script user



                }


        

        }

        ## end of snippet 


        ##

        #$winget = Get-WingetPath





        # NOTE: In theory this shouldn't work. In practice it might.
        # Install WinGet Method - from official installer script
        if (-not $winget){

            Write-Log "WinGet still not found. Attempting to use Install-Script."

            Try{

                Install-Script -Name winget-install -Force -Scope CurrentUser 2>&1
                $result = winget-install
                ForEach ($line in $result) { Write-Log "WINGET-INSTALL: $line" } #; if ($LASTEXITCODE -ne 0) {Write-Log "SCRIPT: $ThisFileName | END | Failed. Exit code: $LASTEXITCODE" "ERROR"; Exit 1 }

                Write-Log "WinGet installed successfully."

            } Catch {
                
                Write-Log "Provisioning failed: $_" "ERROR"
                throw "$_"

            }

            Start-Sleep -Seconds 5
            $winget = Get-WingetPath

        }

        # TODO: NEEDS TESTING
        # Install WinGet Method - with offline installer
        if (-not $winget) {

            Write-Log "Attempting to provision App Installer (offline)..."
            $temp = join-path $WorkingDirectory "Temp\AppInstaller"
            #y$temp = Join-Path $env:TEMP "AppInstaller"
            $Temp
            Write-Log 'Attempting to do this: New-Item $temp @newItemSplat'
            New-Item -path $temp -ItemType "Directory" -Force
            Write-Log 'Attempting to do this: $bundle = Join-Path $temp "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"'
            $bundle = Join-Path $temp "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
            
            # Use official shortlink which redirects to the current App Installer bundle
            Write-Log 'Invoking web requesty'
            $url = "https://aka.ms/getwinget"
            Invoke-WebRequest -Uri $url -OutFile $bundle -UseBasicParsing

            try {

                Add-AppxProvisionedPackage -Online -PackagePath $bundle -SkipLicense | Out-Null
                Write-Log "Provisioned App Installer."

            } catch {

                #throw "Provisioning failed: $($_.Exception.Message)"
                Write-Log "Provisioning failed: $_" "ERROR"
                throw "$_"


            }

            Start-Sleep -Seconds 5
            $winget = Get-WingetPath

        }

        if (-not $winget) { throw "winget.exe still not found after provisioning: $_" }
        
        Write-Log "Successfully resolved WinGet path. Using winget at: $winget"

        # 2) Prep sources (first-run) and install packages
        Write-Log "Prepping WinGet source"
        $result = & $winget source reset --force | Out-String
        ForEach ($line in $result) { Write-Log "WINGET: $line" } #; if ($LASTEXITCODE -ne 0) {Write-Log "SCRIPT: $ThisFileName | END | Failed. Exit code: $LASTEXITCODE" "ERROR"; Exit 1 }
        $result = & $winget source update | Out-String
        ForEach ($line in $result) { Write-Log "WINGET: $line" } #; if ($LASTEXITCODE -ne 0) {Write-Log "SCRIPT: $ThisFileName | END | Failed. Exit code: $LASTEXITCODE" "ERROR"; Exit 1 }

        Write-Log "Final WinGet path: $WinGet"
        Return $WinGet

    } Catch {

        Write-Log "SCRIPT: $ThisFileName| END | Install of WinGet failed. Please investigate. Return message: $_" "ERROR"
        Exit 1

    }

    

    # Old version
    <#
    if (!(Get-Command winget -ErrorAction SilentlyContinue)) {

        Write-Log "WinGet not found, beginning installation..."
        # Install and run the winget installer script
        # NOTE: This requires PowerShellGet module
        Try{

            Install-Script -Name winget-install -Force -Scope CurrentUser 2>&1
            $result = winget-install
            ForEach ($line in $result) { Write-Log "WINGET-INSTALL: $line" } #; if ($LASTEXITCODE -ne 0) {Write-Log "SCRIPT: $ThisFileName | END | Failed. Exit code: $LASTEXITCODE" "ERROR"; Exit 1 }

            Write-Log "WinGet installed successfully."

        } Catch {

            Write-Log "SCRIPT: $ThisFileName| END | Install of WinGet failed. Please investigate. Now exiting script." "ERROR"
            Exit 1
        }
        
    } else {
        Write-Log "Winget is already installed"
    }
    #>

}

function CheckAndInstall-Git {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Log "Git not found. Installing via winget..." "WARNING"
        
        try {

            $Result = & $winget install --id Git.Git -e --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 #| Out-String
            ForEach ($line in $result) { Write-Log "WINGET: $line" } 

            # Refresh environment variables
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            
            
            if ($LASTEXITCODE -ne 0) { throw "$LASTEXITCODE" }

            Write-Log "Git installed successfully!" "SUCCESS"
        }
        catch {
            Write-Log "SCRIPT: $ThisFileName | END | ERROR: Failed to install Git: $_" "ERROR"
            exit 1
        }
    }
    else {
        Write-Log "Git is already installed."
    }
}

Function Set-GitSafeDirectory {

    Write-Log "Configuring Git safe directory for: $LocalRepoPath"
    try {
        # Check if the directory is already in safe.directory list
        $safeDirectories = git config --global --get-all safe.directory 2>&1
        ForEach ($line in $safeDirectories) { Write-Log "GIT: $line" } #; if ($LASTEXITCODE -ne 0) {Write-Log "++++++++++++++++++++++"; Write-Log "SCRIPT: $ThisFileName | END | Failed" "ERROR"; Exit 1 }
        $normalizedRepoPath = $LocalRepoPath -replace '\\', '/'

        
        if ($safeDirectories -notcontains $LocalRepoPath -and $safeDirectories -notcontains $normalizedRepoPath) {
            Write-Log "Adding $LocalRepoPath to Git safe directories..."

            #git config --global --add safe.directory $normalizedRepoPath

            $GitOutput = git config --global --add safe.directory $normalizedRepoPath 2>&1
            ForEach ($line in $GitOutput) { Write-Log "GIT: $line" } #; if ($LASTEXITCODE -ne 0) {Write-Log "++++++++++++++++++++++"; Write-Log "SCRIPT: $ThisFileName | END | Failed" "ERROR"; Exit 1 }


            Write-Log "Successfully added to safe directories" "SUCCESS"


        } else {
            Write-Log "Repository already in safe directories"
        }
    } catch {
        Write-Log "Note: Could not configure safe directory (non-critical): $_" "WARNING"
    }

}

##########
## Main ##
##########

## Pre-Check

Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX PRE-CHECK for SCRIPT: $ThisFileName"
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX NOTE: PRE-CHECK is not logged"
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXX Checking if supplied paths are valid"
# Test the paths

if ($UpdateLocalRepoOnly -eq $True){

    $pathsToValidate = @{
        'WorkingDirectory' = $WorkingDirectory
        'LogRoot' = $LogRoot
        'LogPath' = $LogPath
        'LocalRepoPath' = $LocalRepoPath
    }

} else {

    $pathsToValidate = @{
        'WorkingDirectory' = $WorkingDirectory
        'LogRoot' = $LogRoot
        'LogPath' = $LogPath
        'ScriptPath' = $ScriptPath
        'LocalRepoPath' = $LocalRepoPath
    }

}
Test-PathSyntaxValidity -Paths $pathsToValidate -ExitOnError
Write-Host "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"



#####################
## Begin main body ##
#####################

Write-Log "+++++ Git Runner +++++"

Write-Log "RepoNickName: $RepoNickName"
Write-Log "RepoUrl: $RepoUrl"
Write-Log "ScriptPath: $ScriptPath"
Write-Log "WorkingDirectory: $WorkingDirectory"
Write-Log "ScriptParams: $ScriptParams"
Write-Log "UpdateLocalRepoOnly: $UpdateLocalRepoOnly"
Write-Log "++++++++++++++++++++++"

# Check if WinGet is installed
Write-Log "Checking if WinGet is installed"
$WinGet = Check-WinGet

# If check failed...
if ($WinGet -eq "Failure"){
    
    # ...Attempt to install WinGet...
    Write-Log "Failed to confirm WinGet in installed and working. Now proceeding to attempt installing WinGet." "WARNING"
    Install-WinGet
    $WinGet = Check-WinGet
    if ($WinGet -eq "Failure"){

        Write-Log "Failed to confirm WinGet is working after installation. Please investigate." "ERROR"
        Exit 1

    }

}


# Check if git is installed
Write-Log "Checking if Git is installed..."
CheckAndInstall-Git

# Add safe directory configuration
Set-GitSafeDirectory 

$DoClone = $False
Write-Log "Now checking if local repo exists..."
# Clone or update repository
if(Test-Path $LocalRepoPath){

    Write-Log "Local repository exists."
    Push-Location $LocalRepoPath

    if (!(Test-Path "$LocalRepoPath\.git"))
    {

        Write-Log "No .git folder. Attempting to add." "WARNING"


        # foreach ($line in $gitOutput) {
        #     Write-Log "GIT: $line"
        # }

        $gitOutput = git init -b main 2>&1
        ForEach ($line in $gitOutput) { Write-Log "GIT: $line" } ; if ($LASTEXITCODE -ne 0) {Write-Log "++++++++++++++++++++++"; Write-Log "SCRIPT: $ThisFileName | END | Failed" "ERROR"; Exit 1 }
        
        $gitOutput = git remote add origin $RepoURL 2>&1
        ForEach ($line in $gitOutput) { Write-Log "GIT: $line" } ; if ($LASTEXITCODE -ne 0) {Write-Log "++++++++++++++++++++++"; Write-Log "SCRIPT: $ThisFileName | END | Failed" "ERROR"; Exit 1 }
        
        $gitOutput = git fetch origin 2>&1
        ForEach ($line in $gitOutput) { Write-Log "GIT: $line" } ; if ($LASTEXITCODE -ne 0) {Write-Log "++++++++++++++++++++++"; Write-Log "SCRIPT: $ThisFileName | END | Failed" "ERROR"; Exit 1 }
        
        $gitOutput = git reset --hard origin/main 2>&1
        ForEach ($line in $gitOutput) { Write-Log "GIT: $line" } ; if ($LASTEXITCODE -ne 0) {Write-Log "++++++++++++++++++++++"; Write-Log "SCRIPT: $ThisFileName | END | Failed" "ERROR"; Exit 1 }
        
        $gitOutput = git branch --set-upstream-to=origin/main main 2>&1
        ForEach ($line in $gitOutput) { Write-Log "GIT: $line" } ; if ($LASTEXITCODE -ne 0) {Write-Log "++++++++++++++++++++++"; Write-Log "SCRIPT: $ThisFileName | END | Failed" "ERROR"; Exit 1 }
    
       
        if (Test-Path "$LocalRepoPath\.git"){

            Write-Log ".git folder added" "SUCCESS"

        } else {
            Write-Log "++++++++++++++++++++++"
            Write-Log "SCRIPT: $ThisFileName | END | Could not add .git folder" "ERROR"
            Exit 1
        }

    }
   
    Write-Log "Pulling latest changes..."
    try {
        $gitOutput = git pull 2>&1
        foreach ($line in $gitOutput) {
            Write-Log "GIT: $line"
        }
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "++++++++++++++++++++++"
            Write-Log "SCRIPT: $ThisFileName | END | Failed at: git pull." "ERROR"
            Exit 1            
        } else {
            Write-Log "Successfully pulled latest changes" "SUCCESS"
        }
    }
    finally {
        Pop-Location
    }
} else {
    $DoClone = $True
}

if ($DoClone -eq $true){

    Write-Log "No local repo yet. Cloning repository..."
    $gitOutput = git clone $RepoUrl $LocalRepoPath 2>&1
    foreach ($line in $gitOutput) {
        Write-Log "GIT: $line"
    }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "SCRIPT: $ThisFileName | END | Failed to clone repository" "ERROR"
        exit 1
    } else {
        Write-Log "Successfully cloned repository" "SUCCESS"
    }
    
    Exit 1
}

# Exit script if this was update only
if($UpdateLocalRepoOnly -eq $true) {

    Write-Log "++++++++++++++++++++++"
    Write-Log "SCRIPT: $ThisFileName | END | Repo: $RepoNickName | Update local repo only completed." "SUCCESS"
    Exit 0

}


# Build full script path
$FullScriptPath = Join-Path $LocalRepoPath $ScriptPath

# Check if script exists
if (-not (Test-Path $FullScriptPath)) {
    Write-Log "SCRIPT: $ThisFileName | END | Script not found: $FullScriptPath" "ERROR"
    Exit 1
}

# Run the script with parameters
Write-Log "Running script: $ScriptPath"
Write-Log "With parameters: $ScriptParams"

try {
    if ($ScriptParams) {
        $command = "& `"$FullScriptPath`" $ScriptParams"
        Invoke-Expression $command
    }
    else {
        & $FullScriptPath
    }

    if ($LASTEXITCODE -ne 0) { throw "$LASTEXITCODE" }

}
catch {
    Write-Log "SCRIPT: $ThisFileName | END | Failed to execute script: $_" "ERROR"
    Exit 1
}


Write-Log "++++++++++++++++++++++"
Write-Log "SCRIPT: $ThisFileName | END | Repo: $RepoNickName | Script: $ScriptPath | Execution completed." "SUCCESS"
Exit 0
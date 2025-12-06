# Security Manager

# This guy is gonna be referenced from the Git Runner. Every time Git Runner does something there will be a security check.
# It should be called after the Git Runner does a pull but before it runs any scripts.
# It should be ran a second time after the scripts are ran to make sure nothing sketchy happened.
# The registry portion may need to be carried out by the registry manager script
# May want to consider logging turn off for performance reasons, otherwise this will eat up a lot of space on all of our end machines.

# Security manager can be modified in the future to perform other actions, such as checking for specfic certs
$WorkingDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$ThisFileName = $MyInvocation.MyCommand.Name
$LogRoot = "$WorkingDir\Logs\Security_Logs"
$LogPath = "$LogRoot\$ThisFileName._Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$RepoRoot = (Split-Path $PSScriptRoot -Parent)

# Folders to hit:
# - Working Directory
# - C:\ProgramData\Microsoft\IntuneManagementExtension\Logs
# - HKLM:\SOFTWARE\AdminScriptSuite

# List of folders to check / fix
$Folders = @(
    "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs",
    "$RepoRoot",
    "$WorkingDir\TEMP",
    "$WorkingDir\LOGS"
)

# REGISTRY KEYS to check/fix
$RegistryKeys = @(
    'HKLM:\SOFTWARE\MyLockedKey',
    'HKLM:\SYSTEM\CurrentControlSet\Services\MyService'
)


#################
### Functions ###
#################


function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    if ($Level -eq "INFO2") {
        $logEntry = "[$timestamp] [INFO] $Message"
    } else {
        $logEntry = "[$timestamp] [$Level] $Message"
    }

    
    
    switch ($Level) {
        "ERROR"   { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "DRYRUN"  { Write-Host $logEntry -ForegroundColor Cyan }
        "INFO"    { Write-Host $logEntry -ForegroundColor White }


        default   { Write-Host $logEntry }
    }
    
    # Ensure log directory exists
    $logDir = Split-Path $LogPath -Parent
    if (!(Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    Add-Content -Path $LogPath -Value $logEntry
}



# --- Helper: build the "correct" ACL for a folder ---
function Set-StrictAcl {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Log "Path not found: $Path" "WARNING"
        return
    }

    # SIDs for SYSTEM and BUILTIN\Administrators
    $sidSystem = New-Object System.Security.Principal.SecurityIdentifier "S-1-5-18"
    $sidAdmins = New-Object System.Security.Principal.SecurityIdentifier "S-1-5-32-544"

    # Create a fresh ACL object
    $acl = New-Object System.Security.AccessControl.DirectorySecurity

    # Disable inheritance and remove inherited rules
    $acl.SetAccessRuleProtection($true, $false)

    $inheritFlags  = [System.Security.AccessControl.InheritanceFlags] "ContainerInherit, ObjectInherit"
    $propFlags     = [System.Security.AccessControl.PropagationFlags] "None"
    $accessType    = [System.Security.AccessControl.AccessControlType]::Allow

    # Add SYSTEM FullControl
    $ruleSystem = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $sidSystem,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        $inheritFlags,
        $propFlags,
        $accessType
    )
    $acl.AddAccessRule($ruleSystem) | Out-Null

    # Add Administrators FullControl
    $ruleAdmins = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $sidAdmins,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        $inheritFlags,
        $propFlags,
        $accessType
    )
    $acl.AddAccessRule($ruleAdmins) | Out-Null

    # Apply ACL to folder
    Set-Acl -LiteralPath $Path -AclObject $acl
    Write-Log "[$Path] permissions reset to SYSTEM + Administrators (FullControl only)."
}

# --- Helper: check if ACL is already in the desired state ---
function Test-StrictAcl {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Log "Path not found: $Path" "WARNING"
        return $false
    }

    $acl = Get-Acl -LiteralPath $Path

    $sidSystem = New-Object System.Security.Principal.SecurityIdentifier "S-1-5-18"
    $sidAdmins = New-Object System.Security.Principal.SecurityIdentifier "S-1-5-32-544"
    $allowedSids = @($sidSystem.Value, $sidAdmins.Value)

    # Must have protected ACL (no inheritance)
    if (-not $acl.AreAccessRulesProtected) {
        return $false
    }

    $hasSystem = $false
    $hasAdmins = $false

    foreach ($rule in $acl.Access) {
        $sid = $rule.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value

        # Only SYSTEM or Administrators allowed
        if ($sid -notin $allowedSids) {
            return $false
        }

        # Must be Allow FullControl
        if ($rule.AccessControlType -ne 'Allow') { return $false }

        $fc = [System.Security.AccessControl.FileSystemRights]::FullControl
        if (($rule.FileSystemRights -band $fc) -ne $fc) { return $false }

        # Must inherit to children
        if (($rule.InheritanceFlags -band ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit)) -eq 0 `
         -or ($rule.InheritanceFlags -band ([System.Security.AccessControl.InheritanceFlags]::ObjectInherit)) -eq 0) {
            return $false
        }

        if ($sid -eq $sidSystem.Value) { $hasSystem = $true }
        if ($sid -eq $sidAdmins.Value) { $hasAdmins = $true }
    }

    # Require at least one rule for SYSTEM and one for Administrators
    return ($hasSystem -and $hasAdmins)

}

function Test-StrictRegAcl {
    param(
        [Parameter(Mandatory)]
        [string]$KeyPath
    )

    if (-not (Test-Path -LiteralPath $KeyPath)) {
        Write-Log "Registry key not found: $KeyPath" "WARNING"
        return $false
    }

    $acl = Get-Acl -LiteralPath $KeyPath

    # require protected ACL (no inheritance from parent key)
    if (-not $acl.AreAccessRulesProtected) {
        return $false
    }

    $hasSystem = $false
    $hasAdmins = $false

    $fc = [System.Security.AccessControl.RegistryRights]::FullControl
    $ci = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit

    foreach ($rule in $acl.Access) {
        $sid = $rule.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value

        # Only SYSTEM or Administrators allowed
        if ($sid -notin $allowedSids) { return $false }

        # Must be Allow FullControl
        if ($rule.AccessControlType -ne 'Allow') { return $false }
        if (($rule.RegistryRights -band $fc) -ne $fc) { return $false }

        # We set ContainerInherit for child keys; require it
        if (($rule.InheritanceFlags -band $ci) -eq 0) {
            return $false
        }

        if ($sid -eq $sidSystem.Value) { $hasSystem = $true }
        if ($sid -eq $sidAdmins.Value) { $hasAdmins = $true }
    }

    return ($hasSystem -and $hasAdmins)
}

function Set-StrictRegAcl {
    param(
        [Parameter(Mandatory)]
        [string]$KeyPath
    )

    if (-not (Test-Path -LiteralPath $KeyPath)) {
        Write-Log "Registry key not found: $KeyPath" "WARNING"
        return
    }

    $regSec = New-Object System.Security.AccessControl.RegistrySecurity

    # disable inheritance and remove inherited rules
    $regSec.SetAccessRuleProtection($true, $false)

    $inheritFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit  # child keys
    $propFlags    = [System.Security.AccessControl.PropagationFlags]::None
    $accessType   = [System.Security.AccessControl.AccessControlType]::Allow
    $fc           = [System.Security.AccessControl.RegistryRights]::FullControl

    $ruleSystem = New-Object System.Security.AccessControl.RegistryAccessRule(
        $sidSystem,
        $fc,
        $inheritFlags,
        $propFlags,
        $accessType
    )
    $regSec.AddAccessRule($ruleSystem) | Out-Null

    $ruleAdmins = New-Object System.Security.AccessControl.RegistryAccessRule(
        $sidAdmins,
        $fc,
        $inheritFlags,
        $propFlags,
        $accessType
    )
    $regSec.AddAccessRule($ruleAdmins) | Out-Null

    $key = Get-Item -LiteralPath $KeyPath
    $key.SetAccessControl($regSec)

    Write-Log "[$KeyPath] registry ACL reset to SYSTEM + Administrators only."
}


## MAIN ##

Write-Log "SCRIPT: $ThisFileName | START | Security Manager initiated."

foreach ($folder in $Folders) {
    Write-Log "Checking folder: $folder ..."

    if (-not (Test-Path -LiteralPath $folder)) {

            Write-Log "Folder not found: $folder" "WARNING"

            #Exit 1

    } else {

        Write-Log "Folder exists: $folder"

        if (Test-StrictAcl -Path $folder) {

            Write-Log "ACL already correct. No change."

        } else {

            Write-Log "ACL not strict. Fixing..."

            Set-StrictAcl -Path $folder

            if (Test-StrictAcl -Path $folder) {

                Write-Log "ACL fixed successfully." "SUCCESS"

            } else {

                Write-Log "Failed to fix ACL!" "ERROR"

                Exit 1

            }

        }

    }

}

foreach ($regKey in $RegistryKeys) {
    Write-Log "Checking registry key $regKey ..."

    if (-not (Test-Path -LiteralPath $regKey)) {

            Write-Log "Registry key not found: $regKey" "WARNING"

    } else {

        Write-Log "Registry key exists: $regKey"

        if (Test-StrictRegAcl -KeyPath $regKey) {

            Write-Log "Registry ACL already correct."

        } else {

            Write-Log "Registry ACL not strict. Fixing..."
            Set-StrictRegAcl -KeyPath $regKey

            if (Test-StrictRegAcl -KeyPath $regKey) {

                Write-Log "Registry ACL fixed successfully." "SUCCESS"

            } else {

                Write-Log "Failed to fix registry ACL!" "ERROR"

                Exit 1

            }

        }

    }

}

# Return success
Write-Log "SCRIPT: $ThisFileName | END | Security Manager completed successfully." "SUCCESS"
Exit 0
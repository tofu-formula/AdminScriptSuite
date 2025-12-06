# Security Manager

# This guy is gonna be referenced from the Git Runner. Every time Git Runner does something there will be a security check.
# It should be called after the Git Runner does a pull but before it runs any scripts.
# It should be ran a second time after the scripts are ran to make sure nothing sketchy happened.
# The registry portion may need to be carried out by the registry manager script
# May want to consider logging turn off for performance reasons, otherwise this will eat up a lot of space on all of our end machines.

# Security manager can be modified in the future to perform other actions, such as checking for specfic certs
$WorkingDirectory = (Split-Path $PSScriptRoot -Parent)
$ThisFileName = $MyInvocation.MyCommand.Name
$LogRoot = "$WorkingDirectory\Logs\Security_Logs"
$LogPath = "$LogRoot\$ThisFileName._Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$RepoRoot = $PSScriptRoot

# Folders to hit:
# - Working Directory
# - C:\ProgramData\Microsoft\IntuneManagementExtension\Logs
# - HKLM:\SOFTWARE\AdminScriptSuite

# List of folders to check / fix
$Folders = @(
    "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs",
    "$RepoRoot",
    "$WorkingDirectory\TEMP",
    "$WorkingDirectory\LOGS",
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
        "INFO"    { Write-Host $logEntry -ForegroundColor Cyan }
        "INFO2"    { Write-Host $logEntry }

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
        Write-Warning "Path not found: $Path"
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
    Write-Host "[$Path] permissions reset to SYSTEM + Administrators (FullControl only)."
}

# --- Helper: check if ACL is already in the desired state ---
function Test-StrictAcl {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warning "Path not found: $Path"
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



## MAIN ##


foreach ($folder in $Folders) {
    Write-Host "Checking $folder ..."
    if (Test-StrictAcl -Path $folder) {
        Write-Host "  ACL already correct. No change."
    } else {
        Write-Host "  ACL not strict. Fixing..."
        Set-StrictAcl -Path $folder
    }
}

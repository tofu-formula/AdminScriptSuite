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

# Registry Modifcation script path
$RegistryChangeScriptPath = "$RepoRoot\Configurators\Configure-Registry.ps1"

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
    'HKLM:\SOFTWARE\AdminScriptSuite'
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

function Set-StrictAclOld {
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

function Set-StrictAclOld2 {

    # Get current ACL
    Write-Log "Getting current ACL"
    $CurrentACL = Get-Acl -LiteralPath $folder

    # Break inheritance and remove inherited rules
    Write-Log "Breaking inheritance and removing inherited rules"
    $CurrentACL.SetAccessRuleProtection($true, $false)

    # Remove all existing access rules
    Write-Log "Removing existing access rules"
    $CurrentACL.Access | ForEach-Object {
        $CurrentACL.RemoveAccessRuleAll($_) # | Out-Null
    }

    # Build new access rules

    Write-Log "Building new access rules for Administrators and SYSTEM"

    $admins = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Administrators",
        "FullControl",
        "ContainerInherit, ObjectInherit",
        "None",
        "Allow"
    )

    $system = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "SYSTEM",
        "FullControl",
        "ContainerInherit, ObjectInherit",
        "None",
        "Allow"
    )

    # Add new rules to ACL
    Write-Log "Adding new access rules to ACL"
    $CurrentACL.AddAccessRule($admins)
    $CurrentACL.AddAccessRule($system)

    # Apply the ACL back to the folder
    Write-Log "Applying updated ACL to folder"
    Set-Acl -LiteralPath $folder -AclObject $CurrentACL

}

function Set-StrictAcl {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        # Get current ACL
        Write-Log "Getting current ACL for: $Path"
        $CurrentACL = Get-Acl -LiteralPath $Path

        # Break inheritance and remove inherited rules
        Write-Log "Breaking inheritance and removing inherited rules"
        $CurrentACL.SetAccessRuleProtection($true, $false)

        # Remove all existing access rules (copy to array first to avoid collection modification issues)
        Write-Log "Removing existing access rules"
        $rulesToRemove = @($CurrentACL.Access)
        foreach ($rule in $rulesToRemove) {
            $CurrentACL.RemoveAccessRuleAll($rule)
        }

        # Build new access rules
        Write-Log "Building new access rules for Administrators and SYSTEM"

        $admins = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "BUILTIN\Administrators",
            "FullControl",
            "ContainerInherit, ObjectInherit",
            "None",
            "Allow"
        )

        $system = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "NT AUTHORITY\SYSTEM",
            "FullControl",
            "ContainerInherit, ObjectInherit",
            "None",
            "Allow"
        )

        # Add new rules to ACL
        Write-Log "Adding new access rules to ACL"
        $CurrentACL.AddAccessRule($admins)
        $CurrentACL.AddAccessRule($system)

        # Apply the ACL back to the folder
        Write-Log "Applying updated ACL to folder: $Path"
        Set-Acl -LiteralPath $Path -AclObject $CurrentACL -ErrorAction Stop
        
        Write-Log "ACL applied successfully" "SUCCESS"
    }
    catch {
        Write-Log "Set-Acl failed: $($_.Exception.Message)" "ERROR"
        throw
    }
}

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

function Test-StrictAclTEST {
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
        Write-Log "DIAG: ACL inheritance is NOT protected" "WARNING"
        return $false
    }
    Write-Log "DIAG: ACL inheritance is protected" "INFO"

    $hasSystem = $false
    $hasAdmins = $false

    Write-Log "DIAG: Found $($acl.Access.Count) access rules" "INFO"

    foreach ($rule in $acl.Access) {
        try {
            $sid = $rule.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
        }
        catch {
            Write-Log "DIAG: Failed to translate SID for: $($rule.IdentityReference) - $($_.Exception.Message)" "WARNING"
            return $false
        }

        Write-Log "DIAG: Rule - Identity: $($rule.IdentityReference), SID: $sid, Rights: $($rule.FileSystemRights), Type: $($rule.AccessControlType), Inherit: $($rule.InheritanceFlags)" "INFO"

        # Only SYSTEM or Administrators allowed
        if ($sid -notin $allowedSids) {
            Write-Log "DIAG: Unexpected SID found: $sid (expected: $($allowedSids -join ', '))" "WARNING"
            return $false
        }

        # Must be Allow FullControl
        if ($rule.AccessControlType -ne 'Allow') {
            Write-Log "DIAG: Rule is not Allow type" "WARNING"
            return $false
        }

        $fc = [System.Security.AccessControl.FileSystemRights]::FullControl
        if (($rule.FileSystemRights -band $fc) -ne $fc) {
            Write-Log "DIAG: Rights mismatch. Has: $($rule.FileSystemRights) ($([int]$rule.FileSystemRights)), Need: $fc ($([int]$fc))" "WARNING"
            return $false
        }

        # Must inherit to children
        if (($rule.InheritanceFlags -band ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit)) -eq 0 `
         -or ($rule.InheritanceFlags -band ([System.Security.AccessControl.InheritanceFlags]::ObjectInherit)) -eq 0) {
            Write-Log "DIAG: Inheritance flags not set correctly: $($rule.InheritanceFlags)" "WARNING"
            return $false
        }

        if ($sid -eq $sidSystem.Value) { $hasSystem = $true }
        if ($sid -eq $sidAdmins.Value) { $hasAdmins = $true }
    }

    Write-Log "DIAG: hasSystem=$hasSystem, hasAdmins=$hasAdmins" "INFO"

    # Require at least one rule for SYSTEM and one for Administrators
    return ($hasSystem -and $hasAdmins)
}

function Test-SupportsAclProtection {
    param([string]$Path)
    
    # Quick test: try to set protection and verify it sticks
    try {
        $testAcl = Get-Acl -LiteralPath $Path
        $originalState = $testAcl.AreAccessRulesProtected
        
        # Try setting protection
        $testAcl.SetAccessRuleProtection($true, $true)  # Keep existing rules
        Set-Acl -LiteralPath $Path -AclObject $testAcl -ErrorAction Stop
        
        # Re-read and check
        $verifyAcl = Get-Acl -LiteralPath $Path
        $supported = $verifyAcl.AreAccessRulesProtected
        
        # Restore original state if we changed it
        if (-not $originalState -and $supported) {
            $testAcl.SetAccessRuleProtection($false, $false)
            Set-Acl -LiteralPath $Path -AclObject $testAcl -ErrorAction SilentlyContinue
        }
        
        return $supported
    }
    catch {
        return $false
    }
}


## MAIN ##

Write-Log "SCRIPT: $ThisFileName | START | Security Manager initiated."

foreach ($folder in $Folders) {
    Write-Log "Checking folder: $folder ..."

    if (-not (Test-Path -LiteralPath $folder)) {

            Write-Log "Folder not found: $folder" "WARNING"

            #Exit 1

    } elseif(-not (Test-SupportsAclProtection -Path $folder)){

        Write-Log "Folder does not support ACL protection (shared/virtual filesystem?): $folder" "WARNING"

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

        Write-Log "Registry key exists: $regKey. Proceeding to check and set ACL..."

        & $RegistryChangeScriptPath -KeyOnly $true -KeyPath $regKey -Function "Lockdown" -WorkingDirectory $WorkingDir

        if ($LASTEXITCODE -ne 0) {

            Write-Log "Failed to set strict ACL on registry key: $regKey" "ERROR"

            Exit 1

        } else {

            Write-Log "Registry key ACL set to strict successfully." "SUCCESS"

        }

    }

}

# Return success
Write-Log "SCRIPT: $ThisFileName | END | Security Manager completed successfully." "SUCCESS"
Exit 0
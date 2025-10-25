# # Common_Functions.ps1
# Version: 1.0.0
# Description: Centralized function library for AdminScriptSuite

<#
.SYNOPSIS
    Common functions used across the AdminScriptSuite
.DESCRIPTION
    This file contains all shared functions to maintain consistency
    and enable quick updates across all scripts.
#>

Function CheckAndInstallandRepair-WinGetPSmodule {

    "WWEEEEEEE"
    
    # Check if WinGet PowerShell module is installed
    $moduleInstalled = Get-Module -ListAvailable -Name Microsoft.WinGet.Client -ErrorAction SilentlyContinue
    
    if (!$moduleInstalled) {
        Write-Log "WinGetPSmodule not found, beginning installation..."
        
        # Install NuGet provider if needed
        Write-Log "Installing NuGet provider..."
        Try {
            $null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
            Write-Log "NuGet provider installed successfully"
        } Catch {
            Write-Log "Failed to install NuGet: $_" "ERROR"
            Write-Log "SCRIPT: $ThisFileName | END | Install of NuGet failed. Now exiting script." "ERROR"
            Exit 1
        }

        # Install WinGet PowerShell Module
        Write-Log "Installing WinGet PowerShell Module..."
        Try {
            Install-Module -Name Microsoft.WinGet.Client -Repository PSGallery -Force -AllowClobber -Scope AllUsers -ErrorAction Stop
            Write-Log "WinGet PowerShell Module installed successfully"
        } Catch {
            Write-Log "Failed to install WinGet PowerShell Module: $_" "ERROR"
            Write-Log "SCRIPT: $ThisFileName | END | Install of WinGet module failed. Now exiting script." "ERROR"
            Exit 1
        }
    } else {
        Write-Log "WinGetPSmodule is already installed"
    }
    
    # Import the module
    Write-Log "Importing WinGet PowerShell Module..."
    Try {
        Import-Module Microsoft.WinGet.Client -Force -ErrorAction Stop
        Write-Log "WinGet PowerShell Module imported successfully"
    } Catch {
        Write-Log "Failed to import WinGet PowerShell Module: $_" "ERROR"
        Write-Log "SCRIPT: $ThisFileName | END | Import of WinGet module failed. Now exiting script." "ERROR"
        Exit 1
    }
    
    # Try to repair WinGet, but don't fail if it doesn't work (common in SYSTEM context)
    Try {
        # Check if the Repair cmdlet exists and if we're not running as SYSTEM
        if (Get-Command Repair-WinGetPackageManager -ErrorAction SilentlyContinue) {
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            if ($currentUser.Name -ne 'NT AUTHORITY\SYSTEM') {
                Write-Log "Attempting to repair WinGetPackageManager..."
                Repair-WinGetPackageManager -AllUsers -Force -ErrorAction Stop
                Write-Log "WinGetPackageManager repair completed"
            } else {
                Write-Log "Running as SYSTEM, skipping WinGet repair (not needed for PowerShell module)"
            }
        } else {
            Write-Log "Repair-WinGetPackageManager not available, continuing without repair"
        }
    } Catch {
        # Don't fail on repair errors - the module often works without it
        Write-Log "Note: Could not repair WinGetPackageManager (non-critical): $_" "WARNING"
        Write-Log "Continuing with installation - PowerShell module should still work"
    }
    
    # Verify the module is working
    Try {
        $testCommand = Get-Command Install-WinGetPackage -ErrorAction Stop
        Write-Log "WinGet PowerShell Module verified and ready to use"
    } Catch {
        Write-Log "Failed to verify WinGet PowerShell Module: $_" "ERROR"
        Write-Log "SCRIPT: $ThisFileName | END | WinGet module verification failed. Now exiting script." "ERROR"
        Exit 1
    }
}

Export-ModuleMember -Function @(

    'CheckAndInstallandRepair-WinGetPSmodule'

)
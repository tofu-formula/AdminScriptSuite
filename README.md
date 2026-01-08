
<img width="2083" height="1718" alt="powerdeploy_logo_white_bg" src="https://github.com/user-attachments/assets/fe2d39b3-1500-4629-94c8-6f08702f1e84" />

# PowerDeploy

This writeup was written by AI and is just for proof of concept purposes.

A comprehensive PowerShell automation framework designed for enterprise endpoint management and deployment. This suite provides centralized administrative scripts that automate software installation, configuration management, and system maintenance tasks across organizational environments.


## Overview

PowerDeploy is specifically architected for deployment through enterprise tools like **Microsoft Intune**, **Datto RMM**, and **SCCM**, with scripts designed to run in SYSTEM context on managed endpoints. The framework emphasizes reliability, consistency, and enterprise-scale deployment capabilities.


### Key Features

- **Software Management** — WinGet-based installers, MSI support, and comprehensive uninstallers with multiple removal methods
- **Printer Management** — Automated IP printer installation with driver management via Azure Blob Storage
- **Azure Integration** — Blob storage access for centralized configuration and driver distribution
- **Windows Features** — Enable/disable Windows Optional Features programmatically
- **Registry Management** — Secure registry operations with ACL management and 32/64-bit redirection handling
- **Git-Based Deployment** — Pull latest scripts from repositories and execute on target machines
- 

## Why PowerDeploy?

Native Microsoft Intune has significant limitations that create headaches for IT administrators. PowerDeploy was built to solve these real-world problems:


### 🖨️ Printer Management Done Right

**The Problem:** Intune only offers Universal Print by default, which is unreliable and doesn't cover many enterprise printing scenarios.

**Our Solution:** PowerDeploy includes complete infrastructure to replace your print server. Easily add and manage printer availability across your organization using Azure Blob Storage for centralized driver and configuration management.


### 📦 Reliable Application Deployment

**The Problem:** Intune has notoriously inconsistent installation success rates. Even custom installers under 50MB fail regularly. Larger applications like Microsoft Office or Adobe Acrobat have extremely high failure rates when deployed through native Intune.

**Our Solution:** Only a lightweight runner script is hosted in Intune. The actual applications are pulled from the Microsoft Store via WinGet or your private Azure Blob storage — dramatically improving reliability and eliminating Intune's size limitations.


### ⚡ Rapid Development & Testing

**The Problem:** Intune apps have a painfully long development cycle. Modifying installers requires re-uploading, re-configuring, and waiting for sync cycles. Testing is slow and centralized changes are difficult.

**Our Solution:** The installer script never needs modification for troubleshooting. Make changes in real-time via GitHub or Azure Blob — your endpoints pull the latest version automatically. Test iterations in minutes, not hours.


### 📋 Comprehensive Logging

**The Problem:** Native Intune installation logging is inflexible, vague, and scattered across multiple locations. Troubleshooting failed deployments often feels like detective work.

**Our Solution:** Every script includes detailed, color-coded logging with timestamps, severity levels, and centralized log storage. Know exactly what happened, when, and why.


### 🏪 Full Microsoft Store Access

**The Problem:** The app selection available through Intune's Microsoft Store integration is limited, and many packages are outdated versions.

**Our Solution:** Full, real-time access to nearly everything in the Microsoft Store through WinGet. Install the latest versions of applications the moment they're available.


### 🔄 Streamlined Update Management

**The Problem:** Intune is extremely clunky at handling application updates. Keeping apps current requires creating new app entries, managing supersedence, and hoping detection rules work correctly.

**Our Solution:** For WinGet-based installs, pair with [WinGet Updater](https://github.com/Romanitho/Winget-AutoUpdate) to automatically keep applications current. For custom MSI deployments, simply update your JSON configuration and Azure Blob source — no need to touch the Intune app entry. *(Custom app auto-updater coming soon)*


### 🗑️ Simplified Uninstallation

**The Problem:** Finding the correct uninstaller strings for applications is often a frustrating treasure hunt through registry keys and installer logs.

**Our Solution:** The General Uninstaller script handles multiple removal methods automatically — WinGet, registry-based, WMI, and more. Just provide the app name and let the script figure out the rest.


### ✅ WinGet That Actually Works

**The Problem:** WinGet in SYSTEM context (how Intune runs scripts) has numerous quirks and often fails silently.

**Our Solution:** Our WinGet installer script handles all the edge cases — bootstrapping WinGet if missing, resetting sources, handling 32/64-bit contexts, and providing detailed error reporting when things go wrong.


### 🚀 On-Demand Execution

**The Problem:** Intune automatic app deployment can take anywhere from minutes to 48+ hours with no option to trigger execution manually for testing or urgent deployments.

**Our Solution:** Scripts are stored locally in ProgramData with manual launch options. Need an app installed right now? Run it directly. No waiting for Intune sync cycles.


---

## Prerequisites

- Windows 10/11 or Windows Server 2016+
- PowerShell 5.1 or later
- Administrator privileges for installation scripts
- (Optional) Azure Blob Storage account for printer/application data
- (Optional) Microsoft Intune, Datto RMM, or SCCM for enterprise deployment

## Quick Start

### Option 1: Run Setup Wizard

```powershell
# Clone or download the repository
git clone https://github.com/Adrian-Mandel/PowerDeploy.git

# Run the setup script (as Administrator)
.\Setup_RUNNER.bat
# Or directly:
.\Setup.ps1
```

### Option 2: Use Git Runner Template

The Git Runner allows you to pull the latest commit from the repository and execute any script within it:

```powershell
.\Git-Runner_TEMPLATE.ps1 `
    -RepoNickName "PowerDeploy-Repo" `
    -RepoURL "https://github.com/Adrian-Mandel/PowerDeploy.git" `
    -ScriptPath "Installers\General_WinGet_Installer.ps1" `
    -WorkingDirectory "C:\ProgramData\PowerDeploy" `
    -ScriptParams '-AppID "7zip.7zip" -WorkingDirectory "C:\ProgramData\PowerDeploy"'
```

## Directory Structure

```
PowerDeploy/
├── Setup.ps1                    # Main setup wizard
├── Setup_RUNNER.bat             # Batch launcher for Setup.ps1
├── Installers/
│   ├── General_WinGet_Installer.ps1    # WinGet-based app installer
│   ├── General_IP-Printer_Installer.ps1 # Network printer installer
│   ├── Install-WinGet.ps1              # WinGet bootstrap installer
│   └── Install-DotNET.ps1              # .NET Framework/Runtime installer
├── Uninstallers/
│   └── General_Uninstaller.ps1         # Multi-method app uninstaller
├── Configurators/
│   ├── Configure-Registry.ps1          # Registry management utility
│   └── Configure-WindowsOptionalFeatures.ps1
├── Templates/
│   ├── Git-Runner_TEMPLATE.ps1         # Git-based script runner
│   ├── General_RemediationScript-Registry_TEMPLATE.ps1
│   └── OrganizationCustomRegistryValues-Reader_TEMPLATE.ps1
└── Other_Tools/
    ├── Generate_Install-Command.ps1    # Intune command generator
    ├── Generate_Custom-Script_FromTemplate.ps1
    └── Security_Manager.ps1            # Security and ACL management

```

## Core Scripts

### Installers

#### General_WinGet_Installer.ps1
Installs applications using Windows Package Manager (WinGet) with automatic WinGet bootstrap if needed.

```powershell
.\General_WinGet_Installer.ps1 `
    -AppID "Microsoft.VisualStudioCode" `
    -WorkingDirectory "C:\ProgramData\PowerDeploy"

# With specific version
.\General_WinGet_Installer.ps1 `
    -AppID "7zip.7zip" `
    -Version "23.01" `
    -WorkingDirectory "C:\ProgramData\PowerDeploy"
```

#### General_IP-Printer_Installer.ps1
Installs network printers with automatic driver download from Azure Blob Storage.

```powershell
.\General_IP-Printer_Installer.ps1 `
    -PrinterName "Office-HP-LaserJet" `
    -IPAddress "192.168.1.100" `
    -DriverName "HP Universal Printing PCL 6" `
    -WorkingDirectory "C:\ProgramData\PowerDeploy"
```

#### Install-DotNET.ps1
Installs .NET Framework or .NET Runtime/SDK versions using appropriate methods.

```powershell
# .NET Framework 3.5 (uses Windows Optional Features)
.\Install-DotNET.ps1 -Version "3.5" -WorkingDirectory "C:\ProgramData\PowerDeploy"

# .NET 8 Desktop Runtime (uses WinGet)
.\Install-DotNET.ps1 -Version "8" -WorkingDirectory "C:\ProgramData\PowerDeploy"

# .NET 8 SDK
.\Install-DotNET.ps1 -Version "8" -InstallType "SDK" -WorkingDirectory "C:\ProgramData\PowerDeploy"
```

### Uninstallers

#### General_Uninstaller.ps1
Multi-method uninstaller supporting WinGet, registry-based, WMI, and other removal techniques.

```powershell
# Uninstall using all available methods
.\General_Uninstaller.ps1 `
    -AppName "7-zip" `
    -UninstallType "All" `
    -WorkingDirectory "C:\ProgramData\PowerDeploy"

# Uninstall using WinGet only
.\General_Uninstaller.ps1 `
    -AppName "7-zip" `
    -UninstallType "Win_Get" `
    -WorkingDirectory "C:\ProgramData\PowerDeploy"
```

### Templates

#### Git-Runner_TEMPLATE.ps1
The cornerstone of remote deployment — pulls the latest repository commit and executes specified scripts.

**Parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `RepoNickName` | Yes | Local name for the repository |
| `RepoUrl` | Yes | GitHub repository URL |
| `WorkingDirectory` | Yes | Local working directory path |
| `ScriptPath` | No | Path to script within repo |
| `ScriptParams` | No | Parameters to pass to target script |
| `ScriptParamsBase64` | No | Base64-encoded parameters (for Intune) |
| `UpdateLocalRepoOnly` | No | Exit after pulling repo (skip script execution) |

## Enterprise Deployment

### Microsoft Intune

Generate deployment commands using the built-in command generator:

```powershell
.\Other_Tools\Generate_Install-Command.ps1 `
    -DesiredFunction "CreateIntuneCommand" `
    -FunctionParams @{
        RepoNickName = "PowerDeploy-Repo"
        RepoUrl = "https://github.com/Adrian-Mandel/PowerDeploy.git"
        WorkingDirectory = "C:\ProgramData\PowerDeploy"
        ScriptPath = "Installers\General_WinGet_Installer.ps1"
        ScriptParams = @{
            AppID = "7zip.7zip"
            WorkingDirectory = "C:\ProgramData\PowerDeploy"
        }
    }
```

**Intune Command Format:**
```cmd
%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '.\Git-Runner_TEMPLATE.ps1' -RepoNickName 'PowerDeploy-Repo' -RepoUrl 'https://github.com/Adrian-Mandel/PowerDeploy.git' -WorkingDirectory 'C:\ProgramData\PowerDeploy' -ScriptPath 'Installers\General_WinGet_Installer.ps1' -ScriptParamsBase64 'BASE64_ENCODED_PARAMS'"
```

### Remediation Scripts

Create detection and remediation script pairs for Intune Proactive Remediations:

```powershell
# Detection script checks registry values
# Remediation script applies required configuration

.\Other_Tools\Generate_Install-Command.ps1 `
    -DesiredFunction "CreateRemediationScripts"
```

## Azure Integration

### Setting Up Azure Blob Storage

1. Create an Azure Storage Account
2. Create containers for printers, applications, and drivers
3. Generate SAS tokens with appropriate permissions
4. Configure registry values on endpoints:

```powershell
# Registry path: HKLM:\SOFTWARE\PowerDeploy
# Values required:
#   General\StorageAccountName = "yourstorageaccount"
#   Printers\PrinterDataJSONpath = "printers/PrinterData.json"
#   Printers\PrinterContainerSASkey = "your-sas-token"
#   Applications\ApplicationDataJSONpath = "applications/ApplicationData.json"
#   Applications\ApplicationContainerSASkey = "your-sas-token"
```

### JSON Configuration Examples

**PrinterData.json:**
```json
{
  "printers": [
    {
      "name": "Office-HP-4000",
      "ipAddress": "192.168.1.100",
      "driverName": "HP Universal Printing PCL 6",
      "driverPath": "Drivers/HP/HP_Universal_PCL6/hpcu270u.inf",
      "location": "Building A - Floor 2"
    }
  ]
}
```

## Logging

All scripts implement comprehensive logging with color-coded output:

- **INFO** — Standard operational messages
- **SUCCESS** — Successful operations (Green)
- **WARNING** — Non-critical issues (Yellow)
- **ERROR** — Critical failures (Red)
- **DRYRUN** — Simulation mode output (Cyan)

Log files are stored in: `{WorkingDirectory}\Logs\{Category}_Logs\`

## Security Features

- **ACL Management** — Protects sensitive directories from unauthorized access
- **Certificate-Based Encryption** — Secure credential storage
- **DPAPI Support** — Windows Data Protection API integration
- **Registry ACLs** — Protect sensitive registry values from standard users
- **Execution Context Handling** — Proper SYSTEM account and user context management

## Design Principles

1. **Comprehensive Logging** — Every action is logged with timestamps and severity levels
2. **Robust Error Handling** — Try-catch blocks with proper exit codes
3. **Administrator Verification** — Scripts verify elevation before system modifications
4. **Path Validation** — All paths are validated before use
5. **Standardized Parameters** — Consistent parameter naming across all scripts
6. **Modular Architecture** — Functions can be called independently or as workflows

## Troubleshooting

### Common Issues

**WinGet not found in SYSTEM context:**
- The Install-WinGet.ps1 script automatically handles bootstrap installation
- Uses multiple fallback methods if primary installation fails

**32-bit vs 64-bit registry access:**
- Scripts automatically handle registry redirection
- Use `Sysnative` path for 64-bit PowerShell from 32-bit context

**Azure Blob access failures:**
- Verify SAS token hasn't expired
- Check storage account firewall rules
- Ensure container permissions are correct

### Log Locations

| Category | Path |
|----------|------|
| Git Operations | `{WorkingDirectory}\Logs\Git_Logs\` |
| Installations | `{WorkingDirectory}\Logs\Installer_Logs\` |
| Uninstallations | `{WorkingDirectory}\Logs\Uninstaller_Logs\` |
| Setup | `{WorkingDirectory}\Logs\Setup_Logs\` |
| Security | `{WorkingDirectory}\Logs\Security_Logs\` |

## Contributing

Contributions are welcome! Please ensure:

1. Scripts follow the established logging and error handling patterns
2. Parameters use consistent naming conventions
3. All new scripts include comprehensive comment-based help
4. Test in both local and SYSTEM contexts before submitting

## License

PENDING

## Support

For issues and feature requests, please use the [GitHub Issues](https://github.com/Adrian-Mandel/PowerDeploy/issues) page.

---

**Source:** [https://github.com/Adrian-Mandel/PowerDeploy](https://github.com/Adrian-Mandel/PowerDeploy)

---

**NOTE**

This writeup was written by AI and is just for proof of concept purposes.

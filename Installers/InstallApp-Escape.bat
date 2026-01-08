@echo off

ECHO ===== Preconfigured App Installer =====
ECHO Install App: Escape Online 5 SC
ECHO Download Method: Azure Blob
ECHO Install Method: MSI
ECHO.

setlocal enabledelayedexpansion

REM Get the directory of this batch file (with trailing backslash)
set "SCRIPT_DIR=%~dp0"

REM Remove trailing backslash from SCRIPT_DIR to get clean path
set "SCRIPT_DIR_CLEAN=%SCRIPT_DIR:~0,-1%"


REM Go up ONE level to get repo root
set "REPOROOT=%SCRIPT_DIR%..\"

REM Normalize the repo directory path (resolves .. and .)
for %%i in ("%REPOROOT%") do set "REPOROOT=%%~fi"

REM Remove trailing backslash to prevent escape character issues
if "%REPOROOT:~-1%"=="\" set "REPOROOT=%REPOROOT:~0,-1%"


REM Go up TWO level to get the working directory
set "WORKINGDIR=%SCRIPT_DIR%..\..\"

REM Normalize the working directory path (resolves .. and .)
for %%i in ("%WORKINGDIR%") do set "WORKINGDIR=%%~fi"

REM Remove trailing backslash to prevent escape character issues
if "%WORKINGDIR:~-1%"=="\" set "WORKINGDIR=%WORKINGDIR:~0,-1%"

ECHO Working Directory (puts logs folder here): %WORKINGDIR%
ECHO Repo path: %REPOROOT%
ECHO If that is acceptable...

Pause

Echo Downloading Escape...
Powershell.exe -executionpolicy bypass -File "%REPOROOT%\Downloaders\DownloadFrom-AzureBlob-AADauth.ps1" -WorkingDirectory "%WORKINGDIR%" -StorageAccountName "genericdeploy" -ContainerName "applications" -BlobDirectoryPath "Escape" -BlobName "Escape_Online_5_Client_SC_PROD.msi" -TenantId "7516abc4-25c0-43bd-9371-07778cadffb6"
REM if %ERRORLEVEL% GEQ 1 EXIT /B 1
REM Need to replace the line below with a call to the install-msi script once that is finished
set "EscapeLocation=%WORKINGDIR%\TEMP\Escape_Online_5_Client_SC_PROD.msi"
ECHO Installing Escape from: %EscapeLocation%
Powershell.exe -executionpolicy bypass -File "%REPOROOT%\Installers\General_MSI_Installer.ps1" -WorkingDirectory "%WORKINGDIR%" -MSIPath "%EscapeLocation%" -AppName "Escape" -DisplayName "Escape Online 5 Client"


@REM set SAVESTAMP=%DATE:/=-%@%TIME::=-%
@REM set SAVESTAMP=%SAVESTAMP: =%
@REM set SAVESTAMP=%SAVESTAMP:,=.%.Escape-Install.log

REM msiexec /i "%WORKINGDIR%\TEMP\Escape_Online_5_Client_SC_PROD.msi" /qn /L*v "%WORKINGDIR%\Logs\Installer_Logs\Install-Escape.log"
REM msiexec /i "%REPOROOT%\TEMP\Escape_Online_5_Client_SC_PROD.msi" /qn /norestart /L*v "%REPOROOT%\Logs\Installer_Logs\Install-Escape.log"

REM if %ERRORLEVEL% GEQ 1 EXIT /B 1
Pause
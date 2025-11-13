@echo off

ECHO ===== Preconfigured App Installer =====
ECHO Install App: Adobe Creative Cloud
ECHO Install Method: WinGet
ECHO.

setlocal enabledelayedexpansion

REM Get the directory of this batch file (with trailing backslash)
set "SCRIPT_DIR=%~dp0"

REM Remove trailing backslash from SCRIPT_DIR to get clean path
set "SCRIPT_DIR_CLEAN=%SCRIPT_DIR:~0,-1%"


REM Go up ONE level to get repo root
set "REPOROOT=%%SCRIPT_DIR%..\"

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
ECHO If that is acceptable...
Pause


Powershell.exe -executionpolicy bypass -File "%~dp0General_WinGet_Installer.ps1" -AppName "Adobe_CC" -AppID "Adobe.CreativeCloud" -WorkingDirectory "%WORKINGDIR%"
Pause
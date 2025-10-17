@echo off


ECHO ===== Repo Updater =====

setlocal enabledelayedexpansion

if exist "%~dp0Templates\Git_Runner_TEMPLATE.ps1" (
    Echo Verified Git_Runner exists: /Templates/Git_Runner_TEMPLATE.ps1 
) else (
    Echo ERROR: Could not verify exists: \Templates\Git_Runner_TEMPLATE.ps1 
    Echo Now exiting script.
    Pause
    Exit 1
)

ECHO.
REM Get the directory of this batch file (with trailing backslash)
set "SCRIPT_DIR=%~dp0"

REM Remove trailing backslash from SCRIPT_DIR to get clean path
set "SCRIPT_DIR_CLEAN=%SCRIPT_DIR:~0,-1%"

REM Extract just the folder name from the script directory
for %%i in ("%SCRIPT_DIR_CLEAN%") do set "LOCAL_REPO_FOLDER_NAME=%%~nxi"

REM Go up one level to get the working directory
set "WORKINGDIR=%SCRIPT_DIR%..\"

REM Normalize the working directory path (resolves .. and .)
for %%i in ("%WORKINGDIR%") do set "WORKINGDIR=%%~fi"

REM Remove trailing backslash to prevent escape character issues
if "%WORKINGDIR:~-1%"=="\" set "WORKINGDIR=%WORKINGDIR:~0,-1%"

ECHO WARNING: These are the paths that are currently targeted:
ECHO.
echo WORKINGDIR set to: !WORKINGDIR!
ECHO Info: Root working folder. Contains the local repo folder and the logs folder
ECHO.
echo LOCAL_REPO_FOLDER_NAME set to: !LOCAL_REPO_FOLDER_NAME!
ECHO Info: Name of the local repo folder. Lives inside the folder above.
ECHO.

set /p CORRECT="Is this acceptable? If not, you can enter your own paths. (Y/N): "
ECHO.

if /I "%CORRECT%"=="N" (
    set /p LOCAL_REPO_FOLDER_NAME="Repo nickname/folder name: "
    echo LOCAL_REPO_FOLDER_NAME set to: !LOCAL_REPO_FOLDER_NAME!
    
    set /p WORKINGDIR="Working directory PATH: "
    REM Remove trailing backslash if present
    if "!WORKINGDIR:~-1!"=="\" set "WORKINGDIR=!WORKINGDIR:~0,-1!"
    echo WORKINGDIR set to: !WORKINGDIR!
    
    echo.
    set /p CONFIRM="Are these paths correct? (Y/N): "
    if /I not "!CONFIRM!"=="Y" (
        echo Cancelled. Please run again.
        exit /b 1
    )
)

echo.
echo Reviewing final values:
echo WORKINGDIR: %WORKINGDIR%
echo LOCAL_REPO_FOLDER_NAME: %LOCAL_REPO_FOLDER_NAME%
PAUSE

echo.
echo.
echo DEBUG: About to run PowerShell with these parameters:
echo RepoNickName: "%LOCAL_REPO_FOLDER_NAME%"
echo RepoUrl: "https://github.com/tofu-formula/AdminScriptSuite"
echo UpdateLocalRepoOnly: $true
echo WorkingDirectory: "%WORKINGDIR%"
echo.
echo Full command:
echo Powershell.exe -executionpolicy remotesigned -Command "& '%SCRIPT_DIR%Templates\Git_Runner_TEMPLATE.ps1' -RepoNickName '%LOCAL_REPO_FOLDER_NAME%' -RepoUrl 'https://github.com/tofu-formula/AdminScriptSuite' -UpdateLocalRepoOnly $true -WorkingDirectory '%WORKINGDIR%'"
PAUSE

Powershell.exe -executionpolicy remotesigned -Command "& '%SCRIPT_DIR%Templates\Git_Runner_TEMPLATE.ps1' -RepoNickName '%LOCAL_REPO_FOLDER_NAME%' -RepoUrl 'https://github.com/tofu-formula/AdminScriptSuite' -UpdateLocalRepoOnly $true -WorkingDirectory '%WORKINGDIR%'"

PAUSE
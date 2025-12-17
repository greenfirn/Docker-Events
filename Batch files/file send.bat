@echo off
setlocal enabledelayedexpansion

:: 10.10.0.103 hiveos
:: 10.10.0.114 10.10.0.115 10.10.0.116 intel
:: 3090, 4070tis
:: 10.10.0.104 10.10.0.105
:: clore
:: 10.10.0.100 10.10.0.101 10.10.0.102 10.10.0.108 10.10.0.109 10.10.0.110 10.10.0.111 10.10.0.112 10.10.0.113

:: ================================
:: USER SETTINGS
:: ================================
set "USER=user"
set "PASS=1"

:: Rigs to update
set "RIGS=10.10.0.100 10.10.0.101 10.10.0.102 10.10.0.103 10.10.0.104 10.10.0.105 10.10.0.108 10.10.0.109 10.10.0.110 10.10.0.111 10.10.0.112 10.10.0.113 10.10.0.114 10.10.0.115 10.10.0.116"

sudo systemctl restart rigcloud-agent.service

:: Remote folder to upload into
set "REMOTE_PATH=/home/%USER%"


:: ================================
:: ASK EXTENSION
:: ================================
echo.
echo Enter file extension to search (ex: sh, conf, service, txt):
set /p EXT="Extension: "

set "EXT=%EXT:.=%"
if "%EXT%"=="" (
    echo No extension given. Exiting.
    goto :end
)

set "PATTERN=*.%EXT%"
echo.
echo Searching for "%PATTERN%"...

set "index=0"
for %%F in (%PATTERN%) do (
    set /a index+=1
    set "file[!index!]=%%F"
)

if %index%==0 (
    echo No matching files.
    goto :end
)

echo Found %index% file(s):
for /l %%I in (1,1,%index%) do (
    echo   %%I^) !file[%%I]!
)

echo.
set /p CHOICE="Select file (0 to cancel): "

if "%CHOICE%"=="0" goto :end

for /f "delims=0123456789" %%X in ("%CHOICE%") do (
    echo Invalid number.
    goto :end
)

if %CHOICE% lss 1 goto :end
if %CHOICE% gtr %index% goto :end

set "UPLOADFILE=!file[%CHOICE%]!"
echo Selected: %UPLOADFILE%
echo.


:: ================================
:: REMOTE FILENAME
:: ================================
echo Enter remote filename (leave blank to keep original):
set /p REMOTE_NAME="Remote filename: "
if "%REMOTE_NAME%"=="" set "REMOTE_NAME=%UPLOADFILE%"

echo Uploading as %REMOTE_NAME%
echo.


:: ================================
:: PROCESS EACH RIG
:: ================================
echo ========================================
echo Uploading + restarting rigcloud-agent...
echo ========================================

for %%I in (%RIGS%) do (
    echo.
    echo --- Rig %%I ---
    echo Uploading %UPLOADFILE% ...
    pscp -pw %PASS% "%UPLOADFILE%" %USER%@%%I:%REMOTE_PATH%/%REMOTE_NAME%

    if errorlevel 1 (
        echo [FAIL] Upload failed on %%I
    ) else (
        echo [OK] Uploaded
    )
)

goto :end


:: ================================
:: END
:: ================================
:end
echo.
echo Done.
pause
exit /b

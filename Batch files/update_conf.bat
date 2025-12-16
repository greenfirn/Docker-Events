@echo off
setlocal enabledelayedexpansion

:: ---------------------------------------------------------
:: USER SETTINGS
:: ---------------------------------------------------------
set "USER=user"
set "PASS=1"

:: Rigs to update
set "RIGS=10.10.0.100 10.10.0.101 10.10.0.102"

:: ---------------------------------------------------------
:: SELECT CONFIG .conf FILE (MANDATORY OR SKIP)
:: ---------------------------------------------------------
echo Searching for .conf files in %CD%...
set "cindex=0"

for %%F in (*.conf) do (
    set /a cindex+=1
    set "conf[!cindex!]=%%F"
)

echo.
echo Config Upload Options:
echo   0^) Skip config upload

if %cindex% gtr 0 (
    echo Found %cindex% .conf files:
    for /l %%I in (1,1,%cindex%) do (
        echo   %%I^) !conf[%%I]!
    )
) else (
    echo No .conf files found.
)

echo.
set "CONFFILE="
set /p cchoice="Select config file (0-%cindex%): "

if "%cchoice%"=="0" (
    echo Skipping config upload.
) else (
    if %cchoice% lss 1 (
        echo Invalid choice.
        goto :EndScript
    )
    if %cchoice% gtr %cindex% (
        echo Invalid choice.
        goto :EndScript
    )
    set "CONFFILE=!conf[%cchoice%]!"
    echo Selected config: !CONFFILE!
)

echo.


:: ---------------------------------------------------------
:: MODE AFTER UPLOAD
:: ---------------------------------------------------------
set "MODE="

echo What mode do you want to start after upload?
echo   1^) CPU only
echo   2^) GPU only
echo   3^) BOTH (combined)
echo   4^) Upload only (no restart)

set /p MODESEL="Choose 1-4: "

if "%MODESEL%"=="1" set "MODE=CPU"
if "%MODESEL%"=="2" set "MODE=GPU"
if "%MODESEL%"=="3" set "MODE=BOTH"
if "%MODESEL%"=="4" set "MODE=UPLOAD"

if not defined MODE (
    echo Invalid mode.
    goto :EndScript
)

set "_MODE=%MODE%"
echo.
echo Selected mode: %_MODE%
echo.


:: ---------------------------------------------------------
:: PROCESS ALL RIGS
:: ---------------------------------------------------------
echo ============================================
echo Updating rigs...
echo ============================================

for %%I in (%RIGS%) do call :HandleRig %%I
goto :EndScript


:: =========================================================
:: RIG HANDLER
:: =========================================================
:HandleRig
set "IP=%1"

echo.
echo --- Rig %IP% ---


:: -------------------------------------------------
:: CONFIG UPLOAD
:: -------------------------------------------------
if defined CONFFILE (
    echo Uploading %CONFFILE% as rig.conf...
    pscp -pw %PASS% "%CONFFILE%" %USER%@%IP%:/home/%USER%/rig.conf

    if errorlevel 1 (
        echo [FAIL] Config upload failed!
    ) else (
        echo [OK] Config uploaded.
    )
) else (
    echo Skipping config upload.
)

echo.


:: -------------------------------------------------
:: UPLOAD ONLY MODE (NO SERVICE CHANGES)
:: -------------------------------------------------
if /I "%_MODE%"=="UPLOAD" (
    echo Upload-only mode: No service changes.
    goto :eof
)


:: -------------------------------------------------
:: STOP ALL SERVICES
:: -------------------------------------------------
call :StopAllServices %IP%


:: -------------------------------------------------
:: START SERVICE MODE
:: -------------------------------------------------
if /I "%_MODE%"=="CPU"  call :StartCPU  %IP%
if /I "%_MODE%"=="GPU"  call :StartGPU  %IP%
if /I "%_MODE%"=="BOTH" call :StartBOTH %IP%

goto :eof



:: =========================================================
:: STOP ALL SERVICES
:: =========================================================
:StopAllServices
set "IP=%1"
echo Stopping ALL services on %IP%...

for %%S in (
    docker_events_cpu.service
    docker_events_gpu.service
    docker_events.service
) do (
    plink -batch -pw %PASS% %USER%@%IP% "sudo systemctl stop %%S || true"
    plink -batch -pw %PASS% %USER%@%IP% "sudo systemctl disable %%S || true"
)
echo.
goto :eof


:: =========================================================
:: START CPU SERVICE
:: =========================================================
:StartCPU
set "IP=%1"
echo Starting CPU service...

plink -batch -pw %PASS% %USER%@%IP% "sudo systemctl enable docker_events_cpu.service"
plink -batch -pw %PASS% %USER%@%IP% "sudo systemctl start docker_events_cpu.service"

call :CheckService %IP% docker_events_cpu.service CPU
goto :eof


:: =========================================================
:: START GPU SERVICE
:: =========================================================
:StartGPU
set "IP=%1"
echo Starting GPU service...

plink -batch -pw %PASS% %USER%@%IP% "sudo systemctl enable docker_events_gpu.service"
plink -batch -pw %PASS% %USER%@%IP% "sudo systemctl start docker_events_gpu.service"

call :CheckService %IP% docker_events_gpu.service GPU
goto :eof


:: =========================================================
:: START BOTH SERVICE
:: =========================================================
:StartBOTH
set "IP=%1"
echo Starting combined service...

plink -batch -pw %PASS% %USER%@%IP% "sudo systemctl enable docker_events.service"
plink -batch -pw %PASS% %USER%@%IP% "sudo systemctl start docker_events.service"

call :CheckService %IP% docker_events.service Combined
goto :eof


:: =========================================================
:: SERVICE STATUS CHECK
:: =========================================================
:CheckService
set "IP=%1"
set "SERVICE=%2"
set "LABEL=%3"

plink -batch -pw %PASS% %USER%@%IP% "systemctl is-active %SERVICE% | grep -q active"
if errorlevel 1 (
    echo [FAIL] %LABEL% service NOT running!
) else (
    echo [OK] %LABEL% service running.
)
echo.
goto :eof


:: ---------------------------------------------------------
:EndScript
echo.
echo Completed.
pause
endlocal
exit /b

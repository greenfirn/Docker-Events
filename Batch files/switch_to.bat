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
:: SELECT MODE
:: ---------------------------------------------------------
echo Choose service mode:
echo   1^) CPU only
echo   2^) GPU only
:: echo   3^) BOTH (combined)
echo   4^) Stop all services
echo.

set "MODE="
set /p MODESEL="Choose 1-4: "

if "%MODESEL%"=="1" set "MODE=CPU"
if "%MODESEL%"=="2" set "MODE=GPU"
:: if "%MODESEL%"=="3" set "MODE=BOTH"
if "%MODESEL%"=="4" set "MODE=STOP"

if not defined MODE (
    echo Invalid mode selected.
    goto EndScript
)

echo.
echo Selected mode: %MODE%
echo.

:: ---------------------------------------------------------
:: CONFIRMATION PROMPT
:: ---------------------------------------------------------
set "CONFIRM="
set /p CONFIRM="Continue with mode '%MODE%'? (y/n): "

if /I not "%CONFIRM%"=="y" (
    echo Operation cancelled.
    goto EndScript
)

echo.
echo Proceeding with mode: %MODE%
echo.


:: ---------------------------------------------------------
:: PROCESS ALL RIGS
:: ---------------------------------------------------------
echo ============================================
echo Switching modes on all rigs...
echo ============================================

for %%I in (%RIGS%) do call :HandleRig %%I
goto EndScript


:: =========================================================
:: RIG HANDLER
:: =========================================================
:HandleRig
set "IP=%1"
echo.
echo --- Rig %IP% ---

call :StopAll %IP%

if "%MODE%"=="CPU"  call :StartCPU  %IP%
if "%MODE%"=="GPU"  call :StartGPU  %IP%
if "%MODE%"=="BOTH" call :StartBOTH %IP%
if "%MODE%"=="STOP" echo All services stopped on %IP%.

goto :eof


:: =========================================================
:: STOP ALL SERVICES
:: =========================================================
:StopAll
set "IP=%1"
echo Stopping all services on %IP%...

for %%S in (
    docker_events_cpu.service
    docker_events_gpu.service
    docker_events.service
) do (
    plink -batch -pw %PASS% %USER%@%IP% "sudo systemctl stop %%S || true"
    plink -batch -pw %PASS% %USER%@%IP% "sudo systemctl disable %%S || true"
)
goto :eof


:: =========================================================
:: START CPU SERVICE
:: =========================================================
:StartCPU
set "IP=%1"
echo Starting CPU service...

plink -batch -pw %PASS% %USER%@%IP% "sudo systemctl enable docker_events_cpu.service"
plink -batch -pw %PASS% %USER%@%IP% "sudo systemctl start docker_events_cpu.service"

call :Check %IP% docker_events_cpu.service CPU
goto :eof


:: =========================================================
:: START GPU SERVICE
:: =========================================================
:StartGPU
set "IP=%1"
echo Starting GPU service...

plink -batch -pw %PASS% %USER%@%IP% "sudo systemctl enable docker_events_gpu.service"
plink -batch -pw %PASS% %USER%@%IP% "sudo systemctl start docker_events_gpu.service"

call :Check %IP% docker_events_gpu.service GPU
goto :eof


:: =========================================================
:: START BOTH SERVICE
:: =========================================================
:StartBOTH
set "IP=%1"
echo Starting combined service...

plink -batch -pw %PASS% %USER%@%IP% "sudo systemctl enable docker_events.service"
plink -batch -pw %PASS% %USER%@%IP% "sudo systemctl start docker_events.service"

call :Check %IP% docker_events.service BOTH
goto :eof


:: =========================================================
:: CHECK SERVICE STATUS
:: =========================================================
:Check
set "IP=%1"
set "SERVICE=%2"
set "LABEL=%3"

plink -batch -pw %PASS% %USER%@%IP% "systemctl is-active %SERVICE% | grep -q active"
if errorlevel 1 (
    echo [FAIL] %LABEL% NOT running on %IP%.
) else (
    echo [OK] %LABEL% running on %IP%.
)
goto :eof


:EndScript
echo.
echo Done.
pause
endlocal
exit /b

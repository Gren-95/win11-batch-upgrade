@echo off
setlocal EnableDelayedExpansion

rem ============================================================
rem  Windows 11 batch upgrade
rem
rem  Needs these three files in the same folder as this BAT file:
rem    PsExec64.exe, Windows11InstallationAssistant.exe,
rem    WindowsPCHealthCheckSetup.msi
rem
rem  Asks at the start what should happen on each PC:
rem    1) Force restart: the PC restarts by itself when ready.
rem    2) User restarts: asks the Installation Assistant not to
rem       restart. Its switches are undocumented, so try this on
rem       one PC first: it may still restart by itself.
rem
rem  Computer names can be given in three ways (first match wins):
rem    1) As arguments:      Win11_Batch_Upgrade.bat PC01 PC02 PC03
rem    2) In computers.txt   (same folder, one name per line, # = comment)
rem    3) Typed at the prompt, separated by spaces
rem ============================================================

set "SRC=%~dp0Windows11InstallationAssistant.exe"
set "HC=%~dp0WindowsPCHealthCheckSetup.msi"
set "PSEXEC=%~dp0PsExec64.exe"
set "LIST=%~dp0computers.txt"
set "LOG=%~dp0Win11Upgrade_results.log"
set "OKFILE=%TEMP%\win11_ok_%RANDOM%.tmp"
set "FAILFILE=%TEMP%\win11_fail_%RANDOM%.tmp"

rem ---- Check all required files, and say where to get the missing ones ----
set "MISSING="
if not exist "%PSEXEC%" set "MISSING=!MISSING! PsExec64.exe,"
if not exist "%SRC%" set "MISSING=!MISSING! Windows11InstallationAssistant.exe,"
if not exist "%HC%" set "MISSING=!MISSING! WindowsPCHealthCheckSetup.msi,"
if not defined MISSING goto :ChooseMode

echo.
echo  %MISSING:~1,-1% not detected.
echo  Please download from here and place in the same folder as this BAT file:
echo.
if not exist "%PSEXEC%" echo    PsExec64.exe: https://download.sysinternals.com/files/PSTools.zip - take it out of the zip
if not exist "%SRC%" echo    Windows11InstallationAssistant.exe: https://www.microsoft.com/software-download/windows11
if not exist "%HC%" echo    WindowsPCHealthCheckSetup.msi: https://aka.ms/GetPCHealthCheckApp
echo.
pause
endlocal
exit /b 1

:ChooseMode
rem ---- Choose what happens on each PC ----
echo.
echo  What should happen on each PC?
echo    1 = Force restart: PC restarts by itself when ready
echo    2 = User restarts: upgrade finishes on the next restart. Try on one PC first
echo.
choice /c 12 /n /m "Choose 1 or 2: "
set "MODE=%errorlevel%"
if not "%MODE%"=="1" if not "%MODE%"=="2" exit /b 1

set "ARGS=/QuietInstall /SkipEULA /AutoUpgrade /NoRestartUI"
if "%MODE%"=="2" set "ARGS=%ARGS% /NoReboot"

rem ---- Build the list of computers ----
set "PCS="
if not "%~1"=="" (
    set "PCS=%*"
) else if exist "%LIST%" (
    echo Reading computer names from computers.txt...
    for /f "usebackq eol=# tokens=*" %%A in ("%LIST%") do set "PCS=!PCS! %%A"
) else (
    set /p "PCS=Enter computer names separated by spaces: "
)

if "%PCS%"=="" (
    echo No computer names given.
    pause
    exit /b 1
)

set /a OK=0, FAIL=0
type nul > "%OKFILE%"
type nul > "%FAILFILE%"

echo.>> "%LOG%"
echo ===== Run started %DATE% %TIME% - option %MODE% =====>> "%LOG%"

for %%P in (%PCS%) do call :ProcessPC %%P

rem ---- Summary ----
echo.
echo ============================================================
echo  SUMMARY
echo ============================================================
echo.
echo  SUCCEEDED (%OK%):
type "%OKFILE%"
echo.
echo  FAILED (%FAIL%):
type "%FAILFILE%"
echo.
echo  Full log: %LOG%
echo ============================================================

del "%OKFILE%" "%FAILFILE%" >nul 2>&1
pause
endlocal
exit /b 0


rem ============================================================
:ProcessPC
set "PC=%~1"
echo.
echo ------------------------------------------------------------
echo [%PC%]

rem -- Reachability check (skips offline PCs quickly) --
ping -n 1 -w 1500 %PC% | find "TTL=" >nul
if errorlevel 1 (
    call :Fail "%PC%" "Offline or not reachable"
    goto :eof
)

rem -- PC Health Check: copy + silent install --
rem    A failure here is only a warning; the upgrade still runs.
set "HCNOTE="
echo Copying PC Health Check installer...
copy /Y "%HC%" "\\%PC%\c$\WindowsPCHealthCheckSetup.msi" >nul 2>&1
if errorlevel 1 (
    set "HCNOTE=Health Check copy failed"
) else (
    echo Installing PC Health Check...
    "%PSEXEC%" \\%PC% -accepteula -nobanner -h -s msiexec /i "C:\WindowsPCHealthCheckSetup.msi" /qn /norestart
    call :CheckMsi !errorlevel!
)
if defined HCNOTE (
    echo WARNING: !HCNOTE!
    echo [WARN] %PC% - !HCNOTE!>> "%LOG%"
)

rem -- Copy installer --
echo Copying Windows 11 Installation Assistant...
copy /Y "%SRC%" "\\%PC%\c$\Windows11InstallationAssistant.exe" >nul 2>&1
if errorlevel 1 (
    call :Fail "%PC%" "Copy failed - no access to \\%PC%\c$"
    goto :eof
)

rem -- Start upgrade --
echo Starting Windows 11 upgrade...
"%PSEXEC%" \\%PC% -accepteula -nobanner -h -s cmd /c "C:\Windows11InstallationAssistant.exe %ARGS%"
set "RC=%errorlevel%"
if not "%RC%"=="0" (
    call :Fail "%PC%" "PsExec failed - exit code %RC%"
    goto :eof
)

call :Success "%PC%"
goto :eof


:CheckMsi
rem 0 = installed, 3010/1641 = installed (reboot needed), 1638 = already installed
set "MRC=%~1"
if "%MRC%"=="0" goto :eof
if "%MRC%"=="3010" goto :eof
if "%MRC%"=="1641" goto :eof
if "%MRC%"=="1638" goto :eof
set "HCNOTE=Health Check install failed - msiexec code %MRC%"
goto :eof


:Success
set /a OK+=1
echo SUCCESS: %~1
if defined HCNOTE (
    echo    %~1  ^(upgrade started, but !HCNOTE!^)>> "%OKFILE%"
    echo [OK]   %~1 - upgrade started, !HCNOTE!>> "%LOG%"
) else (
    echo    %~1  ^(Health Check installed, upgrade started^)>> "%OKFILE%"
    echo [OK]   %~1 - Health Check installed, upgrade started>> "%LOG%"
)
goto :eof


:Fail
set /a FAIL+=1
echo FAILED: %~1 - %~2
echo    %~1  ^(%~2^)>> "%FAILFILE%"
echo [FAIL] %~1 - %~2>> "%LOG%"
goto :eof

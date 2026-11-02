@echo off
setlocal EnableDelayedExpansion

rem ============================================================
rem  Windows 11 batch upgrade
rem
rem  Needs these three files in the same folder as this BAT file:
rem    PsExec64.exe, Windows11InstallationAssistant.exe,
rem    WindowsPCHealthCheckSetup.msi
rem
rem  Asks at the start what to do on each PC:
rem    1) Force restart: the PC restarts by itself when ready.
rem    2) User restarts: asks the Installation Assistant not to
rem       restart. Its switches are undocumented, so try this on
rem       one PC first: it may still restart by itself.
rem    3) Check status: changes nothing, shows how far each PC is.
rem
rem  Computer names can be given in three ways (first match wins):
rem    1) As arguments:      Win11_Batch_Upgrade.bat PC01 PC02 PC03
rem    2) In computers.txt   (same folder, one name per line, # = comment)
rem    3) Typed at the prompt, separated by spaces
rem ============================================================

rem ---- Settings you may want to change ----
rem Don't use double quotes or exclamation marks in the messages.
set "MINFREEGB=30"
set "MSG1=Windows 11 is installing on this PC. It will restart by itself when ready, possibly without another warning. Please save your work often."
set "MSG2=Windows 11 is installing in the background. Keep working and leave the PC on. The upgrade finishes the next time you restart. Please save your work often."

set "SRC=%~dp0Windows11InstallationAssistant.exe"
set "HC=%~dp0WindowsPCHealthCheckSetup.msi"
set "PSEXEC=%~dp0PsExec64.exe"
set "LIST=%~dp0computers.txt"
set "LOG=%~dp0Win11Upgrade_results.log"
set "OKFILE=%TEMP%\win11_ok_%RANDOM%.tmp"
set "FAILFILE=%TEMP%\win11_fail_%RANDOM%.tmp"
set "SKIPFILE=%TEMP%\win11_skip_%RANDOM%.tmp"
set "INFOFILE=%TEMP%\win11_info_%RANDOM%.tmp"

rem -n = give up after this many seconds if a PC won't connect
set "PSFLAGS=-accepteula -nobanner -n 15 -h -s"

rem Prints the word CHECK, then free GB on C:, then 1 or 0 for TPM 2.0, then 1 or 0 for UEFI
rem A check that can't run counts as passed: it must not block a good PC.
set "PSCHECK=$g=[math]::Floor((Get-PSDrive C).Free/1GB);$t=1;try{$v=(Get-CimInstance -Namespace root/cimv2/Security/MicrosoftTpm -ClassName Win32_Tpm -ErrorAction Stop).SpecVersion;if($v -notlike '2.0*'){$t=0}}catch{};$u=1;try{$null=Confirm-SecureBootUEFI -ErrorAction Stop}catch [System.PlatformNotSupportedException]{$u=0}catch{};Write-Output ('CHECK '+$g+' '+$t+' '+$u)"

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
rem ---- Choose what to do on each PC ----
echo.
echo  What should happen on each PC?
echo    1 = Force restart: PC restarts by itself when ready
echo    2 = User restarts: upgrade finishes on the next restart. Try on one PC first
echo    3 = Check status: changes nothing, shows how far each PC is
echo.
choice /c 123 /n /m "Choose 1, 2 or 3: "
set "MODE=%errorlevel%"
if not "%MODE%"=="1" if not "%MODE%"=="2" if not "%MODE%"=="3" exit /b 1

set "ARGS=/QuietInstall /SkipEULA /AutoUpgrade /NoRestartUI"
set "MSGTEXT=%MSG1%"
set "CONFIRM=the PCs will restart by themselves"
if not "%MODE%"=="2" goto :BuildList
set "ARGS=%ARGS% /NoReboot"
set "MSGTEXT=%MSG2%"
set "CONFIRM=users restart them, but a PC may still restart by itself"

:BuildList
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

if "%MODE%"=="3" goto :RunStatus

rem ---- Confirm before touching any PC ----
set /a COUNT=0
for %%P in (%PCS%) do set /a COUNT+=1
echo.
echo  Computers: %PCS%
echo.
choice /c YN /n /m "About to upgrade %COUNT% PC(s), %CONFIRM%. Continue? [Y/N] "
set "ANSWER=%errorlevel%"
if not "%ANSWER%"=="1" (
    echo Cancelled, nothing was changed.
    pause
    endlocal
    exit /b 0
)

set /a OK=0, FAIL=0, SKIP=0
type nul > "%OKFILE%"
type nul > "%FAILFILE%"
type nul > "%SKIPFILE%"

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
echo  SKIPPED (%SKIP%):
type "%SKIPFILE%"
echo.
echo  FAILED (%FAIL%):
type "%FAILFILE%"
echo.
echo  Full log: %LOG%
echo  Run this again and pick 3 to see how far each PC is.
echo ============================================================

del "%OKFILE%" "%FAILFILE%" "%SKIPFILE%" >nul 2>&1
pause
endlocal
exit /b 0


:RunStatus
echo.
for %%P in (%PCS%) do call :StatusPC %%P
echo.
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

rem -- Skip PCs that are already done or busy --
echo Checking Windows version...
call :GetBuild
if "%BUILD%"=="" (
    call :Fail "%PC%" "PsExec could not connect or read the Windows version"
    goto :eof
)
if %BUILD% GEQ 22000 (
    call :Skip "%PC%" "Already Windows 11, build %BUILD%"
    goto :eof
)
call :IsRunning
if "%RUNNING%"=="1" (
    call :Skip "%PC%" "Installation Assistant is already running"
    goto :eof
)

rem -- Disk space and hardware --
echo Checking disk space and hardware...
call :GetHardware
if "%FREEGB%"=="" goto :HardwareUnknown
if %FREEGB% LSS %MINFREEGB% (
    call :Fail "%PC%" "Only %FREEGB% GB free on C:, want at least %MINFREEGB% GB"
    goto :eof
)
if "%TPMOK%"=="0" (
    call :Fail "%PC%" "TPM 2.0 not found"
    goto :eof
)
if "%UEFIOK%"=="0" (
    call :Fail "%PC%" "PC starts in legacy BIOS mode, Windows 11 needs UEFI"
    goto :eof
)
goto :HealthCheck

:HardwareUnknown
echo WARNING: Could not check disk space and hardware, continuing anyway.
>> "%LOG%" echo [WARN] %PC% - could not check disk space and hardware

:HealthCheck
rem -- PC Health Check: copy + silent install --
rem    A failure here is only a warning; the upgrade still runs.
set "HCNOTE="
echo Copying PC Health Check installer...
copy /Y "%HC%" "\\%PC%\c$\WindowsPCHealthCheckSetup.msi" >nul 2>&1
if errorlevel 1 (
    set "HCNOTE=Health Check copy failed"
) else (
    echo Installing PC Health Check...
    "%PSEXEC%" \\%PC% %PSFLAGS% msiexec /i "C:\WindowsPCHealthCheckSetup.msi" /qn /norestart
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

rem -- Tell the logged-on user. Only a note if it fails, e.g. nobody is logged on. --
echo Sending message to the logged-on user...
"%PSEXEC%" \\%PC% %PSFLAGS% msg * /time:3600 "%MSGTEXT%" >nul 2>&1 <nul
if errorlevel 1 (
    echo NOTE: Message not delivered, maybe nobody is logged on.
    >> "%LOG%" echo [NOTE] %PC% - message not delivered, maybe nobody is logged on
)

rem -- Start upgrade --
echo Starting Windows 11 upgrade...
"%PSEXEC%" \\%PC% %PSFLAGS% cmd /c "C:\Windows11InstallationAssistant.exe %ARGS%"
set "RC=%errorlevel%"
if not "%RC%"=="0" (
    call :Fail "%PC%" "PsExec failed - exit code %RC%"
    goto :eof
)

call :Success "%PC%"
goto :eof


:StatusPC
set "PC=%~1"
ping -n 1 -w 1500 %PC% | find "TTL=" >nul
if errorlevel 1 (
    echo    %PC%  OFFLINE
    goto :eof
)
call :GetBuild
if "%BUILD%"=="" (
    echo    %PC%  NO CONNECTION - PsExec could not read the Windows version
    goto :eof
)
if %BUILD% GEQ 22000 (
    echo    %PC%  WINDOWS 11 - build %BUILD%
    goto :eof
)
call :IsRunning
if "%RUNNING%"=="1" (
    echo    %PC%  INSTALLING - build %BUILD%, Installation Assistant is running
    goto :eof
)
if exist "\\%PC%\c$\$WINDOWS.~BT\" (
    echo    %PC%  WAITING FOR RESTART, OR FAILED - build %BUILD%, setup files are on C:
    goto :eof
)
echo    %PC%  NOT STARTED, OR FAILED - build %BUILD%, no setup files on C:
goto :eof


:GetBuild
rem Sets BUILD to the Windows build number, empty if it can't be read
set "BUILD="
"%PSEXEC%" \\%PC% %PSFLAGS% reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" /v CurrentBuild > "%INFOFILE%" 2>nul <nul
for /f "usebackq tokens=1,3" %%A in ("%INFOFILE%") do if /i "%%A"=="CurrentBuild" set "BUILD=%%B"
del "%INFOFILE%" >nul 2>&1
goto :eof


:IsRunning
rem Sets RUNNING to 1 if the Installation Assistant's process is running
set "RUNNING=0"
"%PSEXEC%" \\%PC% %PSFLAGS% tasklist /nh /fi "imagename eq Windows10UpgraderApp.exe" 2>nul <nul | find /i "Windows10UpgraderApp" >nul
if not errorlevel 1 set "RUNNING=1"
goto :eof


:GetHardware
rem Sets FREEGB, TPMOK and UEFIOK. FREEGB stays empty if the check couldn't run.
set "FREEGB="
set "TPMOK="
set "UEFIOK="
"%PSEXEC%" \\%PC% %PSFLAGS% powershell -NoProfile -NonInteractive -InputFormat None -Command "%PSCHECK%" > "%INFOFILE%" 2>nul <nul
for /f "usebackq tokens=1-4" %%A in ("%INFOFILE%") do if "%%A"=="CHECK" (
    set "FREEGB=%%B"
    set "TPMOK=%%C"
    set "UEFIOK=%%D"
)
del "%INFOFILE%" >nul 2>&1
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


:Skip
set /a SKIP+=1
echo SKIPPED: %~1 - %~2
>> "%SKIPFILE%" echo    %~1  ^(%~2^)
>> "%LOG%" echo [SKIP] %~1 - %~2
goto :eof


:Fail
rem The redirect goes first: "code 5>> file" would redirect handle 5 and lose the line.
set /a FAIL+=1
echo FAILED: %~1 - %~2
>> "%FAILFILE%" echo    %~1  ^(%~2^)
>> "%LOG%" echo [FAIL] %~1 - %~2
goto :eof

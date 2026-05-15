@echo off
set "LOCAL_VERSION=9.3.0"
chcp 65001 >nul

:: External commands for use in bat files
if "%~1"=="enable_tcp_timestamps" (
    netsh interface tcp set global timestamps=enabled >nul 2>&1
    exit /b
)

if "%~1"=="load_game_filter" (
    call :game_switch_status
    exit /b
)

if "%~1"=="status_zapret" (
    call :test_service zapret soft
    call :tcp_enable
    exit /b
)

:: Check if admin
if "%1"=="admin" (
    echo Started with admin rights
) else (
    call :check_extracted
    echo Requesting admin rights...
    powershell -Command "Start-Process 'cmd.exe' -ArgumentList '/c \"\"%~f0\" admin\"' -Verb RunAs" 2>nul || (
        echo PowerShell not available, trying VBS elevation...
        cscript //nologo "%~dp0bin\tools\elevator.vbs" "%~f0" admin
    )
    exit
)

:: MENU
setlocal EnableDelayedExpansion
:menu
cls
call :game_switch_status

set "menu_choice=null"
echo =========  DiscordFix v%LOCAL_VERSION%  =========
echo:
echo 1. Install as Service
echo 2. Remove Services
echo 3. Check Status
echo 4. Run Diagnostics
echo 5. Switch Game Filter (%GameFilterStatus%)
echo 6. Clear Discord Cache
echo 7. Update IP Lists
echo 0. Exit
echo:
set /p menu_choice=Enter choice (0-7): 

if "%menu_choice%"=="1" goto service_install
if "%menu_choice%"=="2" goto service_remove
if "%menu_choice%"=="3" goto service_status
if "%menu_choice%"=="4" goto service_diagnostics
if "%menu_choice%"=="5" goto game_switch
if "%menu_choice%"=="6" goto clear_discord_cache
if "%menu_choice%"=="7" goto update_ipset
if "%menu_choice%"=="0" exit /b
goto menu


:: TCP ENABLE
:tcp_enable
netsh interface tcp show global | findstr /i "timestamps" | findstr /i "enabled" > nul || netsh interface tcp set global timestamps=enabled > nul 2>&1
exit /b


:: STATUS
:service_status
cls
chcp 437 > nul

sc query "zapret" >nul 2>&1
if !errorlevel!==0 (
    for /f "tokens=2*" %%A in ('reg query "HKLM\System\CurrentControlSet\Services\zapret" /v zapret-discordfix 2^>nul') do echo Service strategy installed from "%%B"
)

call :test_service zapret
call :test_service WinDivert

set "BIN_PATH=%~dp0bin\"
if not exist "%BIN_PATH%\*.sys" (
    call :PrintRed "WinDivert64.sys file NOT found."
)
echo:

tasklist /FI "IMAGENAME eq winws.exe" | find /I "winws.exe" > nul
if !errorlevel!==0 (
    call :PrintGreen "Bypass (winws.exe) is RUNNING."
) else (
    call :PrintRed "Bypass (winws.exe) is NOT running."
)

pause
goto menu

:test_service
set "ServiceName=%~1"
set "ServiceStatus="

for /f "tokens=3 delims=: " %%A in ('sc query "%ServiceName%" ^| findstr /i "STATE"') do set "ServiceStatus=%%A"
set "ServiceStatus=%ServiceStatus: =%"

if "%ServiceStatus%"=="RUNNING" (
    if "%~2"=="soft" (
        echo "%ServiceName%" is ALREADY RUNNING as service. Use "service.bat" and choose "Remove Services" first if you want to run standalone bat.
        pause
        exit /b
    ) else (
        echo "%ServiceName%" service is RUNNING.
    )
) else if "%ServiceStatus%"=="STOP_PENDING" (
    call :PrintYellow "!ServiceName! is STOP_PENDING. Run Diagnostics to try to fix conflicts"
) else if not "%~2"=="soft" (
    echo "%ServiceName%" service is NOT running.
)

exit /b


:: REMOVE
:service_remove
cls
chcp 65001 > nul

set SRVCNAME=zapret
sc query "!SRVCNAME!" >nul 2>&1
if !errorlevel!==0 (
    net stop %SRVCNAME%
    sc delete %SRVCNAME%
) else (
    echo Service "%SRVCNAME%" is not installed.
)

tasklist /FI "IMAGENAME eq winws.exe" | find /I "winws.exe" > nul
if !errorlevel!==0 (
    taskkill /IM winws.exe /F > nul
)

sc query "WinDivert" >nul 2>&1
if !errorlevel!==0 (
    net stop "WinDivert"
    sc query "WinDivert" >nul 2>&1
    if !errorlevel!==0 (
        sc delete "WinDivert"
    )
)
net stop "WinDivert14" >nul 2>&1
sc delete "WinDivert14" >nul 2>&1

pause
goto menu


:: INSTALL
:service_install
cls
chcp 65001 > nul

cd /d "%~dp0"
set "BIN_PATH=%~dp0bin\"
set "LISTS_PATH=%~dp0lists\"

:: Search for .bat files in pre-configs
echo Pick one of the configurations:
set "count=0"
for %%f in (pre-configs\*.bat) do (
    set "filename=%%~nxf"
    if /i not "!filename:~0,7!"=="service" (
        set /a count+=1
        echo !count!. %%~nf
        set "file!count!=%%f"
    )
)

:: Choose file
set "choice="
set /p "choice=Input configuration number: "
if "!choice!"=="" goto :eof

set "selectedFile=!file%choice%!"
if not defined selectedFile (
    echo Invalid choice, exiting...
    pause
    goto menu
)

:: Parse args
set "args="
set "capture=0"
set "mergeargs=0"
set QUOTE="

for /f "tokens=*" %%a in ('type "!selectedFile!"') do (
    set "line=%%a"
    call set "line=%%line:^!=EXCL_MARK%%"

    echo !line! | findstr /i "winws.exe" >nul
    if not errorlevel 1 (
        set "capture=1"
    )

    if !capture!==1 (
        if not defined args (
            set "line=!line:*winws.exe"=!"
        )

        set "temp_args="
        for %%i in (!line!) do (
            set "arg=%%i"

            if not "!arg!"=="^" (
                if "!arg:~0,2!" EQU "--" if not !mergeargs!==0 (
                    set "mergeargs=0"
                )

                if "!arg:~0,1!" EQU "!QUOTE!" (
                    set "arg=!arg:~1,-1!"

                    echo !arg! | findstr ":" >nul
                    if !errorlevel!==0 (
                        set "arg=\!QUOTE!!arg!\!QUOTE!"
                    ) else if "!arg:~0,1!"=="@" (
                        set "arg=\!QUOTE!@%~dp0!arg:~1!\!QUOTE!"
                    ) else if "!arg:~0,5!"=="%%BIN%%" (
                        set "arg=\!QUOTE!!BIN_PATH!!arg:~5!\!QUOTE!"
                    ) else if "!arg:~0,7!"=="%%LISTS%%" (
                        set "arg=\!QUOTE!!LISTS_PATH!!arg:~7!\!QUOTE!"
                    ) else (
                        set "arg=\!QUOTE!%~dp0!arg!\!QUOTE!"
                    )
                ) else if "!arg:~0,12!" EQU "%%GModeRange%%" (
                    set "arg=%GModeRange%"
                )

                if !mergeargs!==1 (
                    set "temp_args=!temp_args!,!arg!"
                ) else if !mergeargs!==3 (
                    set "temp_args=!temp_args!=!arg!"
                    set "mergeargs=1"
                ) else (
                    set "temp_args=!temp_args! !arg!"
                )

                if "!arg:~0,2!" EQU "--" (
                    set "mergeargs=2"
                ) else if !mergeargs! GEQ 1 (
                    if !mergeargs!==2 set "mergeargs=1"
                )
            )
        )

        if not "!temp_args!"=="" (
            set "args=!args! !temp_args!"
        )
    )
)

:: Create service
call :tcp_enable

set ARGS=%args%
call set "ARGS=%%ARGS:EXCL_MARK=^!%%"
echo Final args: !ARGS!
set SRVCNAME=zapret

net stop %SRVCNAME% >nul 2>&1
sc delete %SRVCNAME% >nul 2>&1
sc create %SRVCNAME% binPath= "\"%BIN_PATH%winws.exe\" !ARGS!" DisplayName= "zapret" start= auto
sc description %SRVCNAME% "Zapret DPI bypass (DiscordFix)"
sc start %SRVCNAME%
for %%F in ("!file%choice%!") do (
    set "filename=%%~nF"
)
reg add "HKLM\System\CurrentControlSet\Services\zapret" /v zapret-discordfix /t REG_SZ /d "!filename!" /f

pause
goto menu


:: DIAGNOSTICS
:service_diagnostics
cls
chcp 65001 > nul

echo Running diagnostics...
echo:

:: Check WinDivert driver
sc query "WinDivert" >nul 2>&1
if !errorlevel!==0 (
    call :PrintYellow "WinDivert service exists, attempting cleanup..."
    net stop "WinDivert" >nul 2>&1
    sc delete "WinDivert" >nul 2>&1
    if !errorlevel!==0 (
        call :PrintGreen "WinDivert successfully removed"
    ) else (
        call :PrintRed "Failed to remove WinDivert"
    )
)

:: Check for conflicting services
set "conflicting_services=GoodbyeDPI discordfix_zapret winws1 winws2"
set "found_conflicts="

for %%s in (!conflicting_services!) do (
    sc query "%%s" >nul 2>&1
    if !errorlevel!==0 (
        if "!found_conflicts!"=="" (
            set "found_conflicts=%%s"
        ) else (
            set "found_conflicts=!found_conflicts! %%s"
        )
    )
)

if not "!found_conflicts!"=="" (
    call :PrintRed "Conflicting services found: !found_conflicts!"
    
    set "CHOICE="
    set /p "CHOICE=Remove conflicting services? (Y/N, default: N) "
    if "!CHOICE!"=="" set "CHOICE=N"
    if /i "!CHOICE!"=="Y" (
        for %%s in (!found_conflicts!) do (
            call :PrintYellow "Removing service: %%s"
            net stop "%%s" >nul 2>&1
            sc delete "%%s" >nul 2>&1
        )
        net stop "WinDivert" >nul 2>&1
        sc delete "WinDivert" >nul 2>&1
    )
) else (
    call :PrintGreen "No conflicting services found"
)

echo:
pause
goto menu


:: GAME FILTER
:game_switch_status
chcp 437 > nul

set "gameFlagFile=%~dp0bin\gmode.flag"

if exist "%gameFlagFile%" (
    set "GameFilterStatus=enabled"
    set "GModeRange=1024-65535"
) else (
    set "GameFilterStatus=disabled"
    set "GModeRange=12"
)
exit /b


:game_switch
chcp 437 > nul
cls

set "gameFlagFile=%~dp0bin\gmode.flag"

if not exist "%gameFlagFile%" (
    echo Enabling game filter...
    echo ENABLED > "%gameFlagFile%"
    call :PrintYellow "Restart zapret to apply changes"
) else (
    echo Disabling game filter...
    del /f /q "%gameFlagFile%"
    call :PrintYellow "Restart zapret to apply changes"
)

pause
goto menu


:: DISCORD CACHE
:clear_discord_cache
cls
chcp 65001 > nul

tasklist /FI "IMAGENAME eq Discord.exe" | findstr /I "Discord.exe" > nul
if !errorlevel!==0 (
    echo Discord is running, closing...
    taskkill /IM Discord.exe /F > nul
    if !errorlevel! == 0 (
        call :PrintGreen "Discord was successfully closed"
    ) else (
        call :PrintRed "Unable to close Discord"
    )
)

set "discordCacheDir=%appdata%\discord"

for %%d in ("Cache" "Code Cache" "GPUCache") do (
    set "dirPath=!discordCacheDir!\%%~d"
    if exist "!dirPath!" (
        rd /s /q "!dirPath!"
        if !errorlevel!==0 (
            call :PrintGreen "Deleted !dirPath!"
        ) else (
            call :PrintRed "Failed to delete !dirPath!"
        )
    ) else (
        echo %%~d not found, skipping...
    )
)

echo:
pause
goto menu


:: UPDATE IPSET
:update_ipset
cls
chcp 65001 > nul

set "LISTS_PATH=%~dp0lists\"

echo ========================================
echo    Update IP Lists (antifilter.download)
echo ========================================
echo:
echo Sources:
echo   1. ipsum.lst - aggregated IPs (recommended)
echo   2. ip.lst - all blocked IPs
echo   3. allyouneed.lst - IPs + subnets
echo   4. Update all lists
echo   0. Back to menu
echo:
set /p "ipset_choice=Choose source (0-4): "

if "!ipset_choice!"=="0" goto menu
if "!ipset_choice!"=="1" (
    set "IPSET_URL=https://antifilter.download/list/ipsum.lst"
    set "IPSET_FILE=ipset-russia.txt"
    goto do_download
)
if "!ipset_choice!"=="2" (
    set "IPSET_URL=https://antifilter.download/list/ip.lst"
    set "IPSET_FILE=ipset-russia.txt"
    goto do_download
)
if "!ipset_choice!"=="3" (
    set "IPSET_URL=https://antifilter.download/list/allyouneed.lst"
    set "IPSET_FILE=ipset-russia.txt"
    goto do_download
)
if "!ipset_choice!"=="4" goto do_download_all

goto update_ipset

:do_download
echo:
echo Downloading from !IPSET_URL!...

powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; try { Invoke-WebRequest -Uri '!IPSET_URL!' -OutFile '!LISTS_PATH!!IPSET_FILE!.new' -UseBasicParsing -TimeoutSec 30 } catch { exit 1 }"

if !errorlevel!==0 (
    for %%A in ("!LISTS_PATH!!IPSET_FILE!.new") do set "filesize=%%~zA"
    if !filesize! GTR 1000 (
        move /y "!LISTS_PATH!!IPSET_FILE!.new" "!LISTS_PATH!!IPSET_FILE!" > nul
        call :PrintGreen "Updated !IPSET_FILE! (!filesize! bytes)"
        
        for /f %%L in ('find /c /v "" ^< "!LISTS_PATH!!IPSET_FILE!"') do set "linecount=%%L"
        echo Total IPs: !linecount!
    ) else (
        del /f /q "!LISTS_PATH!!IPSET_FILE!.new" 2>nul
        call :PrintRed "Downloaded file too small, keeping old list"
    )
) else (
    del /f /q "!LISTS_PATH!!IPSET_FILE!.new" 2>nul
    call :PrintRed "Download failed, keeping old list"
)

echo:
pause
goto menu

:do_download_all
echo:
echo Downloading all IP lists...
echo:

:: ipsum (aggregated)
echo [1/3] Downloading ipsum.lst...
powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; try { Invoke-WebRequest -Uri 'https://antifilter.download/list/ipsum.lst' -OutFile '!LISTS_PATH!ipset-russia.txt.new' -UseBasicParsing -TimeoutSec 30 } catch { exit 1 }"
if !errorlevel!==0 (
    for %%A in ("!LISTS_PATH!ipset-russia.txt.new") do set "filesize=%%~zA"
    if !filesize! GTR 1000 (
        move /y "!LISTS_PATH!ipset-russia.txt.new" "!LISTS_PATH!ipset-russia.txt" > nul
        call :PrintGreen "Updated ipset-russia.txt"
    ) else (
        del /f /q "!LISTS_PATH!ipset-russia.txt.new" 2>nul
        call :PrintYellow "ipsum.lst too small, skipped"
    )
) else (
    del /f /q "!LISTS_PATH!ipset-russia.txt.new" 2>nul
    call :PrintRed "Failed to download ipsum.lst"
)

:: discord IPs
echo [2/3] Downloading Discord IPs...
powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; try { Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/nickspaargaren/no-google/master/categories/discord.txt' -OutFile '!LISTS_PATH!ipset-discord.txt.new' -UseBasicParsing -TimeoutSec 30 } catch { exit 1 }"
if !errorlevel!==0 (
    for %%A in ("!LISTS_PATH!ipset-discord.txt.new") do set "filesize=%%~zA"
    if !filesize! GTR 100 (
        move /y "!LISTS_PATH!ipset-discord.txt.new" "!LISTS_PATH!ipset-discord.txt" > nul
        call :PrintGreen "Updated ipset-discord.txt"
    ) else (
        del /f /q "!LISTS_PATH!ipset-discord.txt.new" 2>nul
        call :PrintYellow "Discord IPs too small, skipped"
    )
) else (
    del /f /q "!LISTS_PATH!ipset-discord.txt.new" 2>nul
    call :PrintYellow "Discord IPs not updated (optional)"
)

:: community hostlist
echo [3/3] Downloading community hostlist...
powershell -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; try { Invoke-WebRequest -Uri 'https://antifilter.download/list/domains.lst' -OutFile '!LISTS_PATH!list-community.txt.new' -UseBasicParsing -TimeoutSec 30 } catch { exit 1 }"
if !errorlevel!==0 (
    for %%A in ("!LISTS_PATH!list-community.txt.new") do set "filesize=%%~zA"
    if !filesize! GTR 1000 (
        move /y "!LISTS_PATH!list-community.txt.new" "!LISTS_PATH!list-community.txt" > nul
        call :PrintGreen "Updated list-community.txt"
    ) else (
        del /f /q "!LISTS_PATH!list-community.txt.new" 2>nul
        call :PrintYellow "Community hostlist too small, skipped"
    )
) else (
    del /f /q "!LISTS_PATH!list-community.txt.new" 2>nul
    call :PrintYellow "Community hostlist not updated (optional)"
)

echo:
call :PrintGreen "IP lists update complete!"
call :PrintYellow "Restart zapret service to apply changes"
echo:
pause
goto menu


:: Utility functions
:PrintGreen
powershell -Command "Write-Host \"%~1\" -ForegroundColor Green" 2>nul || echo [OK] %~1
exit /b

:PrintRed
powershell -Command "Write-Host \"%~1\" -ForegroundColor Red" 2>nul || echo [ERROR] %~1
exit /b

:PrintYellow
powershell -Command "Write-Host \"%~1\" -ForegroundColor Yellow" 2>nul || echo [WARN] %~1
exit /b

:check_extracted
set "extracted=1"

if not exist "%~dp0bin\" set "extracted=0"

if "%extracted%"=="0" (
    echo Zapret must be extracted from archive first
    pause
    exit
)
exit /b 0

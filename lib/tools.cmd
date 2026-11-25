@echo off
rem ============================================================
rem  WinPulse 7.1 "Rebuild"  |  lib\tools.cmd  |  ЧАСТЬ 1/3
rem  Инструменты: проверка состояния системы.
rem
rem  Кодировка: UTF-8 БЕЗ BOM, CRLF. Символ "!" в echo запрещён.
rem  Вызов:  call "%WP_LIB%\tools.cmd" :CHECK_STATUS
rem  Свой setlocal ЗАПРЕЩЁН.
rem
rem  Всё в этом модуле READ-ONLY: ни одной записи в систему,
rem  ни одной строки в журнал отката. Пишем только свои файлы
rem  в .run и Logs.
rem
rem  [OK] значение совпадает с ожидаемым
rem  [--] значение или объект отсутствует
rem  [NE] значение отличается от ожидаемого
rem  [..] просто показано, ожидание зависит от профиля
rem
rem  NE не означает ошибку: твик мог быть не применён,
rem  откатан, или профиль выбрал другое значение.
rem ============================================================
if "%~1"=="" exit /b 9009
if not defined WP_LIB exit /b 9009
if not defined JOURNAL exit /b 9009
set "__EP=%~1"
shift
goto %__EP%

rem ============================================================
rem  NORM_DWORD  %1 имя входной переменной  %2 имя приёмника
rem  reg query отдаёт hex, инвентарь оперирует десятичными.
rem  В 6.x сравнение 0x4 с 4 давало ложный красный почти везде.
rem  0xffffffff отдельно: set /a на нём даёт -1.
rem ============================================================
:NORM_DWORD
set "_nd=!%~1!"
set "%~2="
if not defined _nd exit /b 1
if /i "!_nd!"=="0xffffffff" (
    set "%~2=4294967295"
    exit /b 0
)
if "!_nd!"=="4294967295" (
    set "%~2=4294967295"
    exit /b 0
)
set /a "%~2=!_nd!" >nul 2>&1
exit /b 0

rem ============================================================
rem  CHK  %1 подпись  %2 ключ  %3 значение  %4 ожидаемое
rem ============================================================
:CHK
set "_CN=%~1"
set "_CK=%~2"
set "_CV=%~3"
set "_CE=%~4"
set "_CL="
set "_CT="
set "_CD="
set "_CDA="
set "_CEA="
for /f "tokens=* delims=" %%L in ('reg query "%_CK%" /v "%_CV%" 2^>nul') do set "_CL=%%L"
if not defined _CL goto :CHK_ABSENT
set "_CR=!_CL:*REG_=REG_!"
for /f "tokens=1,*" %%a in ("!_CR!") do (
    set "_CT=%%a"
    set "_CD=%%b"
)
if /i not "!_CT!"=="REG_DWORD" goto :CHK_STR
call :NORM_DWORD _CD _CDA
call :NORM_DWORD _CE _CEA
if not defined _CDA goto :CHK_STR
if not defined _CEA goto :CHK_STR
if "!_CDA!"=="!_CEA!" goto :CHK_OK
goto :CHK_NE
:CHK_STR
if /i "!_CD!"=="!_CE!" goto :CHK_OK
:CHK_NE
echo   [NE] !_CN! : сейчас !_CD!, ожидалось !_CE!
set /a TOOL_CHK_NE+=1
exit /b 0
:CHK_OK
echo   [OK] !_CN!
set /a TOOL_CHK_OK+=1
exit /b 0
:CHK_ABSENT
echo   [--] !_CN! : отсутствует
set /a TOOL_CHK_ABSENT+=1
exit /b 0

rem ============================================================
rem  SHOW_VAL  %1 подпись  %2 ключ  %3 значение
rem  Для профиль-зависимых настроек: факт без вердикта.
rem  Иначе MenuShowDelay=100 при профиле Balanced выглядел бы
rem  как ошибка, хотя это ровно то, что выбрал пользователь.
rem ============================================================
:SHOW_VAL
set "_SN=%~1"
set "_SK=%~2"
set "_SV=%~3"
set "_SL="
set "_ST="
set "_SD="
for /f "tokens=* delims=" %%L in ('reg query "%_SK%" /v "%_SV%" 2^>nul') do set "_SL=%%L"
if not defined _SL (
    echo   [..] !_SN! : отсутствует
    exit /b 0
)
set "_SR=!_SL:*REG_=REG_!"
for /f "tokens=1,*" %%a in ("!_SR!") do (
    set "_ST=%%a"
    set "_SD=%%b"
)
if /i "!_ST!"=="REG_DWORD" call :NORM_DWORD _SD _SD
echo   [..] !_SN! : !_SD!
exit /b 0

rem ============================================================
rem  CHK_SVC  %1 служба  %2 ожидаемый Start
rem ============================================================
:CHK_SVC
set "_SS=%~1"
sc query "!_SS!" >nul 2>&1
if errorlevel 1 (
    echo   [--] служба !_SS! : не установлена
    set /a TOOL_CHK_ABSENT+=1
    exit /b 0
)
call :CHK "служба !_SS! Start" "HKLM\SYSTEM\CurrentControlSet\Services\!_SS!" "Start" "%~2"
exit /b 0

rem ============================================================
rem  CHK_BCD  %1 элемент  %2 ожидаемое
rem ============================================================
:CHK_BCD
set "_BN=%~1"
set "_BE=%~2"
set "_BL="
set "_BV="
for /f "tokens=* delims=" %%L in ('bcdedit /enum {current} 2^>nul ^| findstr /i /b /c:"%_BN%"') do set "_BL=%%L"
if not defined _BL (
    echo   [--] BCD !_BN! : не задан
    set /a TOOL_CHK_ABSENT+=1
    exit /b 0
)
for /f "tokens=1,*" %%a in ("!_BL!") do set "_BV=%%b"
if /i "!_BV!"=="Yes" set "_BV=yes"
if /i "!_BV!"=="No" set "_BV=no"
if /i "!_BV!"=="Да" set "_BV=yes"
if /i "!_BV!"=="Нет" set "_BV=no"
if /i "!_BV!"=="!_BE!" (
    echo   [OK] BCD !_BN! = !_BV!
    set /a TOOL_CHK_OK+=1
) else (
    echo   [NE] BCD !_BN! : сейчас !_BV!, ожидалось !_BE!
    set /a TOOL_CHK_NE+=1
)
exit /b 0

rem ============================================================
rem  SHOW_BCD  %1 элемент - просто показать
rem ============================================================
:SHOW_BCD
set "_BN=%~1"
set "_BL="
set "_BV="
for /f "tokens=* delims=" %%L in ('bcdedit /enum {current} 2^>nul ^| findstr /i /b /c:"%_BN%"') do set "_BL=%%L"
if not defined _BL (
    echo   [..] BCD !_BN! : не задан
    exit /b 0
)
for /f "tokens=1,*" %%a in ("!_BL!") do set "_BV=%%b"
echo   [..] BCD !_BN! : !_BV!
exit /b 0

rem ============================================================
rem  CHK_POWER  %1 подпись  %2 subgroup  %3 setting  %4 ожидание AC
rem  powercfg /q печатает ещё Possible/Min/Max индексы, поэтому
rem  берём ДВЕ ПОСЛЕДНИЕ строки с 0x - это Current AC и Current DC.
rem ============================================================
:CHK_POWER
set "_PN=%~1"
set "_PS=%~2"
set "_PT=%~3"
set "_PE=%~4"
set "_PP="
set "_PL="
set "_PA="
for /f "tokens=* delims=" %%L in ('powercfg /q SCHEME_CURRENT %_PS% %_PT% 2^>nul ^| findstr /i "0x"') do (
    set "_PX=%%L"
    set "_PX=!_PX:*0x=0x!"
    for /f "tokens=1" %%v in ("!_PX!") do (
        set "_PP=!_PL!"
        set "_PL=%%v"
    )
)
if not defined _PP (
    echo   [--] !_PN! : параметр отсутствует в этой сборке
    set /a TOOL_CHK_ABSENT+=1
    exit /b 0
)
call :NORM_DWORD _PP _PA
if not defined _PA set "_PA=!_PP!"
if "!_PA!"=="!_PE!" (
    echo   [OK] !_PN! AC=!_PA!
    set /a TOOL_CHK_OK+=1
) else (
    echo   [NE] !_PN! : AC=!_PA!, ожидалось !_PE!
    set /a TOOL_CHK_NE+=1
)
exit /b 0

rem ============================================================
rem  CHK_TASKS - состояние телеметрических задач.
rem  Список путей пишется здесь, PS только читает состояние:
rem  определения твиков живут в batch, не в движке.
rem ============================================================
:CHK_TASKS
set "_TLF=%WP_RUN%\tasklist.txt"
set "_TOF=%WP_RUN%\taskstate.txt"
if not exist "%WP_RUN%" mkdir "%WP_RUN%" >nul 2>&1
>"%_TLF%" echo \Microsoft\Windows\Customer Experience Improvement Program\Consolidator
>>"%_TLF%" echo \Microsoft\Windows\Customer Experience Improvement Program\UsbCeip
>>"%_TLF%" echo \Microsoft\Windows\Application Experience\ProgramDataUpdater
>>"%_TLF%" echo \Microsoft\Windows\Feedback\Siuf\DmClient
>>"%_TLF%" echo \Microsoft\Windows\Windows Error Reporting\QueueReporting
>>"%_TLF%" echo \Microsoft\Windows\MemoryDiagnostic\RunFullMemoryDiagnostic
>>"%_TLF%" echo \Microsoft\Windows\Maintenance\WinSAT
set "ST_TASK_COUNT="
if exist "%_TOF%" del /f /q "%_TOF%" >nul 2>&1
call "%WP_LIB%\core.cmd" :PS_RUN get-tasks "%_TOF%" "%_TLF%"
call "%WP_LIB%\backup.cmd" :LOAD_KV "%_TOF%"
if not defined ST_TASK_COUNT (
    echo   [--] задачи: PS-движок не ответил
    set /a TOOL_CHK_ABSENT+=1
    exit /b 0
)
for /l %%i in (1,1,!ST_TASK_COUNT!) do (
    set "_TP=!ST_TASK_%%i_PATH!"
    set "_TS=!ST_TASK_%%i_STATE!"
    for %%n in ("!_TP!") do set "_TN=%%~nxn"
    if /i "!_TS!"=="Absent" (
        echo   [--] задача !_TN! : отсутствует
        set /a TOOL_CHK_ABSENT+=1
    ) else if /i "!_TS!"=="Disabled" (
        echo   [OK] задача !_TN! отключена
        set /a TOOL_CHK_OK+=1
    ) else (
        echo   [NE] задача !_TN! : !_TS!, ожидалось Disabled
        set /a TOOL_CHK_NE+=1
    )
)
exit /b 0

rem ============================================================
rem  CHECK_STATUS - экран состояния. Только чтение.
rem ============================================================
:CHECK_STATUS
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
set /a ST_G_N=0
set /a TOOL_CHK_OK=0
set /a TOOL_CHK_NE=0
set /a TOOL_CHK_ABSENT=0
echo.
echo == СОСТОЯНИЕ ТВИКОВ ==
echo.
echo   OK совпадает   NE отличается   -- отсутствует   .. просто факт
echo   NE не ошибка: блок мог быть не применён или откатан.
echo.
call :ST_GROUP_BEGIN "Телеметрия и приватность"
call :CHK_SVC "DiagTrack" "4"
call :CHK_SVC "dmwappushservice" "4"
call :CHK "AllowTelemetry" "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" "0"
call :CHK "AdvertisingInfo" "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" "0"
call :CHK "EnableActivityFeed" "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" "EnableActivityFeed" "0"
call :CHK "AITEnable" "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat" "AITEnable" "0"
call :CHK "WER Disabled" "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" "Disabled" "1"
call :CHK "ConsumerFeatures" "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" "1"
call :CHK "Location consent" "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" "Value" "Deny"
call :CHK "DisableLocation" "HKLM\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" "DisableLocation" "1"
call :SHOW_VAL "BackgroundApps GlobalUserDisabled" "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled"
echo.
call :ST_GROUP_END
echo.
call :ST_GROUP_BEGIN "Сеть"
call :CHK "DefaultTTL" "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" "DefaultTTL" "64"
call :CHK "MaxUserPort" "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" "MaxUserPort" "65534"
call :CHK "TcpTimedWaitDelay" "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" "TcpTimedWaitDelay" "30"
call :CHK "NetworkThrottlingIndex" "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex" "4294967295"
call :CHK "DNS CacheHashTableSize" "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" "CacheHashTableSize" "384"
call :CHK "WebDAV лимит" "HKLM\SYSTEM\CurrentControlSet\Services\WebClient\Parameters" "FileSizeLimitInBytes" "4294967295"
echo   Nagle проверяется по каждому адаптеру, смотрите журнал сессии
echo.
call :ST_GROUP_END
echo.
call :ST_GROUP_BEGIN "Питание"
call :CHK "PowerThrottlingOff" "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff" "0"
call :CHK_POWER "Core Parking min" "SUB_PROCESSOR" "CPMINCORES" "100"
call :CHK_POWER "Core Parking max" "SUB_PROCESSOR" "CPMAXCORES" "100"
call :CHK_POWER "Processor Boost" "SUB_PROCESSOR" "PERFBOOSTMODE" "2"
call :CHK_POWER "Disk idle" "SUB_DISK" "DISKIDLE" "0"
call :CHK "HibernateEnabled" "HKLM\SYSTEM\CurrentControlSet\Control\Power" "HibernateEnabled" "0"
echo.
call :ST_GROUP_END
echo.
call :ST_GROUP_BEGIN "Задачи планировщика"
call :CHK_TASKS
echo.
call :ST_GROUP_END
echo.
call :ST_GROUP_BEGIN "Службы"
call :CHK_SVC "Fax" "4"
call :CHK_SVC "RemoteRegistry" "4"
call :CHK_SVC "RetailDemo" "4"
call :SHOW_VAL "Spooler Start" "HKLM\SYSTEM\CurrentControlSet\Services\Spooler" "Start"
call :SHOW_VAL "defragsvc Start" "HKLM\SYSTEM\CurrentControlSet\Services\defragsvc" "Start"
call :SHOW_VAL "SysMain Start" "HKLM\SYSTEM\CurrentControlSet\Services\SysMain" "Start"
call :CHK_SVC "Ndu" "4"
call :CHK_SVC "WSearch" "2"
call :SHOW_VAL "XblAuthManager Start" "HKLM\SYSTEM\CurrentControlSet\Services\XblAuthManager" "Start"
call :SHOW_VAL "ALG Start" "HKLM\SYSTEM\CurrentControlSet\Services\ALG" "Start"
echo   Spooler, defragsvc, SysMain, Xbox показаны как факт:
echo   они применяются только по подтверждению и guard'ам.
echo.
call :ST_GROUP_END
echo.
call :ST_GROUP_BEGIN "Визуал"
call :SHOW_VAL "MenuShowDelay" "!WP_HKCU!\Control Panel\Desktop" "MenuShowDelay"
call :SHOW_VAL "EnableTransparency" "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency"
call :SHOW_VAL "VisualFXSetting" "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting"
call :SHOW_VAL "MinAnimate" "!WP_HKCU!\Control Panel\Desktop\WindowMetrics" "MinAnimate"
call :CHK "ShowSyncProviderNotifications" "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSyncProviderNotifications" "0"
echo   Профиль визуала в этой сессии: !WP_VISUAL_PROFILE!
echo.
call :ST_GROUP_END
echo.
call :ST_GROUP_BEGIN "Игры и UX"
call :CHK "AutoGameModeEnabled" "!WP_HKCU!\Software\Microsoft\GameBar" "AutoGameModeEnabled" "1"
call :CHK "AppCaptureEnabled" "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" "0"
call :CHK "GameDVR_Enabled" "!WP_HKCU!\System\GameConfigStore" "GameDVR_Enabled" "0"
call :CHK "AllowGameDVR" "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" "0"
call :CHK "GameDVR_FSEBehaviorMode" "!WP_HKCU!\System\GameConfigStore" "GameDVR_FSEBehaviorMode" "2"
call :CHK "DisableSearchBoxSuggestions" "!WP_HKCU!\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" "1"
call :CHK "Copilot HKLM" "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" "1"
call :CHK "HwSchMode HAGS" "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" "2"
call :CHK "MouseSpeed" "!WP_HKCU!\Control Panel\Mouse" "MouseSpeed" "0"
echo.
call :ST_GROUP_END
echo.
call :ST_GROUP_BEGIN "Ввод"
call :CHK "KeyboardDelay" "!WP_HKCU!\Control Panel\Keyboard" "KeyboardDelay" "0"
call :CHK "KeyboardSpeed" "!WP_HKCU!\Control Panel\Keyboard" "KeyboardSpeed" "31"
call :CHK "StickyKeys Flags" "!WP_HKCU!\Control Panel\Accessibility\StickyKeys" "Flags" "506"
echo.
call :ST_GROUP_END
echo.
call :ST_GROUP_BEGIN "Память и ядро"
call :CHK "DisablePagingExecutive" "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "DisablePagingExecutive" "1"
call :CHK "LargeSystemCache" "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "LargeSystemCache" "0"
call :SHOW_VAL "SvcHostSplitThresholdInKB" "HKLM\SYSTEM\CurrentControlSet\Control" "SvcHostSplitThresholdInKB"
call :SHOW_VAL "PoolUsageMaximum" "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "PoolUsageMaximum"
call :CHK "GlobalTimerResolutionRequests" "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" "GlobalTimerResolutionRequests" "1"
call :SHOW_VAL "Win32PrioritySeparation" "HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation"
call :SHOW_VAL "SystemResponsiveness" "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "SystemResponsiveness"
echo.
call :ST_GROUP_END
echo.
call :ST_GROUP_BEGIN "Безопасность"
call :SHOW_VAL "HVCI" "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" "Enabled"
call :SHOW_VAL "Credential Guard" "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" "LsaCfgFlags"
call :SHOW_VAL "VBS" "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" "EnableVirtualizationBasedSecurity"
call :SHOW_VAL "Spectre Override" "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "FeatureSettingsOverride"
call :SHOW_VAL "SEHOP off" "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" "DisableExceptionChainValidation"
call :SHOW_VAL "Hetero scheduling off" "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" "DisableHeterogeneousThreadScheduling"
echo   Безопасность показана как факт: снижение защиты - выбор пользователя.
echo.
call :ST_GROUP_END
echo.
call :ST_GROUP_BEGIN "BCD"
call :SHOW_BCD "disabledynamictick"
call :SHOW_BCD "useplatformclock"
call :SHOW_BCD "useplatformtick"
call :SHOW_BCD "tscsyncpolicy"
call :SHOW_BCD "nx"
call :SHOW_BCD "tpmbootentropy"
call :SHOW_BCD "bootuxdisabled"
echo.
call :ST_GROUP_END
echo.
call :ST_GROUP_BEGIN "GPU"
call :SHOW_VAL "DWM OverlayTestMode" "HKLM\SOFTWARE\Microsoft\Windows\DWM" "OverlayTestMode"
if defined GPU_HWID (
    call :SHOW_VAL "GPU MSISupported" "HKLM\SYSTEM\CurrentControlSet\Enum\PCI\!GPU_HWID!\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties" "MSISupported"
) else (
    echo   [..] GPU instance path не определён, MSI не проверяется
)
if defined GPU_CLASSKEY (
    call :SHOW_VAL "GPU EnableUlps" "!GPU_CLASSKEY!" "EnableUlps"
    call :SHOW_VAL "GPU RMHdcpKeyGlob" "!GPU_CLASSKEY!" "RMHdcpKeyGlob"
)
echo.
set /a "_TCT=TOOL_CHK_OK+TOOL_CHK_NE+TOOL_CHK_ABSENT"
echo.
echo   Исключения Defender, состояние MMAgent и BitLocker
echo   смотрите в матрице защиты [J] и в информации о системе [I].
echo.
call :ST_GROUP_END
call :ST_GROUP_BEGIN "Автозагрузка и IFEO"
call :CHK "IFEO GoogleUpdate CPU" "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\GoogleUpdate.exe\PerfOptions" "CpuPriorityClass" "5"
call :CHK "IFEO AdobeARM CPU" "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\AdobeARM.exe\PerfOptions" "CpuPriorityClass" "5"
call :CHK "IFEO jusched IO" "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\jucheck.exe\PerfOptions" "IoPriority" "1"
call :SHOW_VAL "Roblox в Run" "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\Run" "RobloxPlayerBeta"
echo   AUTORUN работает по whitelist: записи вне списка не трогаются.
echo   Полный список автозагрузки и выбор - клавиша 1.
call :ST_GROUP_END
echo.
call :ST_GROUP_BEGIN "Службы по факту устройств"
call :SHOW_VAL "bthserv Start" "HKLM\SYSTEM\CurrentControlSet\Services\bthserv" "Start"
call :SHOW_VAL "TermService Start" "HKLM\SYSTEM\CurrentControlSet\Services\TermService" "Start"
call :SHOW_VAL "ScDeviceEnum Start" "HKLM\SYSTEM\CurrentControlSet\Services\ScDeviceEnum" "Start"
call :SHOW_VAL "WbioSrvc Start" "HKLM\SYSTEM\CurrentControlSet\Services\WbioSrvc" "Start"
call :SHOW_VAL "lfsvc Start" "HKLM\SYSTEM\CurrentControlSet\Services\lfsvc" "Start"
call :SHOW_VAL "MapsBroker Start" "HKLM\SYSTEM\CurrentControlSet\Services\MapsBroker" "Start"
echo   Показаны как факт: служба отключается только если устройства нет.
echo   На ноутбуке с Bluetooth или сканером отпечатка они должны работать.
call :ST_GROUP_END
echo.
call :ST_GROUP_BEGIN "Драйвер Ethernet"
call :CHK_NIC
echo   Считаются только существующие ключи, отсутствующие не создаются.
call :ST_GROUP_END
echo.
call :ST_GROUP_BEGIN "Хранилище и пакеты"
echo   .. STORAGE_SAFE, STORAGE_DEEP, PROVISIONED - удаления.
echo      Реестром не проверяются: кэш мог пересобраться, пакет вернуться
echo      после обновления. Смотри журнал сессии и provisioned_removed.txt.
echo   .. SMB1 проверяется через состояние компонента, не через реестр.
echo      Win+R -^> optionalfeatures -^> SMB 1.0/CIFS, галка должна быть снята.
call :ST_GROUP_END
echo.
call :ST_SUMMARY
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
exit /b 0


rem ============================================================
rem  ЧАСТЬ 2/3. Бенчмарк.
rem
rem  Результат = KEY=VALUE в Logs\bench_<stamp>_<tag>_<rnd>.txt
rem  Это позволяет считать дельту, а не печатать два файла рядом.
rem
rem  Дополнительно к контракту:
rem    WP_BENCH_BASELINE  путь к замеру до режима
rem    WP_BENCH_FINAL     путь к замеру после режима
rem
rem  Публичные метки для winpulse.bat:
rem    BENCH_MENU             меню бенчмарка
rem    BENCH_SILENT <tag>     тихий замер, quick-профиль
rem    BENCH_AUTO_COMPARE     сравнить baseline и final, с возвратом
rem
rem  Замеры пишут только в свои папки. Систему не меняют.
rem ============================================================

rem ============================================================
rem  ASK_NUM  %1 приглашение  %2 максимум  %3 имя приёмника
rem  Валидация обязательна: при мусоре вместо номера раньше
rem  подставлялась пустая переменная и type падал на каталоге.
rem ============================================================
:ASK_NUM
set "_anq=%~1"
set "_anm=%~2"
set "%~3="
set "_ani="
set "WP_QUESTION=!_anq!"
call "%WP_LIB%\desktop_io.cmd" input _ani
if not defined _ani exit /b 1
echo %_ani%| findstr /r "^[0-9][0-9]*$" >nul 2>&1
if errorlevel 1 exit /b 1
if not "%_ani:~3%"=="" exit /b 1
if !_ani! gtr %_anm% exit /b 1
set "%~3=!_ani!"
exit /b 0

rem ============================================================
rem  BENCH_EXEC  %1 quick|full  %2 baseline|final|manual
rem ============================================================
:BENCH_EXEC
set "_BP=%~1"
set "_BT=%~2"
if not defined _BP set "_BP=quick"
if not defined _BT set "_BT=manual"
if not exist "%WP_LOGS%" mkdir "%WP_LOGS%" >nul 2>&1
if not exist "%WP_RUN%" mkdir "%WP_RUN%" >nul 2>&1
set "_BOUT=%WP_LOGS%\bench_%STAMP%_!_BT!_%RANDOM%.txt"
if exist "!_BOUT!" del /f /q "!_BOUT!" >nul 2>&1
call "%WP_LIB%\core.cmd" :MSG "Бенчмарк !_BP!: закрой тяжёлые приложения и не трогай ввод"
call "%WP_LIB%\core.cmd" :PS_RUN get-benchmark "!_BOUT!" "%WP_RUN%" "!_BP!"
set "_BRC=!errorlevel!"
if not exist "!_BOUT!" (
    call "%WP_LIB%\core.cmd" :FAIL "бенчмарк не создал файл результата"
    exit /b 1
)
rem Контекст тоже в формате KEY=VALUE, иначе LOAD_KV споткнётся
>>"!_BOUT!" echo CTX_TAG=!_BT!
>>"!_BOUT!" echo CTX_PROFILE=!_BP!
>>"!_BOUT!" echo CTX_SESSION=%STAMP%
>>"!_BOUT!" echo CTX_CPU=!CPU_NAME!
>>"!_BOUT!" echo CTX_RAM_GB=!RAM_GB!
>>"!_BOUT!" echo CTX_BOOT_DISK=!BOOT_DISK_TYPE!
>>"!_BOUT!" echo CTX_TIER=!DETECT_TIER!
>>"!_BOUT!" echo CTX_VISUAL=!WP_VISUAL_PROFILE!
if "!_BRC!"=="2" call "%WP_LIB%\core.cmd" :WARN "часть замеров не выполнена, список в PS_FAILURES"
call "%WP_LIB%\core.cmd" :OK "замер сохранён: !_BOUT!"
exit /b 0

rem ============================================================
rem  BENCH_SILENT  %1 tag - для вызова из режимов, без вопросов
rem ============================================================
:BENCH_SILENT
set "_BST=%~1"
if not defined _BST set "_BST=manual"
if "%WP_DRYRUN%"=="1" (
    call "%WP_LIB%\core.cmd" :PLAN_NOTE "benchmark !_BST! would run"
    exit /b 0
)
call :BENCH_EXEC "quick" "!_BST!"
if errorlevel 1 exit /b 1
if /i "!_BST!"=="baseline" set "WP_BENCH_BASELINE=!_BOUT!"
if /i "!_BST!"=="final" set "WP_BENCH_FINAL=!_BOUT!"
exit /b 0

rem ============================================================
rem  BENCH_LIST - файлы замеров, свежие первыми по времени записи
rem ============================================================
:BENCH_LIST
set "BL_COUNT=0"
if not exist "%WP_LOGS%" exit /b 0
for /f "usebackq delims=" %%f in (`dir /b /a-d /o:-d "%WP_LOGS%\bench_*.txt" 2^>nul`) do (
    set /a BL_COUNT+=1
    set "BL_!BL_COUNT!=%%f"
)
exit /b 0

rem ============================================================
rem  BENCH_CLEAR_NS - сброс пространств A_ и B_ перед сравнением.
rem  Без этого метрика из прошлого замера пережила бы загрузку
rem  файла, где этот шаг упал, и дельта посчиталась бы по мусору.
rem ============================================================
:BENCH_CLEAR_NS
for %%k in (BENCH_STAMP BENCH_PROFILE BENCH_CPU_ST_MS BENCH_CPU_MT_MS BENCH_CPU_ST_SCORE BENCH_CPU_MT_SPEEDUP_PCT BENCH_CPU_MT_THREADS BENCH_RAM_COPY_MBS BENCH_RAM_MS BENCH_RAM_BLOCK_MB BENCH_DISK_WRITE_MBS BENCH_DISK_READ_CACHED_MBS BENCH_DISK_WRITE_MS BENCH_DISK_READ_MS BENCH_DISK_WRITE_MODE BENCH_DISK_READ_MODE BENCH_NET_AVG_MS BENCH_NET_MIN_MS BENCH_NET_MAX_MS BENCH_NET_OK BENCH_DNS_MS BENCH_DURATION_S PS_FAILURES CTX_TAG CTX_PROFILE CTX_CPU CTX_RAM_GB CTX_BOOT_DISK CTX_TIER CTX_VISUAL) do (
    set "A_%%k="
    set "B_%%k="
)
exit /b 0

rem ============================================================
rem  BENCH_REPORT - человекочитаемый вывод из пространства B_
rem ============================================================
:BENCH_REPORT
echo   Метка: !B_CTX_TAG!    профиль: !B_CTX_PROFILE!    время: !B_BENCH_STAMP!
echo   CPU: !B_CTX_CPU!
echo   RAM: !B_CTX_RAM_GB! GB    диск: !B_CTX_BOOT_DISK!    детект: !B_CTX_TIER!
echo.
echo   CPU 1 поток:     !B_BENCH_CPU_ST_MS! ms    индекс !B_BENCH_CPU_ST_SCORE!
echo   CPU все ядра:    !B_BENCH_CPU_MT_MS! ms    потоков !B_BENCH_CPU_MT_THREADS!
echo   Масштабирование: !B_BENCH_CPU_MT_SPEEDUP_PCT! проц.
echo   RAM копирование: !B_BENCH_RAM_COPY_MBS! MB/s    блок !B_BENCH_RAM_BLOCK_MB! MB
echo   Диск запись:     !B_BENCH_DISK_WRITE_MBS! MB/s    режим !B_BENCH_DISK_WRITE_MODE!
echo   Диск чтение:     !B_BENCH_DISK_READ_CACHED_MBS! MB/s    режим !B_BENCH_DISK_READ_MODE!
if "!B_BENCH_NET_OK!"=="1" (
    echo   Сеть ping:       !B_BENCH_NET_AVG_MS! ms среднее    !B_BENCH_NET_MIN_MS!..!B_BENCH_NET_MAX_MS!
) else (
    echo   Сеть ping:       недоступно
)
echo   DNS резолв:      !B_BENCH_DNS_MS! ms
echo   Длительность:    !B_BENCH_DURATION_S! s
if defined B_PS_FAILURES if not "!B_PS_FAILURES!"=="" echo   Не выполнено: !B_PS_FAILURES!
exit /b 0

rem ============================================================
rem  BENCH_DELTA  %1 ключ  %2 подпись  %3 L|H
rem  L = меньше лучше, H = больше лучше.
rem  Порог 5 проц: ниже этого это шум, а не эффект.
rem ============================================================
:BENCH_DELTA
set "_bk=%~1"
set "_bl=%~2"
set "_bd=%~3"
set "_ov=!A_%_bk%!"
set "_nv=!B_%_bk%!"
if not defined _ov (
    echo   [N/A]    !_bl! : нет в первом замере
    exit /b 0
)
if not defined _nv (
    echo   [N/A]    !_bl! : нет во втором замере
    exit /b 0
)
if /i "!_bd!"=="INFO" (
    echo   [INFO] !_bl! : !_ov! -^> !_nv!
    exit /b 0
)
if "!_ov!"=="0" (
    echo   [N/A]    !_bl! : !_ov! -^> !_nv!, базовый ноль
    exit /b 0
)
set /a "_df=_nv-_ov"
set /a "_pc=(_df * 100) / _ov"
set "_vd=NOISE"
if !_pc! geq 5 (
    if /i "!_bd!"=="H" (set "_vd=BETTER") else (set "_vd=WORSE")
)
if !_pc! leq -5 (
    if /i "!_bd!"=="L" (set "_vd=BETTER") else (set "_vd=WORSE")
)
echo   [!_vd!] !_bl! : !_ov! -^> !_nv!   дельта !_pc! проц.
exit /b 0

rem ============================================================
rem  BENCH_DIFF_BODY - общий вывод сравнения A_ против B_
rem ============================================================
:BENCH_DIFF_BODY
echo   Было:  !A_CTX_TAG! !A_BENCH_STAMP!    профиль !A_CTX_PROFILE!
echo   Стало: !B_CTX_TAG! !B_BENCH_STAMP!    профиль !B_CTX_PROFILE!
if not "!A_CTX_PROFILE!"=="!B_CTX_PROFILE!" echo   [WARN] профили разные, сравнение некорректно
if not "!A_CTX_CPU!"=="!B_CTX_CPU!" echo   [WARN] CPU в замерах различается
echo.
echo   BETTER лучше, WORSE хуже, NOISE меньше 5 проц.
echo.
call :BENCH_DELTA BENCH_CPU_ST_MS "CPU 1 поток, ms" L
call :BENCH_DELTA BENCH_CPU_ST_SCORE "CPU индекс" H
call :BENCH_DELTA BENCH_CPU_MT_MS "CPU все ядра, ms" L
call :BENCH_DELTA BENCH_CPU_MT_SPEEDUP_PCT "Масштабирование" H
call :BENCH_DELTA BENCH_RAM_COPY_MBS "RAM, MB/s" H
call :BENCH_DELTA BENCH_DISK_WRITE_MBS "Диск запись, MB/s" H
call :BENCH_DELTA BENCH_DISK_READ_CACHED_MBS "Диск чтение, MB/s" H
call :BENCH_DELTA BENCH_NET_AVG_MS "Сеть ping, ms" INFO
call :BENCH_DELTA BENCH_DNS_MS "DNS резолв, ms" INFO
echo.
echo   Индекс CPU относительный, это не Cinebench.
echo   Чтение диска помечено cached: кэш ОС участвует.
echo   Разница меньше 5 проц на повторяемых замерах - шум.
exit /b 0

rem ============================================================
rem  BENCH_AUTO_COMPARE - вызывается из сводки режима.
rem  Возвращается вызывающему, в меню НЕ уходит.
rem ============================================================
:BENCH_AUTO_COMPARE
if "%WP_DRYRUN%"=="1" exit /b 0
if not defined WP_BENCH_BASELINE exit /b 0
if not defined WP_BENCH_FINAL exit /b 0
if not exist "!WP_BENCH_BASELINE!" exit /b 0
if not exist "!WP_BENCH_FINAL!" exit /b 0
echo.
echo == ДО И ПОСЛЕ ТЕКУЩЕЙ СЕССИИ ==
echo.
call :BENCH_CLEAR_NS
call "%WP_LIB%\detect.cmd" :LOAD_KV_PFX "!WP_BENCH_BASELINE!" "A_"
call "%WP_LIB%\detect.cmd" :LOAD_KV_PFX "!WP_BENCH_FINAL!" "B_"
call :BENCH_DIFF_BODY
echo.
echo   Если между замерами была перезагрузка, часть твиков
echo   вступила в силу только сейчас, и это ожидаемо.
exit /b 0

rem ============================================================
rem  BENCH_MENU
rem ============================================================
:BENCH_MENU
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == БЕНЧМАРК ==
echo.
echo   [1] Быстрый замер, около 10 секунд
echo   [2] Полный замер, около 30 секунд
echo   [3] Показать последний результат
echo   [4] Сравнить два замера
echo   [5] Сравнить до и после текущей сессии
echo   [0] Назад
echo.
set "_BMKEYS=123450"
set "_BMMAP=1:BENCH_RUN_QUICK 2:BENCH_RUN_FULL 3:BENCH_SHOW_LAST 4:BENCH_COMPARE 5:BENCH_MENU_AUTO 0:BENCH_BACK"
set "WP_QUESTION=Ваш выбор: "
call "%WP_LIB%\desktop_io.cmd" choice %_BMKEYS%
set /a "_BMI=%errorlevel%-1"
set "_BMK=!_BMKEYS:~%_BMI%,1!"
set "_BMT="
for %%p in (%_BMMAP%) do (
    for /f "tokens=1,2 delims=:" %%a in ("%%p") do (
        if /i "%%a"=="!_BMK!" set "_BMT=%%b"
    )
)
if not defined _BMT goto :BENCH_MENU
goto :!_BMT!

:BENCH_RUN_QUICK
set "_BPROF=quick"
goto :BENCH_DO_RUN

:BENCH_RUN_FULL
set "_BPROF=full"
goto :BENCH_DO_RUN

:BENCH_DO_RUN
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == ЗАПУСК ЗАМЕРА ==
echo.
echo   Закрой браузер, игры и рендеры. Не трогай мышь и клавиатуру.
echo   Тест диска создаёт временный файл в .run и удаляет его.
echo.
call "%WP_LIB%\core.cmd" :CONFIRM "Запустить замер" Y
if errorlevel 1 goto :BENCH_MENU
call :BENCH_EXEC "!_BPROF!" "manual"
echo.
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :BENCH_MENU

:BENCH_SHOW_LAST
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == ПОСЛЕДНИЙ ЗАМЕР ==
echo.
call :BENCH_LIST
if "!BL_COUNT!"=="0" (
    echo   Замеров нет.
    echo.
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    goto :BENCH_MENU
)
call :BENCH_CLEAR_NS
call "%WP_LIB%\detect.cmd" :LOAD_KV_PFX "%WP_LOGS%\!BL_1!" "B_"
echo   Файл: !BL_1!
echo.
call :BENCH_REPORT
echo.
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :BENCH_MENU

:BENCH_COMPARE
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == СРАВНЕНИЕ ДВУХ ЗАМЕРОВ ==
echo.
call :BENCH_LIST
if !BL_COUNT! lss 2 (
    echo   Нужно минимум два замера, найдено !BL_COUNT!.
    echo.
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    goto :BENCH_MENU
)
for /l %%i in (1,1,!BL_COUNT!) do (
    if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:sample^|%%i^|!BL_%%i!) else if %%i leq 20 echo   [%%i] !BL_%%i!
)
echo.
set "_BN1="
set "_BN2="
call :ASK_NUM "Номер первого, было (Enter отмена): " !BL_COUNT! _BN1
if errorlevel 1 goto :BENCH_MENU
call :ASK_NUM "Номер второго, стало: " !BL_COUNT! _BN2
if errorlevel 1 goto :BENCH_MENU
if "!_BN1!"=="!_BN2!" (
    echo   Выбран один и тот же замер.
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    goto :BENCH_MENU
)
call :BENCH_CLEAR_NS
call "%WP_LIB%\detect.cmd" :LOAD_KV_PFX "%WP_LOGS%\!BL_%_BN1%!" "A_"
call "%WP_LIB%\detect.cmd" :LOAD_KV_PFX "%WP_LOGS%\!BL_%_BN2%!" "B_"
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == ДЕЛЬТА ==
echo.
call :BENCH_DIFF_BODY
echo.
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :BENCH_MENU

:BENCH_MENU_AUTO
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == ДО И ПОСЛЕ ТЕКУЩЕЙ СЕССИИ ==
echo.
if not defined WP_BENCH_BASELINE (
    echo   Замер "до" не выполнялся в этой сессии.
    echo.
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    goto :BENCH_MENU
)
if not defined WP_BENCH_FINAL (
    echo   Замер "после" не выполнялся в этой сессии.
    echo.
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    goto :BENCH_MENU
)
call :BENCH_CLEAR_NS
call "%WP_LIB%\detect.cmd" :LOAD_KV_PFX "!WP_BENCH_BASELINE!" "A_"
call "%WP_LIB%\detect.cmd" :LOAD_KV_PFX "!WP_BENCH_FINAL!" "B_"
call :BENCH_DIFF_BODY
echo.
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :BENCH_MENU

:BENCH_BACK
exit /b 0


rem ============================================================
rem  ЧАСТЬ 3/3. Время загрузки, диагностика, поиск, история,
rem  настройки, информация о системе.
rem
rem  Дополнительно к контракту:
rem    PREF_FILE          файл настроек, задаёт winpulse.bat
rem    WP_BENCH_AUTO      1 = замер до/после режима автоматически
rem    WP_KEEP_SESSIONS   сколько сессий хранить
rem
rem  Публичные метки для winpulse.bat:
rem    BOOT_TIME  DIAGNOSTICS_MENU  SEARCH_DOCS  UNDO_HISTORY
rem    SETTINGS_MENU  SAVE_PREFS  SYSTEM_INFO_SCREEN
rem
rem  Всё здесь read-only, КРОМЕ диагностики: DISM/SFC/CHKDSK
rem  чинят систему, а сброс сети меняет её. Каждый такой запуск
rem  под подтверждением и пишется в лог, сброс сети - в журнал
rem  как необратимая операция.
rem ============================================================

rem ============================================================
rem  BOOT_TIME - объективное время загрузки вместо "вроде быстрее"
rem ============================================================
:BOOT_TIME
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == ВРЕМЯ ЗАГРУЗКИ ==
echo.
if not exist "%WP_RUN%" mkdir "%WP_RUN%" >nul 2>&1
set "_BOF=%WP_RUN%\boottime.txt"
set "BT_COUNT="
set "BA_COUNT="
set "BT_LOG_ENABLED="
if exist "%_BOF%" del /f /q "%_BOF%" >nul 2>&1
call "%WP_LIB%\core.cmd" :PS_RUN get-boottime "%_BOF%"
call "%WP_LIB%\backup.cmd" :LOAD_KV "%_BOF%"
if not defined BT_COUNT set "BT_COUNT=0"
if not defined BA_COUNT set "BA_COUNT=0"
if "!BT_LOG_ENABLED!"=="0" (
    echo   Журнал Diagnostics-Performance ОТКЛЮЧЁН, записей нет.
    echo   Включить от администратора:
    echo     wevtutil sl Microsoft-Windows-Diagnostics-Performance/Operational /e:true
    echo   Затем перезагрузиться пару раз, чтобы накопились события.
    echo.
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    exit /b 0
)
if "!BT_COUNT!"=="0" (
    echo   Событий загрузки пока нет. Они появляются после нескольких перезагрузок.
    echo.
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    exit /b 0
)
echo   Последние загрузки, свежие первыми. Все значения в миллисекундах.
echo.
echo   Дата              Всего    Ядро     После входа
set "_BSUM=0"
set "_BN=0"
for /l %%i in (1,1,!BT_COUNT!) do (
    set "_BT=!BT_%%i_TOTAL!"
    set "_BM=!BT_%%i_MAIN!"
    set "_BP=!BT_%%i_POST!"
    if not defined _BT set "_BT=-"
    if not defined _BM set "_BM=-"
    if not defined _BP set "_BP=-"
    echo   !BT_%%i_TIME!   !_BT!   !_BM!   !_BP!
    if %%i leq 5 (
        echo !_BT!| findstr /r "^[0-9][0-9]*$" >nul 2>&1
        if not errorlevel 1 (
            set /a "_BSUM+=!_BT!"
            set /a "_BN+=1"
        )
    )
)
if !_BN! gtr 0 (
    set /a "_BAVG=_BSUM/_BN"
    echo.
    echo   Среднее по последним !_BN! загрузкам: !_BAVG! ms
)
echo.
echo   Всего - полное время до готовности рабочего стола.
echo   Ядро - MainPathBootTime, После входа - BootPostBootTime.
echo   Именно "После входа" растёт от автозагрузки.
echo.
if "!BA_COUNT!"=="0" (
    echo   Виновников замедления система не зафиксировала.
) else (
    echo == ЧТО ТОРМОЗИЛО ЗАГРУЗКУ ==
    echo.
    echo   ID 101 приложение, 102 драйвер, 103 служба.
    echo.
    for /l %%i in (1,1,!BA_COUNT!) do (
        if %%i leq 20 (
            set "_BNM=!BA_%%i_NAME!"
            set "_BTT=!BA_%%i_TOTAL!"
            if not defined _BTT set "_BTT=0"
            echo !_BTT!| findstr /r "^[0-9][0-9]*$" >nul 2>&1
            if errorlevel 1 set "_BTT=0"
            if !_BTT! gtr 1000 (
                echo   [SLOW] !BA_%%i_TIME!  ID !BA_%%i_ID!  !_BNM!  !_BTT! ms
            ) else (
                echo   [ok]   !BA_%%i_TIME!  ID !BA_%%i_ID!  !_BNM!  !_BTT! ms
            )
        )
    )
    echo.
    echo   SLOW = больше секунды. Это кандидаты на чистку автозагрузки.
)
echo.
echo   BIOS-настройки влияют на POST, он в эти цифры не входит:
echo   POST происходит до старта загрузчика Windows.
echo.
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
exit /b 0

rem ============================================================
rem  DIAGNOSTICS_MENU
rem ============================================================
:DIAGNOSTICS_MENU
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == ДИАГНОСТИКА ==
echo.
echo   [1] DISM CheckHealth      быстро, только проверка флага
echo   [2] DISM ScanHealth       несколько минут
echo   [3] DISM RestoreHealth    долго, нужен доступ к Windows Update
echo   [4] SFC /scannow          проверка системных файлов
echo   [5] CHKDSK /scan          онлайн-проверка тома, без размонтирования
echo   [6] Сброс сети            уничтожит сетевые твики, только по слову YES
echo   [0] Назад
echo.
set "_DGKEYS=1234560"
set "_DGMAP=1:DG_CHECK 2:DG_SCAN 3:DG_RESTORE 4:DG_SFC 5:DG_CHKDSK 6:DG_NETRESET 0:DG_BACK"
set "WP_QUESTION=Ваш выбор: "
call "%WP_LIB%\desktop_io.cmd" choice %_DGKEYS%
set /a "_DGI=%errorlevel%-1"
set "_DGK=!_DGKEYS:~%_DGI%,1!"
set "_DGT="
for %%p in (%_DGMAP%) do (
    for /f "tokens=1,2 delims=:" %%a in ("%%p") do (
        if /i "%%a"=="!_DGK!" set "_DGT=%%b"
    )
)
if not defined _DGT goto :DIAGNOSTICS_MENU
goto :!_DGT!

:DG_PREVIEW
call "%WP_LIB%\core.cmd" :MSG "Предпросмотр: системная команда диагностики не запущена"
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :DIAGNOSTICS_MENU

:DG_CHECK
if "!WP_DRYRUN!"=="1" goto :DG_PREVIEW
call "%WP_LIB%\core.cmd" :HEAD "DISM CheckHealth"
DISM /Online /Cleanup-Image /CheckHealth
call :DG_RESULT "DISM CheckHealth" !errorlevel!
goto :DIAGNOSTICS_MENU

:DG_SCAN
if "!WP_DRYRUN!"=="1" goto :DG_PREVIEW
call "%WP_LIB%\core.cmd" :HEAD "DISM ScanHealth"
DISM /Online /Cleanup-Image /ScanHealth
call :DG_RESULT "DISM ScanHealth" !errorlevel!
goto :DIAGNOSTICS_MENU

:DG_RESTORE
if "!WP_DRYRUN!"=="1" goto :DG_PREVIEW
call "%WP_LIB%\core.cmd" :HEAD "DISM RestoreHealth"
call "%WP_LIB%\core.cmd" :MSG "Займёт 10-30 минут и полезет в Windows Update"
call "%WP_LIB%\core.cmd" :CONFIRM "Запустить восстановление образа" N
if errorlevel 1 goto :DIAGNOSTICS_MENU
DISM /Online /Cleanup-Image /RestoreHealth
call :DG_RESULT "DISM RestoreHealth" !errorlevel!
goto :DIAGNOSTICS_MENU

:DG_SFC
if "!WP_DRYRUN!"=="1" goto :DG_PREVIEW
call "%WP_LIB%\core.cmd" :HEAD "SFC scannow"
call "%WP_LIB%\core.cmd" :MSG "Займёт 5-20 минут"
call "%WP_LIB%\core.cmd" :CONFIRM "Запустить проверку системных файлов" N
if errorlevel 1 goto :DIAGNOSTICS_MENU
sfc /scannow
call :DG_RESULT "SFC scannow" !errorlevel!
goto :DIAGNOSTICS_MENU

:DG_CHKDSK
if "!WP_DRYRUN!"=="1" goto :DG_PREVIEW
call "%WP_LIB%\core.cmd" :HEAD "CHKDSK онлайн-проверка"
call "%WP_LIB%\core.cmd" :MSG "Том !SYS_DRIVE! проверяется без размонтирования, данные не трогаются"
call "%WP_LIB%\core.cmd" :CONFIRM "Запустить проверку тома" Y
if errorlevel 1 goto :DIAGNOSTICS_MENU
chkdsk !SYS_DRIVE! /scan
call :DG_RESULT "CHKDSK scan" !errorlevel!
goto :DIAGNOSTICS_MENU

:DG_NETRESET
if "!WP_DRYRUN!"=="1" goto :DG_PREVIEW
call "%WP_LIB%\core.cmd" :HEAD "Сброс сетевого стека"
echo   winsock reset и int ip reset вернут стек к состоянию Windows.
echo   ВСЕ сетевые твики WinPulse будут потеряны, журнал их не вернёт:
echo   после сброса придётся применить сетевые блоки заново.
echo   Zapret после этого тоже потребует переустановки из своего меню.
echo.
echo   Введите YES заглавными для сброса.
set "_DGN="
set "WP_QUESTION=Ввод: "
call "%WP_LIB%\desktop_io.cmd" input _DGN
if not "!_DGN!"=="YES" goto :DIAGNOSTICS_MENU
call "%WP_LIB%\core.cmd" :IRREVERSIBLE "network stack reset winsock+ip"
netsh winsock reset
netsh int ip reset
ipconfig /flushdns
call "%WP_LIB%\core.cmd" :WARN "Сетевой стек сброшен, нужна перезагрузка"
set "WP_REBOOT_REQUIRED=1"
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :DIAGNOSTICS_MENU

:DG_RESULT
if "%~2"=="0" (
    call "%WP_LIB%\core.cmd" :OK "%~1 завершено без ошибок"
) else (
    call "%WP_LIB%\core.cmd" :WARN "%~1 вернуло код %~2, смотрите вывод выше"
)
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
exit /b 0

:DG_BACK
exit /b 0

rem ============================================================
rem  SEARCH_DOCS - поиск по всем документам.
rem  Термин пишется в файл и передаётся через findstr /g:
rem  это снимает проблему кавычек и спецсимволов во вводе.
rem  Редирект впереди: иначе хвостовая цифра съедается как номер хэндла.
rem ============================================================
:SEARCH_DOCS
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == ПОИСК ПО ДОКУМЕНТАЦИИ ==
echo.
echo   Ищет в README.txt, MANUAL_STEPS.txt, EXTERNAL_TOOLS.txt
echo.
set "TERM="
set "WP_QUESTION=Ключевое слово, Enter для отмены: "
call "%WP_LIB%\desktop_io.cmd" input TERM
if not defined TERM exit /b 0
if not exist "%WP_RUN%" mkdir "%WP_RUN%" >nul 2>&1
set "_TF=%WP_RUN%\search.txt"
>"%_TF%" echo !TERM!
echo.
set "_SHITS=0"
for %%f in ("%WP_ROOT%\README.txt" "%WP_MAIN%\MANUAL_STEPS.txt" "%WP_MAIN%\EXTERNAL_TOOLS.txt") do (
    if exist "%%~f" (
        echo -- %%~nxf --
        findstr /i /n /g:"%_TF%" "%%~f" 2>nul
        if errorlevel 1 (
            echo   нет совпадений
        ) else (
            set /a _SHITS+=1
        )
        echo.
    ) else (
        echo -- %%~nxf отсутствует --
        echo.
    )
)
if "!_SHITS!"=="0" echo   Ничего не найдено ни в одном документе.
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
exit /b 0

rem ============================================================
rem  UNDO_HISTORY - история сессий на основе журналов.
rem  Журнал значений точнее любого текстового "undo history":
rem  он содержит и прежнее состояние, и тип операции.
rem ============================================================
:UNDO_HISTORY
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == ИСТОРИЯ СЕССИЙ ==
echo.
call "%WP_LIB%\backup.cmd" :SESSION_LIST
if "!SESS_COUNT!"=="0" (
    echo   Журналов нет: твики ещё не применялись.
    echo.
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    exit /b 0
)
for /l %%i in (1,1,!SESS_COUNT!) do (
    if %%i leq 15 (
        set "_HJ=%WP_BACKUPS%\!SESS_%%i!\journal.txt"
        set "_HN=0"
        for /f "usebackq delims=" %%L in ("!_HJ!") do set /a _HN+=1
        echo   [%%i] !SESS_%%i!   записей в журнале: !_HN!
    )
)
echo.
echo   [V] Показать журнал сессии
echo   [I] Необратимые операции по всем сессиям
echo   [R] Ротация: удалить старые сессии
echo   [0] Назад
echo.
set "WP_QUESTION=Ваш выбор: "
call "%WP_LIB%\desktop_io.cmd" choice VIR0
if errorlevel 4 exit /b 0
if errorlevel 3 goto :UH_ROTATE
if errorlevel 2 goto :UH_IRREV
goto :UH_VIEW

:UH_VIEW
set "_HVN="
call :ASK_NUM "Номер сессии: " !SESS_COUNT! _HVN
if errorlevel 1 goto :UNDO_HISTORY
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == ЖУРНАЛ !SESS_%_HVN%! ==
echo.
echo   Формат: ТИП^|ключ^|значение^|прежнее состояние
echo   ABSENT значит значения не было, откат его удалит.
echo.
findstr /n "^" "%WP_BACKUPS%\!SESS_%_HVN%!\journal.txt"
echo.
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :UNDO_HISTORY

:UH_IRREV
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == НЕОБРАТИМЫЕ ОПЕРАЦИИ ==
echo.
set "_HIC=0"
for /d %%d in ("%WP_BACKUPS%\*") do (
    if exist "%%~d\journal.txt" (
        findstr /b /c:"IRREVERSIBLE" "%%~d\journal.txt" >nul 2>&1
        if not errorlevel 1 (
            echo -- %%~nxd --
            findstr /b /c:"IRREVERSIBLE" "%%~d\journal.txt"
            set /a _HIC+=1
        )
    )
)
if "!_HIC!"=="0" echo   Необратимых операций не зафиксировано.
echo.
echo   Эти операции откат не вернёт. Appx переустанавливается через
echo   Add-AppxPackage -Register, файлы только из ваших бэкапов.
echo.
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :UNDO_HISTORY

:UH_ROTATE
if "!WP_DRYRUN!"=="1" (
    call "%WP_LIB%\core.cmd" :MSG "Предпросмотр: старые сессии сохранены"
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    goto :UNDO_HISTORY
)
set "_HK=!WP_KEEP_SESSIONS!"
if not defined _HK set "_HK=10"
call "%WP_LIB%\core.cmd" :MSG "Будет оставлено !_HK! свежих сессий, текущая не удаляется"
call "%WP_LIB%\core.cmd" :CONFIRM "Удалить старые журналы" N
if errorlevel 1 goto :UNDO_HISTORY
call "%WP_LIB%\backup.cmd" :SESSION_ROTATE "!_HK!"
if not errorlevel 1 call "%WP_LIB%\core.cmd" :OK "Ротация выполнена"
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :UNDO_HISTORY

rem ============================================================
rem  SAVE_PREFS - вызывается из настроек и при выходе
rem ============================================================
:SAVE_PREFS
if not defined PREF_FILE exit /b 1
if not defined USER_LEVEL set "USER_LEVEL=Novice"
if not defined ADVANCED_MODE set "ADVANCED_MODE=0"
if not defined TUTORIAL_SHOWN set "TUTORIAL_SHOWN=0"
if not defined WP_VISUAL_PROFILE set "WP_VISUAL_PROFILE=Balanced"
if not defined WP_DRYRUN set "WP_DRYRUN=0"
if not defined WP_BENCH_AUTO set "WP_BENCH_AUTO=1"
if not defined WP_KEEP_SESSIONS set "WP_KEEP_SESSIONS=10"
>"%PREF_FILE%" (
    echo LEVEL=!USER_LEVEL!
    echo ADVANCED=!ADVANCED_MODE!
    echo TUTORIAL=!TUTORIAL_SHOWN!
    echo VISUAL=!WP_VISUAL_PROFILE!
    echo VISUAL_CHOICE=!WP_VISUAL_CHOICE!
    echo DRYRUN=!WP_DRYRUN!
    echo BENCH_AUTO=!WP_BENCH_AUTO!
    echo KEEP_SESSIONS=!WP_KEEP_SESSIONS!
    echo AGREEMENT=%WP_VERSION%
)
exit /b 0

rem ============================================================
rem  SETTINGS_MENU
rem ============================================================
:SETTINGS_MENU
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == НАСТРОЙКИ WINPULSE ==
echo.
echo   [1] Уровень пользователя: !USER_LEVEL!
echo   [2] Advanced Mode:        !ADVANCED_MODE!
echo   [3] Песочница dry-run:    !WP_DRYRUN!
echo   [4] Выбор оформления:     !WP_VISUAL_CHOICE!
echo   [5] Замер до/после:       !WP_BENCH_AUTO!
echo   [6] Хранить сессий:       !WP_KEEP_SESSIONS!
echo   [7] Пройти туториал заново
echo   [8] Сбросить настройки
echo   [0] Назад
echo.
if "!WP_DRYRUN!"=="1" echo   ПЕСОЧНИКА ВКЛЮЧЕНА: ничего не пишется в систему.
if "!ADVANCED_MODE!"=="1" echo   ADVANCED: разблокированы danger и experimental.
echo.
set "_STKEYS=123456780"
set "_STMAP=1:ST_LEVEL 2:ST_ADV 3:ST_DRY 4:ST_VISUAL 5:ST_BENCH 6:ST_KEEP 7:ST_TUTORIAL 8:ST_RESET 0:ST_BACK"
set "WP_QUESTION=Ваш выбор: "
call "%WP_LIB%\desktop_io.cmd" choice %_STKEYS%
set /a "_STI=%errorlevel%-1"
set "_STK=!_STKEYS:~%_STI%,1!"
set "_STT="
for %%p in (%_STMAP%) do (
    for /f "tokens=1,2 delims=:" %%a in ("%%p") do (
        if /i "%%a"=="!_STK!" set "_STT=%%b"
    )
)
if not defined _STT goto :SETTINGS_MENU
goto :!_STT!

:ST_LEVEL
if /i "!USER_LEVEL!"=="Advanced" (set "USER_LEVEL=Novice") else (set "USER_LEVEL=Advanced")
call :SAVE_PREFS
goto :SETTINGS_MENU

:ST_ADV
if "!ADVANCED_MODE!"=="1" (
    set "ADVANCED_MODE=0"
) else (
    call "%WP_LIB%\core.cmd" :WARN "Advanced разблокирует danger и experimental твики"
    call "%WP_LIB%\core.cmd" :CONFIRM "Включить Advanced Mode" N
    if not errorlevel 1 set "ADVANCED_MODE=1"
)
call :SAVE_PREFS
goto :SETTINGS_MENU

:ST_DRY
if "!WP_DRYRUN!"=="1" (
    set "WP_DRYRUN=0"
    call "%WP_LIB%\core.cmd" :WARN "Песочница выключена: твики будут применяться по-настоящему"
) else (
    set "WP_DRYRUN=1"
    call "%WP_LIB%\core.cmd" :OK "Песочница включена: только план, без записи в систему"
)
call :SAVE_PREFS
goto :SETTINGS_MENU

:ST_VISUAL
echo.
echo   [1] Performance  Компактный Проводник, меньше эффектов и анимаций.
echo   [2] Balanced     Компактные строки, меню через 100 мс, сворачивание без анимации.
echo   [3] Comfort      Меню через 200 мс, сохраняет анимацию окон.
echo   [4] Keep         Пропустить оба блока оформления.
echo   [5] MotionOnly   Только анимация сворачивания и разворачивания окон.
echo   [6] Work         Меню через 100 мс, включает прозрачность.
echo   [7] Auto         Выбор по режиму и характеристикам ПК.
set "WP_QUESTION=Профиль: "
call "%WP_LIB%\desktop_io.cmd" choice 1234567
set "_VC=!errorlevel!"
for %%p in (1:Performance 2:Balanced 3:Comfort 4:Keep 5:MotionOnly 6:Work 7:Auto) do (
    for /f "tokens=1,2 delims=:" %%a in ("%%p") do if "!_VC!"=="%%a" set "WP_VISUAL_CHOICE=%%b"
)
call :SAVE_PREFS
goto :SETTINGS_MENU

:ST_BENCH
if "!WP_BENCH_AUTO!"=="1" (set "WP_BENCH_AUTO=0") else (set "WP_BENCH_AUTO=1")
call :SAVE_PREFS
goto :SETTINGS_MENU

:ST_KEEP
set "_STN="
call :ASK_NUM "Сколько сессий хранить, 1-99: " 99 _STN
if errorlevel 1 goto :SETTINGS_MENU
if !_STN! lss 1 goto :SETTINGS_MENU
set "WP_KEEP_SESSIONS=!_STN!"
call :SAVE_PREFS
goto :SETTINGS_MENU

:ST_TUTORIAL
set "TUTORIAL_SHOWN=0"
call :SAVE_PREFS
call "%WP_LIB%\core.cmd" :MSG "Туториал будет показан при возврате в главное меню"
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :SETTINGS_MENU

:ST_RESET
call "%WP_LIB%\core.cmd" :CONFIRM "Сбросить все настройки WinPulse" N
if errorlevel 1 goto :SETTINGS_MENU
set "USER_LEVEL=Novice"
set "ADVANCED_MODE=0"
set "TUTORIAL_SHOWN=0"
set "WP_VISUAL_PROFILE=Balanced"
set "WP_VISUAL_CHOICE=Auto"
set "WP_DRYRUN=0"
set "WP_BENCH_AUTO=1"
set "WP_KEEP_SESSIONS=10"
call :SAVE_PREFS
call "%WP_LIB%\core.cmd" :OK "Настройки сброшены, журналы и бэкапы не тронуты"
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :SETTINGS_MENU

:ST_BACK
call :SAVE_PREFS
exit /b 0

rem ============================================================
rem  SYSTEM_INFO_SCREEN - факты без вердиктов
rem ============================================================
:SYSTEM_INFO_SCREEN
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == ИНФОРМАЦИЯ О СИСТЕМЕ ==
echo.
echo   ОС:            !WIN_VER!
echo   Поддержка:     !WIN_SUPPORTED!    сборка !WIN_BUILD!.!WIN_UBR!
echo   Архитектура:   !WIN_ARCH!    режим !BOOT_MODE!    Secure Boot !SECURE_BOOT!
echo   Детект:        !DETECT_TIER!    не определено:!DETECT_MISSING!
echo   HKCU цель:     !WP_HKCU!
if "!HKCU_MISMATCH!"=="1" echo   Запуск от другого админа, пользовательские твики идут в его куст
echo.
echo   CPU:           !CPU_NAME!
echo   Ядра/потоки:   !CPU_CORES! / !CPU_THREADS!    SMT !CPU_SMT!    гибрид !CPU_HYBRID!
echo   Вендор/серия:  !CPU_VENDOR! / !CPU_SERIES!    поколение !CPU_GENERATION!
echo   GPU:           !GPU_NAME!
echo   Вендор GPU:    !GPU_VENDOR!    драйвер !GPU_DRIVER! от !GPU_DRIVER_DATE!
if defined GPU_HWID (echo   Instance path: !GPU_HWID!) else (echo   Instance path: не определён)
echo   RAM:           !RAM_GB! GB    достоверно !RAM_VALID!    частота !RAM_SPEED!
echo.
echo   Системный том: !SYS_DRIVE!    свободно !FREE_SPACE_GB! GB    известно !FREE_SPACE_KNOWN!
echo   Загрузочный:   !BOOT_DISK_NAME!
echo   Тип/шина:      !BOOT_DISK_TYPE! / !BOOT_DISK_BUS!
echo   Диски:         всего !DISK_COUNT!  HDD !HDD_COUNT!  неизвестно !DISK_UNKNOWN!  все SSD !ALL_SSD!
echo   Список:        !ALL_DISKS!
echo.
echo   BitLocker:     !BITLOCKER_STATUS!
echo   VBS:           !VBS_STATUS!    HVCI !HVCI_STATUS!
echo   Defender RT:   !DEFENDER_RT!    Tamper !DEFENDER_TAMPER!
echo   Сторонний AV:  !AV_THIRD!
echo   Точки восст.:  !RESTORE_COUNT!    защита тома !RESTORE_ENABLED!
echo   Корпус:        !CHASSIS!    ноутбук !IS_LAPTOP!    от батареи !ON_BATTERY!
echo   Zapret:        !ZAPRET_FOUND!    ожидает ребут !PENDING_REBOOT!
echo.
echo   Класс системы: !SYSTEM_CLASS!
echo   Слабый ПК:     !WEAK_PC!    причины:!WEAK_REASONS!
echo   Профиль визуала: !WP_VISUAL_PROFILE!
echo   Сессия:        %STAMP%
echo   Журнал:        %JOURNAL%
echo.
call "%WP_LIB%\guard.cmd" :G_BANNER
echo.
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
exit /b 0
rem ============================================================
rem  SMART_SCREEN  здоровье дисков. Только чтение, ничего не пишет.
rem  Счётчик -1 значит "не отдаётся", а не ноль.
rem ============================================================
:SMART_SCREEN
call "%WP_LIB%\core.cmd" :HEAD "Здоровье дисков"
set "_SMF=%WP_RUN%\smart.txt"
if exist "%_SMF%" del /f /q "%_SMF%" >nul 2>&1
call "%WP_LIB%\core.cmd" :PS_RUN get-smart "%_SMF%"
if not exist "%_SMF%" (
    call "%WP_LIB%\core.cmd" :FAIL "SMART: файл данных не создан"
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    exit /b 0
)
for /f "usebackq tokens=1,* delims==" %%a in ("%_SMF%") do set "%%a=%%b"
if not defined SM_COUNT set /a SM_COUNT=0
if !SM_COUNT! equ 0 (
    call "%WP_LIB%\core.cmd" :WARN "Storage-стек не перечислил диски"
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    exit /b 0
)
set /a SM_WARN=0
set /a SM_CRIT=0
for /l %%i in (1,1,!SM_COUNT!) do (
    if not defined SM_%%i_TEMP set "SM_%%i_TEMP=-1"
    if not defined SM_%%i_WEAR set "SM_%%i_WEAR=-1"
    if not defined SM_%%i_POH set "SM_%%i_POH=-1"
    if not defined SM_%%i_RUNC set "SM_%%i_RUNC=-1"
    if not defined SM_%%i_WUNC set "SM_%%i_WUNC=-1"
    echo.
    echo   [%%i] !SM_%%i_NAME!
    echo       !SM_%%i_MEDIA! / !SM_%%i_BUS!   !SM_%%i_SIZE_GB! ГБ   Health: !SM_%%i_HEALTH!
    if "!SM_%%i_SMART!"=="OK" (
        set /a _tw=45
        set /a _tc=55
        set /a _wr=SM_%%i_WEAR
        if /i "!SM_%%i_MEDIA!"=="SSD" set /a _tw=55
        if /i "!SM_%%i_MEDIA!"=="SSD" set /a _tc=65
        if /i "!SM_%%i_MEDIA!"=="HDD" set /a _wr=-1
        if !SM_%%i_TEMP! geq !_tc! (
            echo       [CRIT] Температура !SM_%%i_TEMP! C
            set /a SM_CRIT+=1
        ) else if !SM_%%i_TEMP! geq !_tw! (
            echo       [WARN] Температура !SM_%%i_TEMP! C
            set /a SM_WARN+=1
        ) else if !SM_%%i_TEMP! geq 0 (
            echo       Температура !SM_%%i_TEMP! C
        ) else (
            echo       Температура не отдаётся
        )
        if !_wr! geq 90 (
            echo       [CRIT] Износ !_wr! процентов
            set /a SM_CRIT+=1
        ) else if !_wr! geq 70 (
            echo       [WARN] Износ !_wr! процентов
            set /a SM_WARN+=1
        ) else if !_wr! geq 0 (
            echo       Износ !_wr! процентов, ноль может быть заглушкой
        )
        if !SM_%%i_POH! geq 0 (
            set /a _smd=SM_%%i_POH/24
            echo       Наработка !SM_%%i_POH! ч, около !_smd! суток
        )
        if !SM_%%i_RUNC! gtr 0 (
            echo       [CRIT] Неисправимых ошибок чтения: !SM_%%i_RUNC!
            set /a SM_CRIT+=1
        )
        if !SM_%%i_WUNC! gtr 0 (
            echo       [CRIT] Неисправимых ошибок записи: !SM_%%i_WUNC!
            set /a SM_CRIT+=1
        )
        if !SM_%%i_RERR! gtr 0 echo       Всего ошибок чтения !SM_%%i_RERR!, исправимых
    ) else (
        echo       SMART недоступен: драйвер или контроллер не отдаёт счётчики
    )
)
echo.
if !SM_CRIT! gtr 0 (
    call "%WP_LIB%\core.cmd" :FAIL "Критичных признаков !SM_CRIT!. Копируй важное на другой носитель сейчас."
) else if !SM_WARN! gtr 0 (
    call "%WP_LIB%\core.cmd" :WARN "Предупреждений !SM_WARN!. Наблюдай в динамике."
) else (
    call "%WP_LIB%\core.cmd" :OK "Явных признаков деградации нет"
)
echo.
echo   SMART не предсказывает отказ. Диск может умереть при нулевых ошибках.
echo   Единственная защита данных - отдельная копия на другом носителе.
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
exit /b 0
rem ============================================================
rem  AUTORUN_SCREEN - интерактивный редактор автозагрузки.
rem  Инструмент, не твик: в счётчик операций не входит.
rem  Выбор вручную, whitelist не применяется. Откат группа A.
rem ============================================================
:AUTORUN_SCREEN
set "AR_SHOWN=0"
if exist "%WP_RUN%\ar.txt" del /q "%WP_RUN%\ar.txt"
call "%WP_LIB%\core.cmd" :PS_RUN get-autorun "%WP_RUN%\ar.txt"
call "%WP_LIB%\backup.cmd" :LOAD_KV "%WP_RUN%\ar.txt"
if not defined AR_SHOWN set /a AR_SHOWN=0
if !AR_SHOWN! equ 0 (
    call "%WP_LIB%\core.cmd" :HEAD "АВТОЗАГРУЗКА"
    call "%WP_LIB%\core.cmd" :WARN "Записей не найдено или чтение не удалось"
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    exit /b 0
)
for /l %%i in (1,1,40) do set "AR_SEL_%%i=0"
set /a AR_PAGE=1
set "AR_MSG="
:AR_LOOP
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
call "%WP_LIB%\core.cmd" :HEAD "АВТОЗАГРУЗКА"
if "!WP_DRYRUN!"=="1" echo   [DRY-RUN] только план, записи в систему нет
echo   Записей !AR_TOTAL!   без подписи !AR_UNSIGN!   битых путей !AR_MISSING!
echo   IFEO-блокировщиков !AR_VEC_IFEO!   подозрительных !AR_IFEO_SUSPECT!
echo.
if defined AR_MSG echo   !AR_MSG!
if defined AR_MSG echo.
set /a "_ps=(AR_PAGE-1)*15+1"
set /a "_pe=AR_PAGE*15"
if !_pe! gtr !AR_SHOWN! set /a _pe=AR_SHOWN
for /l %%i in (!_ps!,1,!_pe!) do (
    set "_mk= "
    if "!AR_SEL_%%i!"=="1" set "_mk=x"
    set "_nm=!AR_E%%i_NAME!                                   "
    set "_nm=!_nm:~0,35!"
    set "_sc=!AR_E%%i_SRC!               "
    set "_sc=!_sc:~0,14!"
    set "_sg=!AR_E%%i_SIGN!           "
    set "_sg=!_sg:~0,11!"
    if defined WP_DESKTOP_TOKEN (
        echo !WP_DESKTOP_TOKEN!:startup^|%%i^|!AR_SEL_%%i!^|!AR_E%%i_NAME!^|!AR_E%%i_SRC!^|!AR_E%%i_SIGN!
    ) else echo   %%i [!_mk!] !_nm! !_sc! !_sg!
)
echo.
echo   Номера через запятую - выбрать.  A все   N снять   S страница
echo   X применить выбранное   Q назад
echo.
set "AR_IN="
set "WP_QUESTION=Ввод: "
call "%WP_LIB%\desktop_io.cmd" input AR_IN
if not defined AR_IN goto :AR_LOOP
for /f "tokens=1 delims= " %%a in ("!AR_IN!") do set "AR_CMD=%%a"
if /i "!AR_CMD!"=="Q" exit /b 0
if /i "!AR_CMD!"=="S" (
    set /a AR_PAGE+=1
    set /a "_pm=(AR_SHOWN+14)/15"
    if !AR_PAGE! gtr !_pm! set /a AR_PAGE=1
    set "AR_MSG="
    goto :AR_LOOP
)
if /i "!AR_CMD!"=="A" (
    for /l %%i in (1,1,!AR_SHOWN!) do set "AR_SEL_%%i=1"
    set "AR_MSG=Выбрано всё"
    goto :AR_LOOP
)
if /i "!AR_CMD!"=="N" (
    for /l %%i in (1,1,!AR_SHOWN!) do set "AR_SEL_%%i=0"
    set "AR_MSG=Выбор снят"
    goto :AR_LOOP
)
if /i "!AR_CMD!"=="X" goto :AR_APPLY
set AR_IN | "%SystemRoot%\System32\findstr.exe" /r /x /c:"AR_IN=[0-9][0-9, ]*" >nul
if errorlevel 1 (
    set "AR_MSG=Введи номера через запятую или команду меню."
    goto :AR_LOOP
)
set "AR_TOK=!AR_IN:,= !"
set /a _hit=0
for %%n in (!AR_TOK!) do (
    set /a "_v=%%n" 2>nul
    if !_v! geq 1 if !_v! leq !AR_SHOWN! (
        if "!AR_SEL_%%n!"=="1" (set "AR_SEL_%%n=0") else (set "AR_SEL_%%n=1")
        set /a _hit+=1
    )
)
if !_hit! equ 0 (set "AR_MSG=Не распознано: !AR_IN!") else (set "AR_MSG=")
goto :AR_LOOP

:AR_APPLY
set /a _ap=0
for /l %%i in (1,1,!AR_SHOWN!) do (
    if "!AR_SEL_%%i!"=="1" call :AR_DISABLE %%i
)
if !_ap! equ 0 (
    set "AR_MSG=Ничего не выбрано"
    goto :AR_LOOP
)
call "%WP_LIB%\core.cmd" :OK "Обработано записей: !_ap!"
call "%WP_LIB%\core.cmd" :MSG "Откат: меню O, группа A"
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
exit /b 0

:AR_DISABLE
set "_i=%~1"
if not "!AR_E%_i%_EDITABLE!"=="1" (
    call "%WP_LIB%\core.cmd" :WARN "Имя нельзя точно передать через CMD. Откройте Автозагрузку Windows или исходную задачу."
    exit /b 1
)
set "_src=!AR_E%_i%_SRC!"
set "_nm=!AR_E%_i%_NAME!"
set "_ak="
if /i "!_src!"=="HKCU_RUN" set "_ak=HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
if /i "!_src!"=="HKCU_RUNONCE" set "_ak=HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce"
if /i "!_src!"=="HKLM_RUN" set "_ak=HKLM\Software\Microsoft\Windows\CurrentVersion\Run"
if /i "!_src!"=="HKLM_RUNONCE" set "_ak=HKLM\Software\Microsoft\Windows\CurrentVersion\RunOnce"
if /i "!_src!"=="HKLM_WOW_RUN" set "_ak=HKLM\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Run"
if defined _ak (
    call "%WP_LIB%\core.cmd" :REG_DEL "!_ak!" "!_nm!"
    if errorlevel 1 exit /b 1
    set /a _ap+=1
    set "AR_SEL_%_i%=0"
    exit /b 0
)
if /i "!_src!"=="TASKS_LOGON" (
    call "%WP_LIB%\core.cmd" :TASK_DISABLE "!AR_E%_i%_PATH!"
    if errorlevel 1 exit /b 1
    set /a _ap+=1
    set "AR_SEL_%_i%=0"
    exit /b 0
)
if /i "!_src!"=="STARTUP_USER" (
    call "%WP_LIB%\core.cmd" :LNK_MOVE "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\!_nm!.lnk"
    if errorlevel 1 exit /b 1
    set /a _ap+=1
    set "AR_SEL_%_i%=0"
    exit /b 0
)
if /i "!_src!"=="STARTUP_COMMON" (
    call "%WP_LIB%\core.cmd" :LNK_MOVE "%ProgramData%\Microsoft\Windows\Start Menu\Programs\Startup\!_nm!.lnk"
    if errorlevel 1 exit /b 1
    set /a _ap+=1
    set "AR_SEL_%_i%=0"
    exit /b 0
)
call "%WP_LIB%\core.cmd" :WARN "Неизвестный источник: !_src!"
exit /b 0
rem ============================================================
rem  FRAMETIME_SCREEN - замер frametime через PresentMon.
rem  Бинарник не поставляется, ищется в Tools, корне и PATH.
rem  Инструмент, не твик: в счётчик операций не входит.
rem ============================================================
:FRAMETIME_SCREEN
call "%WP_LIB%\core.cmd" :HEAD "ЗАМЕР FRAMETIME"
set "_PM="
if exist "%WP_ROOT%\Tools\PresentMon.exe" set "_PM=%WP_ROOT%\Tools\PresentMon.exe"
if not defined _PM if exist "%WP_ROOT%\PresentMon.exe" set "_PM=%WP_ROOT%\PresentMon.exe"
if not defined _PM for %%p in (PresentMon.exe) do if not "%%~$PATH:p"=="" set "_PM=%%~$PATH:p"
if not defined _PM (
    call "%WP_LIB%\core.cmd" :WARN "PresentMon.exe не найден"
    echo.
    echo   Скачай релиз: github.com/GameTechDev/PresentMon
    echo   Положи PresentMon.exe в любой из путей:
    echo     %WP_ROOT%\Tools\PresentMon.exe
    echo     %WP_ROOT%\PresentMon.exe
    echo     или в каталог из PATH
    echo.
    echo   Бинарник сторонний, WinPulse его не поставляет и не скачивает.
    echo   GUI-альтернатива: CapFrameX, capframex.com
    echo.
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    exit /b 0
)
call "%WP_LIB%\core.cmd" :OK "Найден: !_PM!"
echo.
echo   Замер идёт через ETW, нужны права администратора.
echo   [!] Не запускай в матчмейкинге с FACEIT или Vanguard.
echo       Античиты могут счесть ETW-сбор подозрительным.
echo       Меряй в тренировке, оффлайне или на демо.
echo.
echo   Введи имя процесса игры, например cs2.exe
echo   Пустой ввод - выход.
echo.
set "_PN="
set "WP_QUESTION=Процесс: "
call "%WP_LIB%\desktop_io.cmd" input _PN
if not defined _PN exit /b 0
set "_PD="
set "WP_QUESTION=Длительность секунд, Enter для 60: "
call "%WP_LIB%\desktop_io.cmd" input _PD
if not defined _PD set "_PD=60"
set /a _PDI=_PD 2>nul
if !_PDI! lss 5 set /a _PDI=5
if !_PDI! gtr 600 set /a _PDI=600
set "_PC=%WP_LOGS%\frametime_%STAMP%.csv"
echo.
call "%WP_LIB%\core.cmd" :MSG "Запуск игры и запись !_PDI! секунд. Сверни это окно после старта."
call "%WP_LIB%\core.cmd" :CONFIRM "Начать запись" N
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :MSG "Отменено"
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    exit /b 0
)
if exist "!_PC!" del /f /q "!_PC!" >nul 2>&1
"!_PM!" -process_name "!_PN!" -output_file "!_PC!" -timed !_PDI! >nul 2>&1
if not exist "!_PC!" (
    call "%WP_LIB%\core.cmd" :FAIL "CSV не создан"
    echo   Проверь: игра запущена, имя процесса верное, права администратора.
    echo   У PresentMon 2.x синтаксис может отличаться, сверь с его --help.
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    exit /b 0
)
call "%WP_LIB%\core.cmd" :OK "Записано: !_PC!"
set "FT_OK=0"
set "FT_SERIES="
if exist "%WP_RUN%\ftm.txt" del /q "%WP_RUN%\ftm.txt"
call "%WP_LIB%\core.cmd" :PS_RUN get-frametime "%WP_RUN%\ftm.txt" "!_PC!"
call "%WP_LIB%\backup.cmd" :LOAD_KV "%WP_RUN%\ftm.txt"
echo.
if "!FT_OK!"=="1" (
    if defined WP_DESKTOP_TOKEN echo !WP_DESKTOP_TOKEN!:frames^|!FT_SERIES!^|!FT_FRAMES!^|!FT_LOW1_FPS!^|!FT_LOW01_FPS!
    echo   Кадров:            !FT_FRAMES!
    echo   Средний frametime: !FT_AVG_MS! ms
    echo   Средний FPS:       !FT_AVG_FPS!
    echo   1%% low:            !FT_LOW1_FPS!
    echo   0.1%% low:          !FT_LOW01_FPS!
    echo   Отклонение:        !FT_STDDEV_MS! ms
    echo   Худший кадр:       !FT_WORST_MS! ms
    echo.
    echo   Сравнивай 1%% low и отклонение, а не средний FPS.
    echo   Разница меньше 5%% на повторяемых замерах - шум.
) else (
    call "%WP_LIB%\core.cmd" :WARN "Разбор не удался: !FT_ERR!"
    if defined FT_COLS echo   Колонки CSV: !FT_COLS!
    echo   CSV сохранён, разбери его в CapFrameX или Excel.
)
echo.
echo   Файл: !_PC!
echo.
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
exit /b 0

rem ============================================================
rem  ST_GROUP_BEGIN / ST_GROUP_END / ST_SUMMARY
rem  Снимок глобальных счётчиков CHK на границах группы.
rem  Параллельной логики проверок нет: считаются те же счётчики.
rem ============================================================
:ST_GROUP_BEGIN
set "_SG_NAME=%~1"
set /a ST_G_N+=1
set "ST_G_!ST_G_N!_NAME=!_SG_NAME!"
set /a _SG_OK0=TOOL_CHK_OK
set /a _SG_NE0=TOOL_CHK_NE
set /a _SG_AB0=TOOL_CHK_ABSENT
echo -- !_SG_NAME! --
exit /b 0

:ST_GROUP_END
if not defined ST_G_N exit /b 0
set /a "_dOK=TOOL_CHK_OK-_SG_OK0"
set /a "_dNE=TOOL_CHK_NE-_SG_NE0"
set /a "_dAB=TOOL_CHK_ABSENT-_SG_AB0"
set "ST_G_!ST_G_N!_OK=!_dOK!"
set "ST_G_!ST_G_N!_NE=!_dNE!"
set "ST_G_!ST_G_N!_AB=!_dAB!"
if defined WP_DESKTOP_TOKEN echo !WP_DESKTOP_TOKEN!:status^|!_SG_NAME!^|!_dOK!^|!_dNE!^|!_dAB!
set /a "_dAll=_dOK+_dNE+_dAB"
if !_dAll! equ 0 (
    set "ST_G_!ST_G_N!_ST=только факты"
    echo   Итог группы: только факты, проверок нет
    exit /b 0
)
set "_st=применена"
if !_dNE! gtr 0 set "_st=частично"
if !_dOK! equ 0 if !_dNE! gtr 0 set "_st=не применена"
if !_dOK! equ 0 if !_dNE! equ 0 set "_st=не применена"
set "ST_G_!ST_G_N!_ST=!_st!"
echo   Итог группы: !_st!   OK !_dOK!  NE !_dNE!  -- !_dAB!
exit /b 0

:ST_SUMMARY
if not defined ST_G_N exit /b 0
echo.
echo == СВОДКА ПО ГРУППАМ ==
echo.
for /l %%i in (1,1,!ST_G_N!) do (
    set "_gn=!ST_G_%%i_NAME!                              "
    set "_gn=!_gn:~0,30!"
    set "_go=!ST_G_%%i_OK!"
    set "_ge=!ST_G_%%i_NE!"
    set "_ga=!ST_G_%%i_AB!"
    set "_gs=!ST_G_%%i_ST!"
    if not defined _gs set "_gs=неизвестно"
    set "_pad=            "
    if "!_gs!"=="применена" set "_pad=            "
    if "!_gs!"=="частично" set "_pad=             "
    if "!_gs!"=="не применена" set "_pad=         "
    if "!_gs!"=="только факты" set "_pad=         "
    echo   !_gn! !_gs!!_pad! OK !_go!  NE !_ge!  -- !_ga!
)
echo.
echo   Всего: OK !TOOL_CHK_OK!   NE !TOOL_CHK_NE!   отсутствует !TOOL_CHK_ABSENT!
echo   NE не ошибка: блок мог быть не применён или откатан.
echo   только факты - группа без проверок, состояние не утверждается.
exit /b 0

:CHK_NIC
set "NIC_COUNT="
set "NIC_ETH_PHYS="
set "_NSF=%WP_RUN%\nic_st.txt"
if exist "!_NSF!" del /f /q "!_NSF!" >nul 2>&1
call "%WP_LIB%\core.cmd" :PS_RUN get-nic "!_NSF!"
if not exist "!_NSF!" (
    echo   [--] get-nic не создал файл ответа, PS-движок не отработал
    set /a TOOL_CHK_ABSENT+=1
    exit /b 0
)
call "%WP_LIB%\backup.cmd" :LOAD_KV "!_NSF!"
if not defined NIC_COUNT (
    echo   [--] get-nic ответил без NIC_COUNT, отказ внутри verb
    if defined PS_FAILURES echo      PS_FAILURES: !PS_FAILURES!
    set /a TOOL_CHK_ABSENT+=1
    exit /b 0
)
if !NIC_COUNT! equ 0 (
    echo   [--] веток адаптеров не найдено: база !NIC_BASE_EXISTS!, подузлов !NIC_SUBKEYS!
    set /a TOOL_CHK_ABSENT+=1
    exit /b 0
)
set /a _nel=0
for /l %%n in (1,1,!NIC_COUNT!) do (
    if "!NIC_%%n_ELIG!"=="1" (
        set /a _nel+=1
        call :CHK_NIC_ONE %%n
    )
)
if !_nel! equ 0 (
    echo   [--] веток !NIC_COUNT!, допущенных нет: все виртуальные или WiFi
    echo      физических Ethernet по Get-NetAdapter: !NIC_ETH_PHYS!
    set /a TOOL_CHK_ABSENT+=1
)
exit /b 0

:CHK_NIC_ONE
set "_i=%~1"
set "_nm=!NIC_%_i%_NAME!                                   "
set "_nm=!_nm:~0,35!"
set /a _tot=0
set /a _good=0
for /l %%k in (1,1,14) do (
    set "_hs=!NIC_%_i%_K%%k!"
    set "_cv=!NIC_%_i%_V%%k!"
    set "_tg=0"
    if %%k equ 14 set "_tg=1"
    if "!_hs!"=="1" (
        set /a _tot+=1
        if "!_cv!"=="!_tg!" set /a _good+=1
    )
)
if !_tot! equ 0 (
    echo   [--] !_nm! : драйвер не публикует ключи
    set /a TOOL_CHK_ABSENT+=1
    exit /b 0
)
if !_good! equ !_tot! (
    echo   [OK] !_nm! : !_good! из !_tot! в цели
    set /a TOOL_CHK_OK+=1
) else (
    echo   [NE] !_nm! : !_good! из !_tot! в цели
    set /a TOOL_CHK_NE+=1
)
exit /b 0

:: END OF FILE | Всего твиков в файле: 0

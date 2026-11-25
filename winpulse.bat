@echo off
rem ============================================================
rem  WinPulse 7.1 "Rebuild"  |  winpulse.bat  |  ЧАСТЬ 1/2
rem  Проводка: preflight, selftest, меню, оркестрация режимов.
rem
rem  Кодировка ЭТОГО файла: UTF-8 БЕЗ BOM, CRLF.
rem  lib\*.cmd  UTF-8 без BOM.  lib\wp.ps1  UTF-8 С BOM.
rem  Символ "!" в echo запрещён: его съедает delayed expansion.
rem
rem  Запуск: от администратора. Ключи: /dryrun /advanced /?
rem  Путь без ! %% ^ & - лучше C:\WinPulseRelease
rem
rem  Здесь НЕ определяется ни один твик. Только вызов модулей.
rem ============================================================
setlocal DisableDelayedExpansion
set "WP_ROOT=%~dp0"
setlocal EnableDelayedExpansion
set "WP_VERSION=7.1"
set "WP_CODENAME=Rebuild"
set "WP_EXIT_CODE=0"
set "OLD_CP="
for /f "tokens=2 delims=:" %%a in ('chcp 2^>nul') do set "OLD_CP=%%a"
if defined OLD_CP for /f "tokens=* delims= " %%a in ("!OLD_CP!") do set "OLD_CP=%%a"
chcp 65001 >nul 2>&1
set "PATH=%SystemRoot%\System32;%SystemRoot%;%SystemRoot%\System32\WindowsPowerShell\v1.0;%SystemRoot%\System32\Wbem"
title WinPulse %WP_VERSION% %WP_CODENAME%
color 0A

if "!WP_ROOT:~-1!"=="\" set "WP_ROOT=!WP_ROOT:~0,-1!"
set "WP_LIB=!WP_ROOT!\lib"
set "WP_MAIN=!WP_ROOT!\Main"
set "WP_BACKUPS=!WP_ROOT!\Backups"
set "WP_LOGS=!WP_ROOT!\Logs"
set "WP_RUN=!WP_ROOT!\.run"
set "PREF_FILE=!WP_ROOT!\.user_preference"
set "AGREE_FILE=!WP_ROOT!\.agreement_accepted"
set "LOCK_FILE=!WP_RUN!\winpulse.lock"

set "WP_DRYRUN=0"
set "WP_UNATTENDED=0"
set "CLI_DRYRUN="
set "CLI_ADVANCED="
set "CLI_HELP=0"
set "CLI_OPEN="
set "CLI_VISUAL="
set "DESKTOP_ENTERED=0"
set "ADVANCED_MODE=0"
set "USER_LEVEL=Novice"
set "TUTORIAL_SHOWN=0"
set "WP_VISUAL_PROFILE=Balanced"
set "WP_VISUAL_CHOICE=Auto"
set "WP_BENCH_AUTO=1"
set "WP_KEEP_SESSIONS=10"
set "WP_RP_OK=0"
set "WP_RP_SEQ="
set "WP_RP_SKIPPED=0"
set "WP_BCD_SUSPENDED=0"
set "WP_REBOOT_REQUIRED=0"
set "WP_SECURITY_REDUCED=0"
set "WP_DEF_PROTECTION_REDUCED=0"
set "WP_SEC_LOADED=0"
set "WP_IRREVERSIBLE=0"
set "WP_HKCU=HKCU"
set "WP_BENCH_BASELINE="
set "WP_BENCH_FINAL="
set /a WP_OP_OK=0
set /a WP_OP_FAIL=0
set /a WP_OP_SKIP=0
set /a WP_OP_PLAN=0

rem --- 64-bit: PROCESSOR_ARCHITEW6432 определён только когда
rem     32-битный cmd работает на 64-битной ОС. В 6.x условие
rem     было инвертировано и перезапуск не срабатывал никогда.
rem     Идёт ДО создания лока, иначе дочерний упрётся в свой же лок.
if defined PROCESSOR_ARCHITEW6432 (
    if exist "%SystemRoot%\Sysnative\cmd.exe" (
        "%SystemRoot%\Sysnative\cmd.exe" /c ""%~f0" %*"
        exit /b
    )
)

:PARSE_ARGS
if [%1]==[] goto :ARGS_DONE
for %%p in (LITE MINIMUM MEDIUM WORK MAXIMUM EXPERIMENTAL ROLLBACK STATUS DIAG MAINT RESTORE PANELS BENCH BOOTTIME HISTORY MATRIX DETECTREPAIR SETTINGS SYSINFO SEARCH CONSTRUCTOR SMART AUTORUN FRAMETIME) do if /i "%~1"=="/open-%%p" (
    set "CLI_OPEN=%%p"
    goto :ARG_NEXT
)
for %%p in (Auto MotionOnly Keep Comfort Work Balanced Performance) do if /i "%~1"=="/visual-%%p" (
    set "CLI_VISUAL=%%p"
    goto :ARG_NEXT
)
if /i "%~1"=="/dryrun" goto :ARG_DRY
if /i "%~1"=="--dry-run" goto :ARG_DRY
if /i "%~1"=="/live" goto :ARG_LIVE
if /i "%~1"=="/advanced" (set "CLI_ADVANCED=1" & goto :ARG_NEXT)
if /i "%~1"=="/?" (set "CLI_HELP=1" & goto :ARG_NEXT)
if /i "%~1"=="/help" (set "CLI_HELP=1" & goto :ARG_NEXT)
:ARG_BAD
echo Ошибка аргументов. Для справки используйте /?.
if defined OLD_CP chcp !OLD_CP! >nul 2>&1
endlocal & exit /b 2
:ARG_DRY
if "!CLI_DRYRUN!"=="0" goto :ARG_BAD
set "CLI_DRYRUN=1"
goto :ARG_NEXT
:ARG_LIVE
if "!CLI_DRYRUN!"=="1" goto :ARG_BAD
set "CLI_DRYRUN=0"
:ARG_NEXT
shift
goto :PARSE_ARGS
:ARGS_DONE
if "!CLI_HELP!"=="1" goto :SHOW_USAGE

if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == WinPulse %WP_VERSION% %WP_CODENAME% ==
echo.
echo   Preflight:
if "!WP_DRYRUN!"=="1" echo   [MODE] ПЕСОЧНИКА: только план, без записи в систему

rem --- Админ через fltmc: не зависит от службы Server,
rem     в отличие от net session, который отваливался при её отключении.
fltmc >nul 2>&1
if errorlevel 1 goto :ERR_NOT_ADMIN
echo   [OK] права администратора

call :VALIDATE_PATH
if not "!PATH_BAD!"=="0" goto :ERR_BAD_PATH
echo   [OK] путь: !WP_ROOT!

if not exist "!WP_LIB!\desktop_io.cmd" (
    echo Отсутствует lib\desktop_io.cmd. Восстановите комплект WinPulse.
    exit /b 1
)
if not exist "!WP_LIB!\core.cmd" goto :ERR_NO_LIB
for %%d in ("!WP_MAIN!" "!WP_BACKUPS!" "!WP_LOGS!" "!WP_RUN!") do (
    if not exist "%%~d" mkdir "%%~d" >nul 2>&1
)
echo   [OK] каталоги

set "LOCK_ENTERED="
call :LOCK_OK 9>>"!LOCK_FILE!"
set "RUN_RC=!errorlevel!"
if not defined LOCK_ENTERED goto :LOCK_EXISTS
exit /b !RUN_RC!

:LOCK_OK
set "LOCK_ENTERED=1"
echo   [OK] блокировка экземпляра

echo   [..] метка сессии: PowerShell, 1-3 секунды
set "STAMP="
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul`) do set "STAMP=%%i"
if not defined STAMP (
    set "STAMP=r%RANDOM%%RANDOM%"
    echo   [WARN] PowerShell не ответил, метка случайная
)
set "STAMP=!STAMP: =0!"
:RESERVE_SESSION
set "WP_SESSION_DIR=!WP_BACKUPS!\!STAMP!"
if exist "!WP_SESSION_DIR!" goto :NEW_STAMP
if exist "!WP_LOGS!\session_!STAMP!.log" goto :NEW_STAMP
if exist "!WP_LOGS!\errors_!STAMP!.log" goto :NEW_STAMP
mkdir "!WP_SESSION_DIR!" >nul 2>&1
if errorlevel 1 goto :ERR_BACKUPS_RO
goto :SESSION_RESERVED
:NEW_STAMP
set "STAMP=r%RANDOM%%RANDOM%"
goto :RESERVE_SESSION
:SESSION_RESERVED
set "SESSION_LOG=!WP_LOGS!\session_!STAMP!.log"
set "ERROR_LOG=!WP_LOGS!\errors_!STAMP!.log"
set "PLAN_LOG=!WP_SESSION_DIR!\plan.txt"
set "JOURNAL=!WP_SESSION_DIR!\journal.txt"
>"!SESSION_LOG!" echo WinPulse %WP_VERSION% %WP_CODENAME% session !STAMP!
>"!ERROR_LOG!" echo WinPulse %WP_VERSION% errors !STAMP!
if not exist "!SESSION_LOG!" goto :ERR_LOGS_RO
if not exist "!ERROR_LOG!" goto :ERR_LOGS_RO
echo   [OK] сессия !STAMP!

echo   [..] selftest: метки и команды PowerShell, 2-4 секунды
call :SELFTEST
if not "!ST_MISSING!"=="0" goto :ERR_SELFTEST
echo   [OK] selftest модулей и меток

call :LOAD_PREFS
if "!CLI_ADVANCED!"=="1" set "ADVANCED_MODE=1"
call :MENU_DEFS
call :MENU_SELFTEST
if not "!MENU_BAD!"=="0" goto :ERR_MENU_MAP
echo   [OK] карта меню согласована

if not exist "!AGREE_FILE!" goto :AGREEMENT
set "AGREE_VER="
for /f "usebackq delims=" %%a in ("!AGREE_FILE!") do if not defined AGREE_VER set "AGREE_VER=%%a"
if not "!AGREE_VER!"=="%WP_VERSION%" goto :AGREEMENT

call :DETECT_ALL_MAIN
if errorlevel 3 goto :ERR_BACKUPS_RO
if errorlevel 2 goto :EXIT
if errorlevel 1 goto :ERR_UNSUPPORTED
call :POST_DETECT_WARN
goto :MAIN_MENU

rem ============================================================
rem  DETECT_ALL_MAIN - единственная точка запуска детекта и гейтов.
rem  Вызывается и из preflight, и после принятия соглашения.
rem  0 = можно работать, 1 = сборка не поддержана, 2 = отказ BitLocker
rem ============================================================
:DETECT_ALL_MAIN
call "%WP_LIB%\backup.cmd" :SESSION_INIT
if errorlevel 1 exit /b 3
call "%WP_LIB%\detect.cmd" :DETECT_ALL
if not "!WIN_SUPPORTED!"=="1" exit /b 1
if /i "!BITLOCKER_STATUS!"=="Enabled" (
    call :BITLOCKER_GATE
    if errorlevel 1 exit /b 2
)
exit /b 0

:POST_DETECT_WARN
if "!ZAPRET_FOUND!"=="1" (
    echo.
    echo   [WARN] Обнаружен Zapret или winws.
    echo   Сетевые твики ухудшат его работу. Это ожидаемо.
    echo   После применения переустанови Zapret из его собственного меню.
)
if "!PENDING_REBOOT!"=="1" (
    echo.
    echo   [WARN] Windows ожидает перезагрузку. Часть твиков применится некорректно.
)
exit /b 0

rem ============================================================
rem  VALIDATE_PATH - проверка запрещённых символов.
rem  Delayed expansion выключается локально: иначе ! и %%
rem  невозможно проверить, их съедает сам парсер.
rem ============================================================
:VALIDATE_PATH
set "PATH_BAD=1"
powershell -NoProfile -NonInteractive -Command "if ($env:WP_ROOT.IndexOfAny([char[]](33,37,94,38)) -ge 0) { exit 1 }"
if not errorlevel 1 set "PATH_BAD=0"
exit /b 0

rem ============================================================
rem  LOAD_PREFS
rem ============================================================
:LOAD_PREFS
if not exist "!PREF_FILE!" goto :LOAD_PREFS_CLI
for /f "usebackq tokens=1,* delims==" %%a in ("!PREF_FILE!") do (
    if /i "%%a"=="LEVEL" set "USER_LEVEL=%%b"
    if /i "%%a"=="ADVANCED" set "ADVANCED_MODE=%%b"
    if /i "%%a"=="TUTORIAL" set "TUTORIAL_SHOWN=%%b"
    if /i "%%a"=="VISUAL_CHOICE" for %%p in (Auto Keep MotionOnly Work Comfort Balanced Performance) do if /i "%%b"=="%%p" set "WP_VISUAL_CHOICE=%%p"
    if /i "%%a"=="VISUAL" set "WP_VISUAL_PROFILE=%%b"
    if /i "%%a"=="DRYRUN" set "WP_DRYRUN=%%b"
    if /i "%%a"=="BENCH_AUTO" set "WP_BENCH_AUTO=%%b"
    if /i "%%a"=="KEEP_SESSIONS" set "WP_KEEP_SESSIONS=%%b"
)
if not "!ADVANCED_MODE!"=="1" set "ADVANCED_MODE=0"
if not "!WP_DRYRUN!"=="1" set "WP_DRYRUN=0"
if not "!WP_BENCH_AUTO!"=="1" set "WP_BENCH_AUTO=0"
if not defined WP_KEEP_SESSIONS set "WP_KEEP_SESSIONS=10"
:LOAD_PREFS_CLI
if defined CLI_DRYRUN set "WP_DRYRUN=!CLI_DRYRUN!"
if defined CLI_ADVANCED set "ADVANCED_MODE=!CLI_ADVANCED!"
if "!WP_DRYRUN!"=="1" echo   [MODE] ПЕСОЧНИКА: только план, записи в систему нет
exit /b 0

rem ============================================================
rem  SELFTEST - файлы, метки, verb'ы PowerShell.
rem  Отсутствие метки в CALL убивает весь батник, поэтому
rem  проверяем ДО первого вызова, а не ловим падение потом.
rem ============================================================
:SELFTEST
set /a ST_MISSING=0
call :ST_MOD "core.cmd" "MSG OK FAIL SKIP WARN HEAD PLAN CONFIRM SNAP_REG REG_SET REG_DEL REG_KEY SC_SET SC_STOP SC_START BCD_SNAP BCD_SET BCD_DEL POWER_SCHEME POWER_SET NETSH_TCP NETSH_SUPP NET_FLUSH FSUTIL_SET TASK_DISABLE TASK_ENABLE PS_RUN BLOCK_BEGIN BLOCK_END AGG_BEGIN AGG_END IRREVERSIBLE PURGE_FILES PAUSE_SAFE PURGE_DIR DISM_RUN"
call :ST_MOD "detect.cmd" "DETECT_ALL DETECT_REPAIR DETECT_LOAD LOAD_KV_PFX DQ DNUM DETECT_TIER1 DETECT_TIER2 DETECT_TIER3 DETECT_MERGE DETECT_AUDIT DETECT_DEFAULTS DETECT_SANITIZE DETECT_OS_FIX DETECT_ENV DETECT_CLASSIFY DETECT_HKCU DETECT_FALLBACK DETECT_SYSINFO DETECT_TIER_LABEL DETECT_SOURCES_FIX"
call :ST_MOD "backup.cmd" "LOAD_KV SESSION_INIT SESSION_ROTATE SESSION_LIST RP_CLEAR RP_REQUIRE RP_MENU MM_SET DEF_EXCL DEF_SET REGACL_SET APPX_REMOVE HIBER_SET RESERVED_SET BCD_SUSPEND POWER_ULTIMATE ROLLBACK_MENU ROLLBACK_FULL ROLLBACK_GROUP CLASSIFY REPLAY_LINE PROVISIONED_REMOVE"
call :ST_MOD "guard.cmd" "G_INIT G_HARD G_SOFT_LOG G_INFO G_CONFIRM G_ADVANCED G_RAM G_RAM_SOFT G_SSD G_ALLSSD G_NOTLAPTOP G_ACPOWER G_CPU_HYBRID G_CPU_OLD G_BUILD G_GPU_VENDOR G_HWID G_SECURITY_REFRESH G_SECURITY_INVALIDATE G_AV G_AV_THIRD G_TAMPER G_DISKSPACE G_NETWORK G_GLOBAL G_BANNER G_SUMMARY G_MVERDICT G_MATRIX"
call :ST_MOD "tweaks_safe.cmd" "T_TELEMETRY T_NET_STD T_NET_PORTS T_POWER T_POWER_THROTTLE T_UWP T_SCHTASKS T_DEFENDER_EXC T_SERVICES T_SPOOLER T_DEFRAG T_VISUAL T_GAMING T_UX T_WORK T_MAINT T_INPUT T_PRIVACY_EXT T_WEBDAV NET_IF_LOAD IFACE_SET MAINT_PATHS"
call :ST_MOD "tweaks_warn.cmd" "T_PRIORITY T_MEMORY T_MMCSS T_POWER_HIBER T_POWER_DISK T_POWER_TIMER T_RESERVED T_WORK_IFEO T_UX_CHAT T_MOUSE T_TIMERS T_NDU T_GAMEBAR_RT T_SERVICES_XBOX T_AUDIO T_WDI T_STORPORT T_PREFETCH T_SYSMAIN T_VISUAL_AGG T_NET_GLOBAL POWER_HAS"
call :ST_MOD "tweaks_danger.cmd" "T_VBS T_MITIGATIONS T_BCD_TIMERS T_BCD_TSC T_BCD_BOOT T_GPU_ULPS T_GPU_HDCP T_MSI_GPU GPU_CLASS_LOAD"
call :ST_MOD "tweaks_exp.cmd" "E_DWM E_NX E_PAGING_ENC E_DEF_SCRIPT E_TSC_LEGACY E_SEHOP E_HETERO E_DEF_RT E_CSTATES E_POOL E_SUPERFETCH E_ULTIMATE"
call :ST_MOD "tools.cmd" "NORM_DWORD CHK SHOW_VAL CHK_SVC CHK_BCD SHOW_BCD CHK_POWER CHK_TASKS CHECK_STATUS ASK_NUM BENCH_EXEC BENCH_SILENT BENCH_LIST BENCH_CLEAR_NS BENCH_REPORT BENCH_DELTA BENCH_DIFF_BODY BENCH_MENU BENCH_AUTO_COMPARE BOOT_TIME DIAGNOSTICS_MENU SEARCH_DOCS UNDO_HISTORY SAVE_PREFS SETTINGS_MENU SYSTEM_INFO_SCREEN SMART_SCREEN FRAMETIME_SCREEN CHK_NIC CHK_NIC_ONE"
call :ST_MOD "blocks.cmd" "BLOCKS_DATA BLOCKS_LOAD BLOCKS_PARSE BLOCKS_NORM BLOCKS_CLEAR BLOCKS_FLIP BLOCKS_RANGE BLOCKS_TOGGLE BLOCKS_ALL BLOCKS_NEW BLOCKS_PACK BLOCKS_PRESET BLOCKS_CONFLICT BLOCKS_VERDICT BLOCKS_VERDICT_ALL BLOCKS_SELSTAT BLOCKS_PLAN BLOCKS_SHOW BLOCKS_APPLY"
call :ST_PS
exit /b 0

:ST_MOD
set "_MF=!WP_LIB!\%~1"
if not exist "!_MF!" (
    echo   [FAIL] отсутствует модуль %~1
    set /a ST_MISSING+=1
    exit /b 1
)
for %%L in (%~2) do (
    findstr /r /c:"^:%%L$" "!_MF!" >nul 2>&1
    if errorlevel 1 (
        echo   [FAIL] %~1 : нет метки %%L
        set /a ST_MISSING+=1
    )
)
exit /b 0

:ST_PS
set "_PF=!WP_LIB!\wp.ps1"
if not exist "!_PF!" (
    echo   [FAIL] отсутствует lib\wp.ps1
    set /a ST_MISSING+=1
    exit /b 1
)
for %%V in (get-engine get-detect get-detect-api get-interfaces get-gpuclass get-security get-benchmark get-boottime get-tasks get-mmagent get-defender get-restorepoints do-regacl do-restorepoint do-appx do-mmagent do-defender get-smart get-autorun get-features do-provisioned get-nic get-frametime snapshot-task snapshot-reg rotate-sessions session-key) do (
    findstr /c:"'%%V' {" "!_PF!" >nul 2>&1
    if errorlevel 1 (
        echo   [FAIL] wp.ps1 : нет verb %%V
        set /a ST_MISSING+=1
    )
)
exit /b 0

rem ============================================================
rem  MENU_SELFTEST - каждая клавиша имеет ровно одну пару.
rem  Рассинхрон строки клавиш и карты был причиной запуска
rem  случайного блока. Теперь он невозможен конструктивно.
rem ============================================================
:MENU_SELFTEST
set /a MENU_BAD=0
call :MS_CHECK "!AM_KEYS!" "!AM_MAP!"
call :MS_CHECK "!NV_KEYS!" "!NV_MAP!"
exit /b 0

:MS_CHECK
set "_MSK=%~1"
set "_MSM=%~2"
if not defined _MSK (
    set /a MENU_BAD+=1
    exit /b 1
)
set "_MSN=0"
for %%p in (%_MSM%) do set /a _MSN+=1
set "_MSL=0"
:MS_LEN
if not "!_MSK:~%_MSL%,1!"=="" (
    set /a _MSL+=1
    goto :MS_LEN
)
if not "!_MSL!"=="!_MSN!" (
    echo   [FAIL] карта меню: клавиш !_MSL!, пар !_MSN!
    set /a MENU_BAD+=1
    exit /b 1
)
for /l %%i in (0,1,!_MSL!) do (
    set "_MSC=!_MSK:~%%i,1!"
    if defined _MSC (
        set "_MSHIT=0"
        for %%p in (%_MSM%) do (
            for /f "tokens=1 delims=:" %%a in ("%%p") do (
                if /i "%%a"=="!_MSC!" set /a _MSHIT+=1
            )
        )
        if not "!_MSHIT!"=="1" (
            echo   [FAIL] клавиша !_MSC! имеет !_MSHIT! пар вместо одной
            set /a MENU_BAD+=1
        )
    )
)
exit /b 0

rem ============================================================
rem  AGREEMENT - версионируется, при смене версии показывается снова
rem ============================================================
:AGREEMENT
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
color 0E
echo.
echo == ПОЛЬЗОВАТЕЛЬСКОЕ СОГЛАШЕНИЕ %WP_VERSION% ==
echo.
echo   WinPulse меняет настройки системы. Это инструмент, не волшебство.
echo.
echo   Что нужно понимать:
echo   - Прирост не гарантирован. Разница меньше 5 проц - это шум.
echo   - Часть твиков снижает защиту. Это видно в описании каждого.
echo   - Точка восстановления обязательна перед применением.
echo   - Откат вернёт значения из журнала, но не удалённые файлы и Appx.
echo   - Сторонние оптимизаторы пишут мимо журнала, применяй их после.
echo   - Сначала обновления Windows, BIOS и драйверов, потом твики.
echo.
echo   Автор не отвечает за потерю данных, нестабильность и блокировки
echo   античитами. Программа бесплатна, телеметрии не содержит.
echo.
set "WP_QUESTION=Принимаю (Y/N): "
call "%WP_LIB%\desktop_io.cmd" choice YN
if errorlevel 2 goto :ERR_AGREEMENT_DECLINED
>"!AGREE_FILE!" echo %WP_VERSION%
>>"!SESSION_LOG!" echo [%TIME%] agreement accepted %WP_VERSION%
color 0A
call :DETECT_ALL_MAIN
if errorlevel 3 goto :ERR_BACKUPS_RO
if errorlevel 2 goto :EXIT
if errorlevel 1 goto :ERR_UNSUPPORTED
call :POST_DETECT_WARN
goto :MAIN_MENU

rem ============================================================
rem  BITLOCKER_GATE - не пролистываемый Y/N, а показ команды
rem  и явное подтверждение что ключ сохранён.
rem ============================================================
:BITLOCKER_GATE
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
color 0C
echo.
echo == BITLOCKER ВКЛЮЧЁН ==
echo.
echo   Системный том !SYS_DRIVE! зашифрован.
echo   Правки BCD меняют измерения TPM. Без ключа восстановления
echo   система может не загрузиться после перезагрузки.
echo.
echo   Получи и сохрани ключ СЕЙЧАС, вне этого компьютера:
echo     manage-bde -protectors !SYS_DRIVE! -get
echo.
echo   WinPulse приостановит защиту на одну перезагрузку перед
echo   BCD-блоками, но ключ всё равно должен быть у тебя на руках.
echo.
set "WP_QUESTION=Ключ восстановления сохранён (Y/N): "
call "%WP_LIB%\desktop_io.cmd" choice YN
if errorlevel 2 exit /b 1
>>"!SESSION_LOG!" echo [%TIME%] bitlocker key confirmed by user
color 0A
exit /b 0

rem ============================================================
rem  MAIN_MENU
rem ============================================================
:MAIN_MENU
if defined CLI_OPEN (
    if "!DESKTOP_ENTERED!"=="1" goto :EXIT
    set "DESKTOP_ENTERED=1"
    if defined CLI_VISUAL set "WP_VISUAL_CHOICE=!CLI_VISUAL!"
    if /i "!CLI_OPEN!"=="ROLLBACK" goto :TOOL_ROLLBACK
    if /i "!CLI_OPEN!"=="EXPERIMENTAL" goto :EXP_MENU
    for %%t in (STATUS DIAG MAINT RESTORE PANELS BENCH BOOTTIME HISTORY MATRIX DETECTREPAIR SETTINGS SYSINFO SEARCH CONSTRUCTOR SMART AUTORUN FRAMETIME) do if /i "!CLI_OPEN!"=="%%t" goto :TOOL_%%t
    goto :MODE_!CLI_OPEN!
)
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
if "!WP_DRYRUN!"=="1" (color 0B) else (color 0A)
if "!PENDING_REBOOT!"=="1" color 0E
echo.
echo == WinPulse %WP_VERSION% %WP_CODENAME% ==
echo.
echo   OS: !WIN_VER!
echo   CPU: !CPU_NAME!  !CPU_CORES!C/!CPU_THREADS!T
echo   GPU: !GPU_NAME!
echo   RAM: !RAM_GB! GB   Boot: !BOOT_DISK_TYPE! !BOOT_DISK_BUS!   Free: !FREE_SPACE_GB! GB
call "%WP_LIB%\guard.cmd" :G_BANNER
if "!WP_DRYRUN!"=="1" echo   [DRY-RUN] запись в систему отключена
if "!ADVANCED_MODE!"=="1" echo   [ADVANCED] danger и experimental разблокированы
if "!PENDING_REBOOT!"=="1" echo   [PENDING REBOOT] Windows ожидает перезагрузку
if "!HKCU_MISMATCH!"=="1" echo   [HKCU] пользовательские твики идут в !WP_HKCU!
echo.
if /i "!USER_LEVEL!"=="Novice" if "!TUTORIAL_SHOWN!"=="0" goto :TUTORIAL
if /i "!USER_LEVEL!"=="Novice" goto :MENU_NOVICE
goto :MENU_ADV

:MENU_ADV
echo   -- РЕЖИМЫ --
echo   [L] Lite      минимальный риск, для слабых ПК
echo   [M] Minimum   базовые безопасные твики
echo   [E] Medium    баланс: визуал, приоритеты, обслуживание
echo   [W] Work      работа: HAGS, офис, прозрачность сохранена
echo   [X] Maximum   игры: safe + warn + danger, нужен Advanced
echo   [Q] Experimental  по одному, с замерами
echo.
echo   -- ИНСТРУМЕНТЫ --
echo   [S] Состояние твиков      [D] Диагностика
echo   [C] Обслуживание          [B] Точки восстановления
echo   [O] Откат по группам      [R] Ручные панели Windows
echo   [V] Конструктор          выбор блоков с вердиктами гвардов
echo   [Z] Здоровье дисков        SMART, температура, износ, наработка
echo   [G] Бенчмарк              [N] Время загрузки
echo   [U] История сессий        [J] Матрица защиты
echo   [K] Починка детекта
echo.
echo   [1] Редактор автозагрузки   [2] Время кадра   [3] Фон приложений
echo   -- ДОКУМЕНТЫ И НАСТРОЙКИ --
echo   [H] README                [T] Manual Steps
echo   [Y] Внешние оптимизаторы  [F] Поиск по документам
echo   [P] Настройки             [I] Информация о системе
echo   [A] Соглашение
echo.
echo   [0] Выход
echo.
call :DISPATCH "!AM_KEYS!" "!AM_MAP!"
goto :!MENU_TARGET!

:MENU_NOVICE
echo   -- РЕКОМЕНДУЕМОЕ --
if "!WEAK_PC!"=="1" (
    echo   [L] Lite      рекомендован для вашего ПК
    echo   [M] Minimum   безопасный старт
) else (
    echo   [M] Minimum   безопасный старт
    echo   [W] Work      работа и базовые игры
)
echo   [L] Lite
echo.
echo   -- ПОЛЕЗНОЕ --
echo   [1] Автозагрузка Windows   [3] Фон приложений
echo   [S] Состояние твиков      [B] Точки восстановления
echo   [G] Бенчмарк              [N] Время загрузки
echo   [T] Manual Steps          [H] README
echo.
echo   [V] Расширенное меню
echo   [0] Выход
echo.
call :DISPATCH "!NV_KEYS!" "!NV_MAP!"
goto :!MENU_TARGET!

rem ============================================================
rem  DISPATCH - карта клавиша-метка, без каскада if errorlevel
rem ============================================================
:DISPATCH
set "_DK=%~1"
set "_DM=%~2"
set "MENU_TARGET="
set "WP_QUESTION=Ваш выбор: "
call "%WP_LIB%\desktop_io.cmd" choice %_DK%
set /a "_DI=%errorlevel%-1"
set "_DC=!_DK:~%_DI%,1!"
for %%p in (%_DM%) do (
    for /f "tokens=1,2 delims=:" %%a in ("%%p") do (
        if /i "%%a"=="!_DC!" set "MENU_TARGET=%%b"
    )
)
if not defined MENU_TARGET set "MENU_TARGET=MAIN_MENU"
exit /b 0

:NOVICE_TO_ADV
set "USER_LEVEL=Advanced"
call "%WP_LIB%\tools.cmd" :SAVE_PREFS
goto :MAIN_MENU

rem ============================================================
rem  Обёртки инструментов и документов
rem ============================================================
:TOOL_STATUS
call "%WP_LIB%\tools.cmd" :CHECK_STATUS
goto :MAIN_MENU

:TOOL_DIAG
call "%WP_LIB%\tools.cmd" :DIAGNOSTICS_MENU
goto :MAIN_MENU

:TOOL_MAINT
call "%WP_LIB%\guard.cmd" :G_GLOBAL "MAINT"
if errorlevel 1 goto :MAIN_MENU
call "%WP_LIB%\guard.cmd" :G_INIT
call "%WP_LIB%\backup.cmd" :RP_REQUIRE "MAINT"
if errorlevel 1 goto :MAIN_MENU
call "%WP_LIB%\tweaks_safe.cmd" :T_MAINT
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :MAIN_MENU

:TOOL_RESTORE
call "%WP_LIB%\backup.cmd" :RP_MENU
goto :MAIN_MENU

:TOOL_ROLLBACK
call "%WP_LIB%\backup.cmd" :ROLLBACK_MENU
goto :MAIN_MENU

:TOOL_PANELS
start "" devmgmt.msc
start "" services.msc
start "" powercfg.cpl
goto :MAIN_MENU

:TOOL_BENCH
call "%WP_LIB%\tools.cmd" :BENCH_MENU
goto :MAIN_MENU

:TOOL_BOOTTIME
call "%WP_LIB%\tools.cmd" :BOOT_TIME
goto :MAIN_MENU

:TOOL_HISTORY
call "%WP_LIB%\tools.cmd" :UNDO_HISTORY
goto :MAIN_MENU

:TOOL_MATRIX
call "%WP_LIB%\guard.cmd" :G_MATRIX
goto :MAIN_MENU

:TOOL_DETECTREPAIR
call "%WP_LIB%\detect.cmd" :DETECT_REPAIR
goto :MAIN_MENU

:TOOL_SETTINGS
call "%WP_LIB%\tools.cmd" :SETTINGS_MENU
goto :MAIN_MENU

:TOOL_SYSINFO
call "%WP_LIB%\tools.cmd" :SYSTEM_INFO_SCREEN
goto :MAIN_MENU

:TOOL_SEARCH
call "%WP_LIB%\tools.cmd" :SEARCH_DOCS
goto :MAIN_MENU

:DOC_README
if exist "!WP_MAIN!\Help\overview.html" (
    start "" "!WP_MAIN!\Help\overview.html"
    goto :MAIN_MENU
)
if exist "!WP_ROOT!\README.txt" (start "" notepad.exe "!WP_ROOT!\README.txt") else (call :DOC_MISSING "README.txt")
goto :MAIN_MENU

:DOC_MANUAL
if exist "!WP_MAIN!\Help\manual.html" (
    start "" "!WP_MAIN!\Help\manual.html"
    goto :MAIN_MENU
)
if exist "!WP_MAIN!\MANUAL_STEPS.txt" (start "" notepad.exe "!WP_MAIN!\MANUAL_STEPS.txt") else (call :DOC_MISSING "MANUAL_STEPS.txt")
goto :MAIN_MENU

:DOC_EXTERNAL
if exist "!WP_MAIN!\Help\external.html" (
    start "" "!WP_MAIN!\Help\external.html"
    goto :MAIN_MENU
)
if exist "!WP_MAIN!\EXTERNAL_TOOLS.txt" (start "" notepad.exe "!WP_MAIN!\EXTERNAL_TOOLS.txt") else (call :DOC_MISSING "EXTERNAL_TOOLS.txt")
goto :MAIN_MENU

:DOC_MISSING
call "%WP_LIB%\core.cmd" :FAIL "документ %~1 не найден"
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
exit /b 0

:DOC_AGREEMENT
del /f /q "!AGREE_FILE!" >nul 2>&1
goto :AGREEMENT

:SHOW_USAGE
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo WinPulse %WP_VERSION% %WP_CODENAME%
echo.
echo   winpulse.bat [/dryrun] [/advanced]
echo.
echo   /dryrun или --dry-run     песочница: только план, без записи в систему
echo   /advanced   включить Advanced Mode при старте
echo.
echo   Запуск от администратора. Путь без спецсимволов, см. README раздел 0
echo   Кодировки: .bat/.cmd UTF-8 без BOM, wp.ps1 UTF-8 с BOM, CRLF
echo.
if defined OLD_CP chcp !OLD_CP! >nul 2>&1
endlocal & exit /b 0


rem ============================================================
rem  ЧАСТЬ 2/2. Оркестрация режимов, Experimental, сводка, выход.
rem
rem  Состав режимов по операциям:
rem    LITE     60   safe-подмножество плюс WDI
rem    MINIMUM  114   safe без визуала и обслуживания
rem    MEDIUM  155   MINIMUM плюс визуал, приоритеты, MMCSS, игры, обслуживание
rem    WORK    124   без Defender-исключений и игровых блоков
rem    MAXIMUM  все safe + warn + danger, число считается из blocks.cmd
rem    EXP      14   отдельно, по одному, в режимы не входит
rem ============================================================

rem ============================================================
rem  MENU_DEFS - единственное место определения строк меню.
rem  Дублировать их внутри меток меню нельзя: selftest проверял бы
rem  одну копию, а choice работал бы с другой.
rem ============================================================
:MENU_DEFS
set "AM_KEYS=LMEWXQSDCBORHTYPIAFGUNJK0VZ123"
set "AM_MAP=L:MODE_LITE M:MODE_MINIMUM E:MODE_MEDIUM W:MODE_WORK X:MODE_MAXIMUM Q:EXP_MENU S:TOOL_STATUS D:TOOL_DIAG C:TOOL_MAINT B:TOOL_RESTORE O:TOOL_ROLLBACK R:TOOL_PANELS H:DOC_README T:DOC_MANUAL Y:DOC_EXTERNAL P:TOOL_SETTINGS I:TOOL_SYSINFO A:DOC_AGREEMENT F:TOOL_SEARCH G:TOOL_BENCH U:TOOL_HISTORY N:TOOL_BOOTTIME J:TOOL_MATRIX K:TOOL_DETECTREPAIR 0:EXIT V:TOOL_CONSTRUCTOR Z:TOOL_SMART 1:TOOL_AUTORUN 2:TOOL_FRAMETIME 3:TOOL_BACKGROUND"
set "NV_KEYS=LMWSBTHGNV013"
set "NV_MAP=L:MODE_LITE M:MODE_MINIMUM W:MODE_WORK S:TOOL_STATUS B:TOOL_RESTORE T:DOC_MANUAL H:DOC_README G:TOOL_BENCH N:TOOL_BOOTTIME V:NOVICE_TO_ADV 0:EXIT 1:TOOL_STARTUP_SETTINGS 3:TOOL_BACKGROUND"
exit /b 0

rem ============================================================
rem  MODE_PREP  %1 имя режима. 0 = можно применять, 1 = стоп.
rem  Точка восстановления обязательна, обход только в Advanced.
rem ============================================================
:MODE_PREP
set /a WP_MODE_OK=0, WP_MODE_FAIL=0, WP_MODE_SKIP=0, WP_MODE_PLAN=0, WP_OP_EXPECTED=0
set "_MN=%~1"
call "%WP_LIB%\guard.cmd" :G_GLOBAL "!_MN!"
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    exit /b 1
)
call "%WP_LIB%\guard.cmd" :G_INIT
set /a WP_OP_OK=0
set /a WP_OP_FAIL=0
set /a WP_OP_SKIP=0
set /a WP_OP_PLAN=0
set "WP_APPLIED_BLOCKS="
set "WP_SKIPPED_BLOCKS="
set "WP_FAILED_BLOCKS="
set "WP_REBOOT_REQUIRED=0"
set "WP_SECURITY_REDUCED=0"
set "WP_DEF_PROTECTION_REDUCED=0"
set "WP_IRREVERSIBLE=0"
call "%WP_LIB%\backup.cmd" :RP_REQUIRE "!_MN!"
if errorlevel 1 exit /b 1
if "!WP_BENCH_AUTO!"=="1" call "%WP_LIB%\tools.cmd" :BENCH_SILENT "baseline"
>>"%SESSION_LOG%" echo [%TIME%] MODE START !_MN!
exit /b 0

rem ============================================================
rem  MODE_LITE - 60 номинальных операций
rem ============================================================
:MODE_LITE
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
call "%WP_LIB%\core.cmd" :HEAD "РЕЖИМ LITE"
echo   Телеметрия, базовая сеть, план питания, рекламные UWP,
echo   задачи планировщика, повтор клавиш, лог WDI.
echo   Визуал не трогаем. Службы не отключаем. Дефраг не трогаем.
echo.
call "%WP_LIB%\core.cmd" :CONFIRM "Применить LITE" N
if errorlevel 1 goto :MAIN_MENU
call :MODE_PREP "LITE"
if errorlevel 1 goto :MAIN_MENU
call "%WP_LIB%\tweaks_safe.cmd" :T_SMB1
call "%WP_LIB%\tweaks_safe.cmd" :T_IFEO_ECO
call "%WP_LIB%\tweaks_safe.cmd" :T_TELEMETRY
call "%WP_LIB%\tweaks_safe.cmd" :T_NET_STD
call "%WP_LIB%\tweaks_safe.cmd" :T_POWER
call "%WP_LIB%\tweaks_safe.cmd" :T_UWP "selective"
call "%WP_LIB%\tweaks_safe.cmd" :T_SCHTASKS
call "%WP_LIB%\tweaks_safe.cmd" :T_INPUT
call "%WP_LIB%\tweaks_warn.cmd" :T_WDI
goto :MODE_SUMMARY

rem ============================================================
rem  MODE_MINIMUM - 114 номинальных операций
rem ============================================================
:MODE_MINIMUM
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
call "%WP_LIB%\core.cmd" :HEAD "РЕЖИМ MINIMUM"
echo   LITE плюс порты сети, Power Throttling, полный debloat,
echo   исключения Defender, службы, геолокация, UX, WebDAV.
echo   Визуал и обслуживание не входят.
echo.
call "%WP_LIB%\core.cmd" :CONFIRM "Применить MINIMUM" N
if errorlevel 1 goto :MAIN_MENU
call :MODE_PREP "MINIMUM"
if errorlevel 1 goto :MAIN_MENU
call "%WP_LIB%\tweaks_safe.cmd" :T_SMB1
call "%WP_LIB%\tweaks_safe.cmd" :T_IFEO_ECO
call "%WP_LIB%\tweaks_safe.cmd" :T_AUTORUN
call "%WP_LIB%\tweaks_safe.cmd" :T_STORAGE_SAFE
call "%WP_LIB%\tweaks_safe.cmd" :T_DO_PEERING
call "%WP_LIB%\tweaks_safe.cmd" :T_TELEMETRY
call "%WP_LIB%\tweaks_safe.cmd" :T_SCHTASKS
call "%WP_LIB%\tweaks_safe.cmd" :T_UX
call "%WP_LIB%\tweaks_safe.cmd" :T_PRIVACY_EXT
call "%WP_LIB%\tweaks_safe.cmd" :T_INPUT
call "%WP_LIB%\tweaks_safe.cmd" :T_NET_STD
call "%WP_LIB%\tweaks_safe.cmd" :T_NET_PORTS
call "%WP_LIB%\tweaks_safe.cmd" :T_WEBDAV
call "%WP_LIB%\tweaks_safe.cmd" :T_POWER
call "%WP_LIB%\tweaks_safe.cmd" :T_POWER_THROTTLE
call "%WP_LIB%\tweaks_safe.cmd" :T_UWP "full"
call "%WP_LIB%\tweaks_safe.cmd" :T_DEFENDER_EXC
call "%WP_LIB%\tweaks_safe.cmd" :T_SERVICES
call "%WP_LIB%\tweaks_safe.cmd" :T_SPOOLER
call "%WP_LIB%\tweaks_warn.cmd" :T_WDI
goto :MODE_SUMMARY

rem ============================================================
rem  MODE_MEDIUM - 155 номинальных операций
rem ============================================================
:MODE_MEDIUM
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
call "%WP_LIB%\core.cmd" :HEAD "РЕЖИМ MEDIUM"
echo   MINIMUM плюс визуал, приоритеты, MMCSS, игровые твики
echo   и обслуживание. Опасные блоки не входят.
echo.
if "!WEAK_PC!"=="1" echo   [WARN] Слабый ПК:!WEAK_REASONS! - визуал пойдёт в профиле Comfort
echo.
call "%WP_LIB%\core.cmd" :CONFIRM "Применить MEDIUM" N
if errorlevel 1 goto :MAIN_MENU
call :MODE_PREP "MEDIUM"
if errorlevel 1 goto :MAIN_MENU
call "%WP_LIB%\tweaks_safe.cmd" :T_SMB1
call "%WP_LIB%\tweaks_safe.cmd" :T_IFEO_ECO
call "%WP_LIB%\tweaks_safe.cmd" :T_AUTORUN
call "%WP_LIB%\tweaks_safe.cmd" :T_STORAGE_SAFE
call "%WP_LIB%\tweaks_safe.cmd" :T_DO_PEERING
call "%WP_LIB%\tweaks_warn.cmd" :T_STORAGE_DEEP
call "%WP_LIB%\tweaks_safe.cmd" :T_TELEMETRY
call "%WP_LIB%\tweaks_safe.cmd" :T_SCHTASKS
call "%WP_LIB%\tweaks_safe.cmd" :T_UX
call "%WP_LIB%\tweaks_safe.cmd" :T_PRIVACY_EXT
call "%WP_LIB%\tweaks_safe.cmd" :T_INPUT
call "%WP_LIB%\tweaks_safe.cmd" :T_NET_STD
call "%WP_LIB%\tweaks_safe.cmd" :T_NET_PORTS
call "%WP_LIB%\tweaks_safe.cmd" :T_WEBDAV
call "%WP_LIB%\tweaks_safe.cmd" :T_POWER
call "%WP_LIB%\tweaks_safe.cmd" :T_POWER_THROTTLE
call "%WP_LIB%\tweaks_safe.cmd" :T_UWP "full"
call "%WP_LIB%\tweaks_safe.cmd" :T_DEFENDER_EXC
call "%WP_LIB%\tweaks_safe.cmd" :T_SERVICES
call "%WP_LIB%\tweaks_safe.cmd" :T_SPOOLER
call "%WP_LIB%\tweaks_warn.cmd" :T_WDI
call "%WP_LIB%\tweaks_safe.cmd" :T_GAMING
if "!WEAK_PC!"=="1" (
    call "%WP_LIB%\tweaks_safe.cmd" :T_VISUAL "Comfort"
) else (
    call "%WP_LIB%\tweaks_safe.cmd" :T_VISUAL "Balanced"
)
call "%WP_LIB%\tweaks_warn.cmd" :T_PRIORITY "40" "20"
call "%WP_LIB%\tweaks_warn.cmd" :T_MMCSS
call "%WP_LIB%\tweaks_safe.cmd" :T_MAINT
goto :MODE_SUMMARY

rem ============================================================
rem  MODE_WORK - 124 номинальных операций
rem  Без исключений Defender и без игровых блоков.
rem  Прозрачность сохранена, Windhawk выглядит как надо.
rem ============================================================
:MODE_WORK
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
call "%WP_LIB%\core.cmd" :HEAD "РЕЖИМ WORK"
echo   HAGS, приоритеты офисных приложений, отложенный WSearch,
echo   прозрачность включена, комфортные меню.
echo   Исключения Defender и игровые твики не применяются.
echo.
call "%WP_LIB%\core.cmd" :CONFIRM "Применить WORK" N
if errorlevel 1 goto :MAIN_MENU
call :MODE_PREP "WORK"
if errorlevel 1 goto :MAIN_MENU
call "%WP_LIB%\tweaks_safe.cmd" :T_SMB1
call "%WP_LIB%\tweaks_safe.cmd" :T_IFEO_ECO
call "%WP_LIB%\tweaks_safe.cmd" :T_AUTORUN
call "%WP_LIB%\tweaks_safe.cmd" :T_STORAGE_SAFE
call "%WP_LIB%\tweaks_safe.cmd" :T_DO_PEERING
call "%WP_LIB%\tweaks_safe.cmd" :T_TELEMETRY
call "%WP_LIB%\tweaks_safe.cmd" :T_SCHTASKS
call "%WP_LIB%\tweaks_safe.cmd" :T_UX
call "%WP_LIB%\tweaks_safe.cmd" :T_PRIVACY_EXT
call "%WP_LIB%\tweaks_safe.cmd" :T_INPUT
call "%WP_LIB%\tweaks_safe.cmd" :T_NET_STD
call "%WP_LIB%\tweaks_safe.cmd" :T_NET_PORTS
call "%WP_LIB%\tweaks_safe.cmd" :T_WEBDAV
call "%WP_LIB%\tweaks_safe.cmd" :T_POWER
call "%WP_LIB%\tweaks_safe.cmd" :T_POWER_THROTTLE
call "%WP_LIB%\tweaks_safe.cmd" :T_UWP "selective"
call "%WP_LIB%\tweaks_safe.cmd" :T_SERVICES
call "%WP_LIB%\tweaks_safe.cmd" :T_SPOOLER
call "%WP_LIB%\tweaks_warn.cmd" :T_WDI
call "%WP_LIB%\tweaks_safe.cmd" :T_WORK
call "%WP_LIB%\tweaks_warn.cmd" :T_WORK_IFEO
call "%WP_LIB%\tweaks_safe.cmd" :T_VISUAL "Work"
call "%WP_LIB%\tweaks_warn.cmd" :T_PRIORITY "40" "20"
call "%WP_LIB%\tweaks_safe.cmd" :T_MAINT
goto :MODE_SUMMARY

rem ============================================================
rem  MODE_MAXIMUM - все блоки safe + warn + danger, до гвардов
rem  Experimental сюда НЕ входит.
rem ============================================================
:MODE_MAXIMUM
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
color 0C
call "%WP_LIB%\core.cmd" :HEAD "РЕЖИМ MAXIMUM"
if not "!ADVANCED_MODE!"=="1" (
    echo   Требуется Advanced Mode. Включите в настройках [P].
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    goto :MAIN_MENU
)
set /a _MX_S=0
set /a _MX_W=0
set /a _MX_D=0
call "%WP_LIB%\blocks.cmd" :BLOCKS_LOAD
if not errorlevel 1 (
    for /l %%i in (1,1,!BLK_COUNT!) do (
        set "_bn=0%%i"
        for %%n in (!_bn:~-2!) do (
            if /i "!BL_CAT_%%n!"=="safe" set /a _MX_S+=BL_OPS_%%n
            if /i "!BL_CAT_%%n!"=="warn" set /a _MX_W+=BL_OPS_%%n
            if /i "!BL_CAT_%%n!"=="danger" set /a _MX_D+=BL_OPS_%%n
        )
    )
    set /a _MX_T=_MX_S+_MX_W+_MX_D
    echo   safe !_MX_S! + warn !_MX_W! + danger !_MX_D! = !_MX_T! операций до гвардов.
    echo   Заблокированные гвардами блоки не применяются, итог будет меньше.
) else (
    echo   Все блоки safe + warn + danger. Точное число зависит от гвардов.
)
echo.
echo   Будет снижена защита: VBS, HVCI, Credential Guard,
echo   Spectre mitigations, возможно Defender-исключения.
echo   FaceIT и ESEA могут перестать запускаться.
echo   Netflix и Disney+ перестанут работать при отключении HDCP.
echo.
echo   Каждый опасный блок спросит отдельно и потребует YES.
echo   Experimental применяется только через меню [Q].
echo.
call "%WP_LIB%\guard.cmd" :G_SECURITY_REFRESH
if not "!SEC_AV_ACTIVE!"=="1" (
    echo   [WARN] Активный антивирус не обнаружен.
    echo   Блоки снижения защиты закрыты по отдельности: VBS, HVCI,
    echo   mitigations, Defender-твики. Они не применятся.
    echo   Остальное применится, но система останется без защиты
    echo   в реальном времени. Portable-сканер её не заменяет.
    echo.
    call "%WP_LIB%\core.cmd" :CONFIRM "Продолжить MAXIMUM без антивируса" N
    if errorlevel 1 goto :MAIN_MENU
)
call "%WP_LIB%\core.cmd" :CONFIRM "Применить MAXIMUM" N
if errorlevel 1 goto :MAIN_MENU
call :MODE_PREP "MAXIMUM"
if errorlevel 1 goto :MAIN_MENU
call "%WP_LIB%\tweaks_safe.cmd" :T_SMB1
call "%WP_LIB%\tweaks_safe.cmd" :T_IFEO_ECO
call "%WP_LIB%\tweaks_safe.cmd" :T_AUTORUN
call "%WP_LIB%\tweaks_safe.cmd" :T_STORAGE_SAFE
call "%WP_LIB%\tweaks_safe.cmd" :T_DO_PEERING
call "%WP_LIB%\tweaks_warn.cmd" :T_STORAGE_DEEP
call "%WP_LIB%\tweaks_warn.cmd" :T_SERVICES_EXT
call "%WP_LIB%\tweaks_warn.cmd" :T_PROVISIONED
call "%WP_LIB%\tweaks_warn.cmd" :T_NIC_DRIVER

echo.
echo   Профиль визуала:
echo   [1] Performance  MenuShowDelay=0, прозрачность off, анимации off
echo   [2] Balance      MenuShowDelay=100, прозрачность off
echo   [3] Keep         визуал не трогаем вообще
echo   [4] MotionOnly   только анимация сворачивания окон
echo   [5] Из настроек  !WP_VISUAL_CHOICE!
set "WP_QUESTION=Выбор: "
call "%WP_LIB%\desktop_io.cmd" choice 12345
set "_VC=!errorlevel!"
if "!_VC!"=="1" set "WP_VISUAL_PROFILE=Performance"
if "!_VC!"=="2" set "WP_VISUAL_PROFILE=Balanced"
if "!_VC!"=="3" set "WP_VISUAL_PROFILE=Keep"
if "!_VC!"=="4" set "WP_VISUAL_PROFILE=MotionOnly"
if "!_VC!"=="5" if /i not "!WP_VISUAL_CHOICE!"=="Auto" set "WP_VISUAL_PROFILE=!WP_VISUAL_CHOICE!"
echo.
echo   Win32PrioritySeparation:
echo   [1] 2   дефолт: короткий квант, переменный, буст 2
echo   [2] 26  короткий, фиксированный, буст 2 - для игр
echo   [3] 38  длинный, переменный, буст 2
echo   [4] 40  длинный, фиксированный, БЕЗ буста
set "WP_QUESTION=Выбор: "
call "%WP_LIB%\desktop_io.cmd" choice 1234
set "_PC=!errorlevel!"
if "!_PC!"=="1" set "_MSEP=2"
if "!_PC!"=="2" set "_MSEP=26"
if "!_PC!"=="3" set "_MSEP=38"
if "!_PC!"=="4" set "_MSEP=40"

call "%WP_LIB%\tweaks_safe.cmd" :T_TELEMETRY
call "%WP_LIB%\tweaks_safe.cmd" :T_SCHTASKS
call "%WP_LIB%\tweaks_safe.cmd" :T_UX
call "%WP_LIB%\tweaks_warn.cmd" :T_UX_CHAT
call "%WP_LIB%\tweaks_safe.cmd" :T_PRIVACY_EXT
call "%WP_LIB%\tweaks_safe.cmd" :T_INPUT
call "%WP_LIB%\tweaks_safe.cmd" :T_NET_STD
call "%WP_LIB%\tweaks_safe.cmd" :T_NET_PORTS
call "%WP_LIB%\tweaks_warn.cmd" :T_NET_GLOBAL
call "%WP_LIB%\tweaks_safe.cmd" :T_WEBDAV
call "%WP_LIB%\tweaks_safe.cmd" :T_POWER
call "%WP_LIB%\tweaks_safe.cmd" :T_POWER_THROTTLE
call "%WP_LIB%\tweaks_warn.cmd" :T_POWER_DISK
call "%WP_LIB%\tweaks_warn.cmd" :T_POWER_TIMER
call "%WP_LIB%\tweaks_warn.cmd" :T_POWER_HIBER
call "%WP_LIB%\tweaks_warn.cmd" :T_RESERVED
call "%WP_LIB%\tweaks_safe.cmd" :T_UWP "full"
call "%WP_LIB%\tweaks_safe.cmd" :T_DEFENDER_EXC
call "%WP_LIB%\tweaks_safe.cmd" :T_SERVICES
call "%WP_LIB%\tweaks_safe.cmd" :T_SPOOLER
call "%WP_LIB%\tweaks_warn.cmd" :T_SERVICES_XBOX
call "%WP_LIB%\tweaks_warn.cmd" :T_NDU
call "%WP_LIB%\tweaks_warn.cmd" :T_WDI
call "%WP_LIB%\tweaks_warn.cmd" :T_STORPORT
call "%WP_LIB%\tweaks_safe.cmd" :T_DEFRAG
call "%WP_LIB%\tweaks_warn.cmd" :T_SYSMAIN
call "%WP_LIB%\tweaks_warn.cmd" :T_PREFETCH
call "%WP_LIB%\tweaks_warn.cmd" :T_MEMORY
call "%WP_LIB%\tweaks_warn.cmd" :T_MMCSS
call "%WP_LIB%\tweaks_warn.cmd" :T_PRIORITY "!_MSEP!" "0"
call "%WP_LIB%\tweaks_warn.cmd" :T_TIMERS
call "%WP_LIB%\tweaks_safe.cmd" :T_WORK
call "%WP_LIB%\tweaks_warn.cmd" :T_WORK_IFEO
call "%WP_LIB%\tweaks_warn.cmd" :T_GAMEBAR_RT
call "%WP_LIB%\tweaks_safe.cmd" :T_GAMING
call "%WP_LIB%\tweaks_warn.cmd" :T_MOUSE
call "%WP_LIB%\tweaks_safe.cmd" :T_VISUAL "!WP_VISUAL_PROFILE!" "explicit"
call "%WP_LIB%\tweaks_warn.cmd" :T_VISUAL_AGG
call "%WP_LIB%\tweaks_danger.cmd" :T_VBS
call "%WP_LIB%\tweaks_danger.cmd" :T_MITIGATIONS
call "%WP_LIB%\tweaks_danger.cmd" :T_BCD_TIMERS
call "%WP_LIB%\tweaks_danger.cmd" :T_BCD_TSC
call "%WP_LIB%\tweaks_danger.cmd" :T_BCD_BOOT
call "%WP_LIB%\tweaks_danger.cmd" :T_GPU_ULPS
call "%WP_LIB%\tweaks_danger.cmd" :T_GPU_HDCP
call "%WP_LIB%\tweaks_danger.cmd" :T_MSI_GPU
call "%WP_LIB%\tweaks_warn.cmd" :T_AUDIO
call "%WP_LIB%\tweaks_safe.cmd" :T_MAINT
goto :MODE_SUMMARY

rem ============================================================
rem  EXP_MENU - 14 операций, по одной.
rem  Нумерация в меню совпадает с картой: в 6.x клавиши 2 и 3
rem  обе вызывали DWM, а пункт 4 применял NX вместо Defender.
rem ============================================================
:EXP_MENU
set /a WP_MODE_OK=0, WP_MODE_FAIL=0, WP_MODE_SKIP=0, WP_MODE_PLAN=0, WP_OP_EXPECTED=0
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
color 0C
call "%WP_LIB%\core.cmd" :HEAD "EXPERIMENTAL"
if not "!ADVANCED_MODE!"=="1" (
    echo   Требуется Advanced Mode. Включите в настройках [P].
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    goto :MAIN_MENU
)
if not "!WP_RP_OK!"=="1" (
    call "%WP_LIB%\backup.cmd" :RP_REQUIRE "EXPERIMENTAL"
    if errorlevel 1 goto :MAIN_MENU
)
echo   Применяй ПО ОДНОМУ и замеряй. Разница меньше 5 проц - шум.
echo   Каждый твик проверит пригодность вашей системы сам.
echo.
echo   [1] DWM OverlayTestMode=5      артефакты на части GPU
echo   [2] NX = OptOut                снижение защиты DEP
echo   [3] EncryptPagingFile OFF      pagefile читаем
echo   [4] Defender ScriptScan OFF    fileless-атаки
echo   [5] TSC sync = Legacy          только старые CPU
echo   [6] SEHOP disable              SEH overwrite
echo   [7] Heterogeneous sched OFF    только гибридный CPU и Win11
echo   [8] Defender Realtime OFF      нужен сторонний антивирус
echo   [9] CPU C-states OFF           только десктоп от сети
echo   [A] Kernel Paging combo        нужно 32+ ГБ, рекомендуется 64+
echo   [B] Superfetch override        только все диски SSD
echo   [C] Ultimate Performance       только десктоп от сети
echo.
echo   [0] Назад
echo.
set "_EK=123456789ABC0"
set "_EM=1:EX_DWM 2:EX_NX 3:EX_PAGING 4:EX_SCRIPT 5:EX_TSC 6:EX_SEHOP 7:EX_HETERO 8:EX_DEFRT 9:EX_CSTATES A:EX_POOL B:EX_SUPERFETCH C:EX_ULTIMATE 0:EXP_BACK"
call :DISPATCH "!_EK!" "!_EM!"
goto :!MENU_TARGET!

:EX_DWM
call "%WP_LIB%\tweaks_exp.cmd" :E_DWM
goto :EXP_DONE
:EX_NX
call "%WP_LIB%\tweaks_exp.cmd" :E_NX
goto :EXP_DONE
:EX_PAGING
call "%WP_LIB%\tweaks_exp.cmd" :E_PAGING_ENC
goto :EXP_DONE
:EX_SCRIPT
call "%WP_LIB%\tweaks_exp.cmd" :E_DEF_SCRIPT
goto :EXP_DONE
:EX_TSC
call "%WP_LIB%\tweaks_exp.cmd" :E_TSC_LEGACY
goto :EXP_DONE
:EX_SEHOP
call "%WP_LIB%\tweaks_exp.cmd" :E_SEHOP
goto :EXP_DONE
:EX_HETERO
call "%WP_LIB%\tweaks_exp.cmd" :E_HETERO
goto :EXP_DONE
:EX_DEFRT
call "%WP_LIB%\tweaks_exp.cmd" :E_DEF_RT
goto :EXP_DONE
:EX_CSTATES
call "%WP_LIB%\tweaks_exp.cmd" :E_CSTATES
goto :EXP_DONE
:EX_POOL
call "%WP_LIB%\tweaks_exp.cmd" :E_POOL
goto :EXP_DONE
:EX_SUPERFETCH
call "%WP_LIB%\tweaks_exp.cmd" :E_SUPERFETCH
goto :EXP_DONE
:EX_ULTIMATE
call "%WP_LIB%\tweaks_exp.cmd" :E_ULTIMATE
goto :EXP_DONE

:EXP_DONE
echo.
echo   ok=!WP_MODE_OK!  fail=!WP_MODE_FAIL!  skip=!WP_MODE_SKIP!  plan=!WP_MODE_PLAN!
call "%WP_LIB%\guard.cmd" :G_SUMMARY
if "!WP_REBOOT_REQUIRED!"=="1" echo   Часть изменений вступит в силу после перезагрузки.
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :EXP_MENU

:EXP_BACK
goto :MAIN_MENU

rem ============================================================
rem  MODE_SUMMARY
rem  Замер "после" идёт ДО предложения перезагрузки: в 6.x
rem  shutdown запускался первым и бенчмарк мог не доехать.
rem ============================================================
:MODE_SUMMARY
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
color 0A
call "%WP_LIB%\core.cmd" :HEAD "ИТОГ РЕЖИМА"
echo   Операций выполнено:   !WP_MODE_OK!
echo   Отказов:              !WP_MODE_FAIL!
echo   Пропущено:            !WP_MODE_SKIP!
if "!WP_DRYRUN!"=="1" echo   Запланировано:        !WP_MODE_PLAN!
set /a _MS_TOTAL=WP_MODE_OK+WP_MODE_FAIL+WP_MODE_SKIP+WP_MODE_PLAN
echo   Всего обработано:     !_MS_TOTAL!
if defined WP_OP_EXPECTED (
    echo   Ожидалось по блокам:  !WP_OP_EXPECTED!
    if !_MS_TOTAL! equ !WP_OP_EXPECTED! (
        echo   [OK] Сходится, потерь нет
    ) else (
        set /a _MS_DELTA=_MS_TOTAL-WP_OP_EXPECTED
        if !_MS_DELTA! gtr 0 (
            echo   [WARN] Учтено сверх ожидания: +!_MS_DELTA!
        ) else (
            echo   [WARN] Учтено меньше ожидаемого. Отклонение: !_MS_DELTA!
        )
    )
)
if "!WP_DRYRUN!"=="1" (
    echo   Запланировано из них: !WP_MODE_PLAN!
) else (
    if !_MS_TOTAL! gtr 0 (
        set /a _MS_PCT=WP_MODE_OK*100/_MS_TOTAL
        echo   Успешно:              !_MS_PCT! процентов
    )
)
echo.
if defined WP_APPLIED_BLOCKS (
    echo   Применённые блоки:
    for %%b in (!WP_APPLIED_BLOCKS!) do echo      %%b
    echo.
)
if defined WP_SKIPPED_BLOCKS (
    echo   Блоки с пропусками:
    for %%b in (!WP_SKIPPED_BLOCKS!) do echo      %%b
    echo.
)
if defined WP_FAILED_BLOCKS (
    echo   Блоки с отказами:
    for %%b in (!WP_FAILED_BLOCKS!) do echo      %%b
    echo.
)
call "%WP_LIB%\guard.cmd" :G_SUMMARY
echo.
echo   Профиль визуала: !WP_VISUAL_PROFILE!
echo   Сессия: %STAMP%
echo   Журнал отката: %JOURNAL%
echo   Лог сессии: %SESSION_LOG%
if "!WP_IRREVERSIBLE!"=="1" echo   Были необратимые операции, список в журнале
if "!WP_SECURITY_REDUCED!"=="1" echo   [WARN] Защита системы снижена. Откат - группа S или B
if "!WP_DEF_PROTECTION_REDUCED!"=="1" echo   [WARN] Защита Defender снижена. Верните через группу S
if "!WP_BCD_SUSPENDED!"=="1" echo   [WARN] BitLocker приостановлен на одну перезагрузку
echo.
if "!WP_BENCH_AUTO!"=="1" (
    if not "!WP_DRYRUN!"=="1" (
        call "%WP_LIB%\tools.cmd" :BENCH_SILENT "final"
        call "%WP_LIB%\tools.cmd" :BENCH_AUTO_COMPARE
    )
)
call "%WP_LIB%\backup.cmd" :SESSION_ROTATE "!WP_KEEP_SESSIONS!"
if defined WP_DESKTOP_TOKEN echo !WP_DESKTOP_TOKEN!:result^|!WP_MODE_OK!^|!WP_MODE_FAIL!^|!WP_MODE_SKIP!^|!WP_MODE_PLAN!
>>"%SESSION_LOG%" echo [%TIME%] MODE END ok=!WP_MODE_OK! fail=!WP_MODE_FAIL! skip=!WP_MODE_SKIP!
echo.
if "!WP_REBOOT_REQUIRED!"=="1" (
    echo   ТРЕБУЕТСЯ ПЕРЕЗАГРУЗКА
    if "!WP_DRYRUN!"=="1" (
        echo   Песочница: перезагрузка не предлагается.
        call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    ) else (
        set "WP_QUESTION=Перезагрузить сейчас (Y/N): "
        call "%WP_LIB%\desktop_io.cmd" choice YN
        if errorlevel 2 (
            echo   Перезагрузите вручную: часть твиков ещё не активна.
            call "%WP_LIB%\core.cmd" :PAUSE_SAFE
        ) else (
            call "%WP_LIB%\tools.cmd" :SAVE_PREFS
            shutdown /r /t 10 /c "WinPulse: применение настроек"
            echo   Перезагрузка через 10 секунд. Отмена: shutdown /a
            timeout /t 10 >nul
            goto :EXIT
        )
    )
) else (
    echo   Перезагрузка не обязательна, но рекомендуется.
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
)
goto :MAIN_MENU

rem ============================================================
rem  TUTORIAL - ASCII, без эмодзи, четыре экрана
rem ============================================================
:TUTORIAL
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
color 0B
echo.
echo == ШАГ 1 из 4. РЕЖИМЫ ==
echo.
echo   LITE     минимум риска, для слабых ПК
echo   MINIMUM  базовые безопасные твики
echo   MEDIUM   баланс: визуал, приоритеты, обслуживание
echo   WORK     работа: офис, HAGS, прозрачность сохранена
echo   MAXIMUM  игры: снижает защиту, нужен Advanced и антивирус
echo.
echo   Experimental применяется по одному и только вручную.
echo.
call "%WP_LIB%\desktop_io.cmd" wait visible
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == ШАГ 2 из 4. ВАША СИСТЕМА ==
echo.
echo   CPU: !CPU_NAME!  !CPU_CORES!C/!CPU_THREADS!T
echo   RAM: !RAM_GB! GB
echo   Загрузочный диск: !BOOT_DISK_TYPE! !BOOT_DISK_BUS!
echo   Класс системы: !SYSTEM_CLASS!
echo.
if "!WEAK_PC!"=="1" (
    echo   Слабый ПК:!WEAK_REASONS!
    echo   Рекомендация: LITE или MINIMUM.
    echo   Агрессивные твики на такой системе вредят, а не помогают.
) else (
    echo   Рекомендация: MEDIUM для баланса, WORK для работы.
    echo   Для игр: MAXIMUM, но сначала прочитайте MANUAL_STEPS.
)
echo.
call "%WP_LIB%\desktop_io.cmd" wait visible
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == ШАГ 3 из 4. ЗАЩИТА ==
echo.
echo   Точка восстановления создаётся принудительно перед режимом.
echo   Не отключайте System Restore.
echo.
echo   Каждый опасный твик проверяет вашу систему сам.
echo   Если написано BLOCK - это не ошибка, это защита.
echo   Причины смотрите в матрице защиты, клавиша [J].
echo.
echo   Сначала обновления Windows, BIOS и драйверов, потом твики.
echo.
call "%WP_LIB%\desktop_io.cmd" wait visible
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == ШАГ 4 из 4. ОТКАТ ==
echo.
echo   [O] Откат по группам: визуал, сеть, питание, BCD,
echo       безопасность, игры, память, службы, UX или всё.
echo   [B] Точки восстановления Windows.
echo   [U] История сессий и журналы.
echo.
echo   Откат вернёт значения из журнала, но не удалённые файлы
echo   и не удалённые приложения. Список невозвратного показывается.
echo.
echo   Туториал можно пройти заново в настройках [P].
echo.
call "%WP_LIB%\desktop_io.cmd" wait visible
set "TUTORIAL_SHOWN=1"
call "%WP_LIB%\tools.cmd" :SAVE_PREFS
goto :MAIN_MENU

rem ============================================================
rem  Блокировка экземпляра. Отказ действительно продолжает,
rem  а не печатает "продолжаю" и выходит, как было в 6.x.
rem ============================================================
:LOCK_EXISTS
echo   Не удалось занять блокировку !LOCK_FILE!.
echo   Проверьте, закрыт ли другой экземпляр и доступна ли папка .run для записи.
goto :EXIT_EARLY

rem ============================================================
rem  Обработчики ошибок. До создания логов core вызывать нельзя:
rem  он пишет в SESSION_LOG, которого ещё нет.
rem ============================================================
:ERR_NOT_ADMIN
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
color 0C
echo.
echo   [CRITICAL] Требуются права администратора.
echo   ПКМ по winpulse.bat - Запуск от имени администратора.
echo.
call "%WP_LIB%\desktop_io.cmd" wait visible
goto :EXIT_EARLY

:ERR_BAD_PATH
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
color 0C
echo.
echo   [CRITICAL] Недопустимые символы в пути:
echo   !WP_ROOT!
echo.
echo   Уберите из пути восклицательный знак, процент, caret и амперсанд.
echo   Проще всего перенести папку в C:\WinPulseRelease
echo.
call "%WP_LIB%\desktop_io.cmd" wait visible
goto :EXIT_EARLY

:ERR_NO_LIB
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
color 0C
echo.
echo   [CRITICAL] Не найдена папка lib:
echo   !WP_LIB!
echo.
echo   winpulse.bat должен лежать рядом с папкой lib.
echo   Не запускайте батник из архива - сначала распакуйте.
echo.
call "%WP_LIB%\desktop_io.cmd" wait visible
goto :EXIT_EARLY

:ERR_LOGS_RO
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
color 0C
echo.
echo   [CRITICAL] Папка Logs недоступна для записи:
echo   !WP_LOGS!
echo.
echo   Уберите атрибут "только чтение", проверьте права
echo   или перенесите WinPulse из Program Files.
echo.
call "%WP_LIB%\desktop_io.cmd" wait visible
goto :EXIT_EARLY

:ERR_BACKUPS_RO
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
color 0C
echo.
echo   [CRITICAL] Папка Backups недоступна для записи:
echo   !WP_BACKUPS!
echo.
echo   Без журнала отката работа запрещена.
echo.
call "%WP_LIB%\desktop_io.cmd" wait visible
goto :EXIT_EARLY

:ERR_SELFTEST
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
color 0C
echo.
echo   [CRITICAL] Selftest не пройден, отсутствий: !ST_MISSING!
echo.
echo   Список выше. Восстановите недостающие файлы или метки.
echo   Запуск заблокирован: отсутствующая метка в CALL
echo   убивает батник посреди применения твиков.
echo.
call "%WP_LIB%\desktop_io.cmd" wait visible
goto :EXIT_EARLY

:ERR_MENU_MAP
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
color 0C
echo.
echo   [CRITICAL] Карта меню рассинхронизирована.
echo.
echo   Строка клавиш и карта пар не совпадают.
echo   Это привело бы к запуску случайного блока.
echo.
call "%WP_LIB%\desktop_io.cmd" wait visible
goto :EXIT_EARLY

:ERR_AGREEMENT_DECLINED
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo   Соглашение не принято. Работа невозможна.
echo.
call "%WP_LIB%\desktop_io.cmd" wait visible
goto :EXIT_EARLY

:ERR_UNSUPPORTED
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
color 0C
echo.
echo   [CRITICAL] Сборка Windows вне поддержки: !WIN_BUILD!
echo.
echo   Требуется Windows 10 22H2 (19045) или Windows 11.
echo   Обновите систему: твики на старых сборках не проверялись,
echo   а часть ключей в них отсутствует.
echo.
call "%WP_LIB%\desktop_io.cmd" wait visible
goto :EXIT

rem ============================================================
rem  Выход. Кодовая страница консоли восстанавливается.
rem ============================================================
:EXIT
if not defined CLI_OPEN call "%WP_LIB%\tools.cmd" :SAVE_PREFS
>>"%SESSION_LOG%" echo [%TIME%] session ended ok=!WP_OP_OK! fail=!WP_OP_FAIL! skip=!WP_OP_SKIP!
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == WinPulse %WP_VERSION% %WP_CODENAME% ==
echo.
echo   Сессия: !STAMP!
echo   Журнал: !JOURNAL!
echo   Лог:    !SESSION_LOG!
echo.
if "!WP_REBOOT_REQUIRED!"=="1" echo   Не забудьте перезагрузиться.
if "!WP_RP_SKIPPED!"=="1" echo   Точка восстановления была пропущена вами.
echo.
if defined OLD_CP chcp !OLD_CP! >nul 2>&1
if not defined WP_DESKTOP_TOKEN timeout /t 2 >nul
exit /b %WP_EXIT_CODE%

:EXIT_EARLY
if defined OLD_CP chcp !OLD_CP! >nul 2>&1
exit /b 1
rem ============================================================
rem  TOOL_CONSTRUCTOR  выбор блоков с вердиктами гвардов.
rem  Клавиша V, только Advanced. Пресеты не заменяет, дополняет.
rem  Запись остаётся в модулях, здесь только выбор и вызов.
rem ============================================================
:TOOL_CONSTRUCTOR
call "%WP_LIB%\blocks.cmd" :BLOCKS_LOAD
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :FAIL "Реестр блоков не загрузился"
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    goto :MAIN_MENU
)
set /a CS_PAGE=1
set "CS_MSG="
call "%WP_LIB%\core.cmd" :MSG "Опрос гвардов по !BLK_COUNT! блокам, несколько секунд"
call "%WP_LIB%\blocks.cmd" :BLOCKS_VERDICT_ALL
:CS_LOOP
call "%WP_LIB%\blocks.cmd" :BLOCKS_CONFLICT
if defined WP_DESKTOP_TOKEN (
    echo !WP_DESKTOP_TOKEN!:screen
    for /l %%i in (1,1,!BLK_COUNT!) do (
        set "_ui_num=0%%i"
        for %%v in (!_ui_num:~-2!) do echo !WP_DESKTOP_TOKEN!:block^|%%i^|!BL_ID_%%v!^|!SEL_%%v!^|!VD_%%v!^|!BL_DESC_%%v!
    )
    if !BLK_CF_COUNT! gtr 0 echo   [CRITICAL] Конфликт:!_CF_LIST!
) else call "%WP_LIB%\blocks.cmd" :BLOCKS_SHOW !CS_PAGE!
if defined CS_MSG (
    echo   !CS_MSG!
    echo.
    set "CS_MSG="
)
set "CS_IN="
set "WP_QUESTION=Команда: "
call "%WP_LIB%\desktop_io.cmd" input CS_IN
if not defined CS_IN goto :CS_LOOP
set CS_IN | "%SystemRoot%\System32\findstr.exe" /i /r /x /c:"CS_IN=[0-9][0-9,; -]*" /c:"CS_IN=[a-z][a-z0-9 ]*" >nul
if errorlevel 1 (
    set "CS_MSG=Введи команду меню или список номеров блоков."
    goto :CS_LOOP
)
set "_c1=!CS_IN:~0,1!"
set "_dchk="
for /f "delims=0123456789" %%z in ("!_c1!") do set "_dchk=1"
if not defined _dchk (
    set "_nums=!CS_IN: =!"
    call "%WP_LIB%\blocks.cmd" :BLOCKS_TOGGLE "!_nums!"
    goto :CS_LOOP
)
set "CS_CMD="
set "CS_ARG="
for /f "tokens=1,* delims= " %%a in ("!CS_IN!") do (
    set "CS_CMD=%%a"
    set "CS_ARG=%%b"
)
if /i "!CS_CMD!"=="Q" goto :MAIN_MENU
if /i "!CS_CMD!"=="S" (
    set /a CS_PAGE+=1
    set /a "_csmax=(BLK_COUNT+19)/20"
    if !CS_PAGE! gtr !_csmax! set /a CS_PAGE=1
    goto :CS_LOOP
)
if /i "!CS_CMD!"=="N" (
    call "%WP_LIB%\blocks.cmd" :BLOCKS_CLEAR
    set "CS_MSG=Выбор снят"
    goto :CS_LOOP
)
if /i "!CS_CMD!"=="W" (
    call "%WP_LIB%\blocks.cmd" :BLOCKS_NEW
    set "CS_MSG=Новых блоков выбрано: !BLK_NEW_FOUND!"
    goto :CS_LOOP
)
if /i "!CS_CMD!"=="G" (
    call "%WP_LIB%\core.cmd" :MSG "Пересчёт вердиктов"
    call "%WP_LIB%\blocks.cmd" :BLOCKS_VERDICT_ALL
    set "CS_MSG=Вердикты обновлены"
    goto :CS_LOOP
)
if /i "!CS_CMD!"=="A" (
    if not defined CS_ARG (
        set "CS_MSG=A требует категорию: safe, warn, danger, exp, all"
    ) else (
        call "%WP_LIB%\blocks.cmd" :BLOCKS_ALL "!CS_ARG!"
        set "CS_MSG=Категория добавлена: !CS_ARG!"
    )
    goto :CS_LOOP
)
if /i "!CS_CMD!"=="B" (
    if not defined CS_ARG (
        set "CS_MSG=B требует базу: LIT, MIN, MED, WRK, MAX"
    ) else (
        call "%WP_LIB%\blocks.cmd" :BLOCKS_PRESET "!CS_ARG!"
        if errorlevel 1 (
            set "CS_MSG=Неизвестная база: !CS_ARG!"
        ) else (
            set "CS_MSG=База задана: !BLK_BASE!"
        )
    )
    goto :CS_LOOP
)
set "_pk=!CS_CMD:~0,1!"
if /i "!_pk!"=="E" (
    call "%WP_LIB%\blocks.cmd" :BLOCKS_PACK "!CS_CMD!"
    if errorlevel 1 (
        set "CS_MSG=Нет такой пачки: !CS_CMD!. Есть E1, E2, E3, E4"
    ) else (
        set "CS_MSG=Пачка добавлена: !CS_CMD!"
    )
    goto :CS_LOOP
)
if /i "!CS_CMD!"=="P" (
    call "%WP_LIB%\blocks.cmd" :BLOCKS_PLAN
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    goto :CS_LOOP
)
if /i "!CS_CMD!"=="X" goto :CS_APPLY
set "CS_MSG=Неизвестная команда: !CS_CMD!"
goto :CS_LOOP

:CS_APPLY
call "%WP_LIB%\blocks.cmd" :BLOCKS_CONFLICT
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :FAIL "Конфликт блоков:!_CF_LIST!"
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    goto :CS_LOOP
)
call "%WP_LIB%\blocks.cmd" :BLOCKS_SELSTAT
if !BS_N! equ 0 (
    set "CS_MSG=Выбор пуст, применять нечего"
    goto :CS_LOOP
)
call "%WP_LIB%\blocks.cmd" :BLOCKS_PLAN
echo.
if !BS_IRR! gtr 0 echo   [WARN] Необратимых блоков: !BS_IRR!. Откат их не вернёт.
if !BS_DANGER! gtr 0 echo   [WARN] Операций категории danger: !BS_DANGER!
if !BS_EXP! gtr 0 echo   [WARN] Операций категории exp: !BS_EXP!
echo.
call "%WP_LIB%\core.cmd" :CONFIRM "Применить выбранные блоки" N
if errorlevel 1 (
    set "CS_MSG=Применение отменено"
    goto :CS_LOOP
)
call :MODE_PREP "CONSTRUCTOR"
if errorlevel 1 goto :CS_LOOP
call "%WP_LIB%\blocks.cmd" :BLOCKS_APPLY
goto :MODE_SUMMARY

rem ============================================================
rem  TOOL_SMART  враппер для экрана здоровья дисков.
rem ============================================================
:TOOL_SMART
call "%WP_LIB%\tools.cmd" :SMART_SCREEN
goto :MAIN_MENU


:TOOL_STARTUP_SETTINGS
start "" ms-settings:startupapps
goto :MAIN_MENU

:TOOL_BACKGROUND
if !WIN_BUILD! geq 22000 (
    echo   Выбери приложение, затем Дополнительные параметры и Разрешения для фоновых приложений.
    start "" ms-settings:appsfeatures
) else (
    echo   Выбери приложение в списке фоновых разрешений.
    start "" ms-settings:privacy-backgroundapps
)
echo   При запрете могут задерживаться уведомления и синхронизация. Для возврата открой ту же страницу.
echo   Для классических программ доступные настройки находятся в самом приложении.
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :MAIN_MENU

:TOOL_AUTORUN
call "%WP_LIB%\tools.cmd" :AUTORUN_SCREEN
goto :MAIN_MENU

:TOOL_FRAMETIME
call "%WP_LIB%\tools.cmd" :FRAMETIME_SCREEN
goto :MAIN_MENU
:: END OF FILE | Всего твиков в файле: 0

@echo off
rem ============================================================
rem  WinPulse 7.1 "Rebuild"  |  lib\guard.cmd  |  ЧАСТЬ 1/2
rem  Единая точка предусловий. Защита от применения твика на
rem  конфигурации, для которой он не предназначен.
rem
rem  Кодировка: UTF-8 БЕЗ BOM, CRLF. Символ "!" в echo запрещён.
rem  Вызов:  call "%WP_LIB%\guard.cmd" :G_xxx "arg" "TAG"
rem  Свой setlocal ЗАПРЕЩЁН.
rem
rem  ТРИ УРОВНЯ:
rem    HARD  твик не применяется, обхода нет даже в Advanced
rem    SOFT  нужен Advanced Mode и ввод слова YES заглавными
rem    INFO  тихий пропуск: твик не для этой конфигурации
rem
rem  ВОЗВРАТ: 0 = можно, 1 = отказ/неприменимо, 2 = жёсткий блок
rem  Проверка вызывающим: if errorlevel 1 exit /b 0
rem
rem  FAIL-CLOSED: неизвестные данные = запрет. Провал детекта
rem  ЗАКРЫВАЕТ твик, а не открывает. В 6.x упавший
rem  Get-PhysicalDisk давал ALL_SSD=1 и дефраг гасил HDD.
rem
rem  ВЫЗЫВАТЬ ДО BLOCK_BEGIN, иначе аудит операций соврёт.
rem  Счётчики WP_OP_* не трогаем, только свои WP_GUARD_*.
rem
rem  WP_GUARD_PROBE=1 - пробник для матрицы: без логов и счётчиков.
rem ============================================================
if "%~1"=="" exit /b 9009
if not defined WP_LIB exit /b 9009
if not defined JOURNAL exit /b 9009
set "__EP=%~1"
shift
goto %__EP%

rem ============================================================
rem  G_INIT - сброс счётчиков перед режимом
rem ============================================================
:G_INIT
set /a WP_GUARD_HARD=0
set /a WP_GUARD_SOFT=0
set /a WP_GUARD_INFO=0
set "WP_GUARD_LAST="
set "WP_GUARD_PROBE=0"
if not defined WP_SESSION_DIR exit /b 1
if not exist "%WP_SESSION_DIR%" mkdir "%WP_SESSION_DIR%" >nul 2>&1
set "GUARD_LOG=%WP_SESSION_DIR%\guards.txt"
if not exist "%GUARD_LOG%" type nul > "%GUARD_LOG%"
exit /b 0

rem ============================================================
rem  Логгеры решений. В пробнике молчат и не считают.
rem ============================================================
:G_HARD
if "%WP_GUARD_PROBE%"=="1" (
    set "WP_PROBE_KIND=HARD"
    exit /b 2
)
set "_GT=%~1"
set "_GR=%~2"
set "WP_GUARD_LAST=HARD"
set /a WP_GUARD_HARD+=1
echo   [BLOCK] !_GT!: !_GR!
>>"%GUARD_LOG%" echo HARD^|!_GT!^|!_GR!
>>"%SESSION_LOG%" echo [%TIME%] [GUARD-HARD] !_GT! !_GR!
exit /b 2

:G_SOFT_LOG
if "%WP_GUARD_PROBE%"=="1" (
    set "WP_PROBE_KIND=SOFT"
    exit /b 1
)
set "WP_GUARD_LAST=SOFT"
set /a WP_GUARD_SOFT+=1
echo   [SKIP] !_GT!: отказ пользователя
>>"%GUARD_LOG%" echo SOFT^|!_GT!^|!_GR!
>>"%SESSION_LOG%" echo [%TIME%] [GUARD-SOFT] !_GT! !_GR!
exit /b 1

:G_INFO
if "%WP_GUARD_PROBE%"=="1" (
    set "WP_PROBE_KIND=INFO"
    exit /b 1
)
set "_GT=%~1"
set "_GR=%~2"
set "WP_GUARD_LAST=INFO"
set /a WP_GUARD_INFO+=1
echo   [SKIP] !_GT!: !_GR!
>>"%GUARD_LOG%" echo INFO^|!_GT!^|!_GR!
>>"%SESSION_LOG%" echo [%TIME%] [GUARD-INFO] !_GT! !_GR!
exit /b 1

rem ============================================================
rem  G_CONFIRM  %1 TAG  %2 текст риска
rem  SOFT: Advanced Mode плюс ввод YES заглавными.
rem  В dry-run проходит автоматически: песочница должна показать
rem  полный план, а не остановиться на первом вопросе.
rem ============================================================
:G_CONFIRM
if "%WP_GUARD_PROBE%"=="1" exit /b 1
set "_GT=%~1"
set "_GR=%~2"
if "%WP_DRYRUN%"=="1" goto :G_CONFIRM_DRY
if "%ADVANCED_MODE%"=="1" goto :G_CONFIRM_ASK
call "%WP_LIB%\core.cmd" :WARN "!_GT!: !_GR!"
call "%WP_LIB%\core.cmd" :MSG "Нужен Advanced Mode, включите в настройках WinPulse"
goto :G_SOFT_LOG
:G_CONFIRM_DRY
echo   [PLAN] confirm !_GT!
exit /b 0
:G_CONFIRM_ASK
echo.
echo   [RISK] !_GT!
echo   !_GR!
echo.
echo   Введите YES заглавными для применения, любой другой ввод - отказ.
set "_GIN="
set "WP_QUESTION=Ввод: "
call "%WP_LIB%\desktop_io.cmd" input _GIN
if "!_GIN!"=="YES" goto :G_CONFIRM_YES
goto :G_SOFT_LOG
:G_CONFIRM_YES
set "WP_GUARD_LAST=OK"
>>"%GUARD_LOG%" echo SOFT_OK^|!_GT!^|!_GR!
>>"%SESSION_LOG%" echo [%TIME%] [GUARD-SOFT-OK] !_GT!
exit /b 0

rem ============================================================
rem  G_ADVANCED  %1 TAG - просто требование Advanced Mode
rem ============================================================
:G_ADVANCED
set "_GT=%~1"
if "%ADVANCED_MODE%"=="1" exit /b 0
set "_GR=требуется Advanced Mode"
call "%WP_LIB%\core.cmd" :MSG "!_GT!: нужен Advanced Mode"
goto :G_SOFT_LOG

rem ============================================================
rem  G_RAM  %1 минимум GB  %2 TAG - жёсткий порог
rem ============================================================
:G_RAM
set "_GN=%~1"
set "_GT=%~2"
if not "!RAM_VALID!"=="1" (
    call :G_HARD "!_GT!" "объём RAM не определён, твик запрещён"
    exit /b 2
)
if !RAM_GB! lss !_GN! (
    call :G_HARD "!_GT!" "RAM !RAM_GB! GB, требуется !_GN!+ GB"
    exit /b 2
)
exit /b 0

rem ============================================================
rem  G_RAM_SOFT  %1 рекомендация GB  %2 TAG
rem ============================================================
:G_RAM_SOFT
set "_GN=%~1"
set "_GT=%~2"
if not "!RAM_VALID!"=="1" (
    call :G_HARD "!_GT!" "объём RAM не определён, твик запрещён"
    exit /b 2
)
if !RAM_GB! geq !_GN! exit /b 0
call :G_CONFIRM "!_GT!" "RAM !RAM_GB! GB, рекомендуется !_GN!+ GB. Возможен своп и просадки"
exit /b !errorlevel!

rem ============================================================
rem  G_SSD  %1 TAG - загрузочный диск обязан быть SSD
rem ============================================================
:G_SSD
set "_GT=%~1"
if /i "!BOOT_DISK_TYPE!"=="SSD" exit /b 0
if /i "!BOOT_DISK_TYPE!"=="HDD" (
    call :G_HARD "!_GT!" "загрузочный диск HDD, твик только для SSD"
    exit /b 2
)
call :G_HARD "!_GT!" "тип загрузочного диска не определён"
exit /b 2

rem ============================================================
rem  G_ALLSSD  %1 TAG - все диски SSD, без неизвестных.
rem  Здесь ловится сценарий "чувак с HDD гасит SysMain и дефраг".
rem  Медиатип Unspecified на RAID-контроллере НЕ считается SSD.
rem ============================================================
:G_ALLSSD
set "_GT=%~1"
if !DISK_COUNT! leq 0 (
    call :G_HARD "!_GT!" "список дисков не получен"
    exit /b 2
)
if !HDD_COUNT! gtr 0 (
    call :G_HARD "!_GT!" "в системе HDD: !HDD_COUNT! шт, кэш и дефраг нужны"
    exit /b 2
)
if !DISK_UNKNOWN! gtr 0 (
    call :G_HARD "!_GT!" "тип части дисков не определён: !DISK_UNKNOWN! шт"
    exit /b 2
)
if not "!ALL_SSD!"=="1" (
    call :G_HARD "!_GT!" "не все диски подтверждены как SSD"
    exit /b 2
)
exit /b 0

rem ============================================================
rem  G_NOTLAPTOP  %1 TAG
rem  Исключение: батарея есть, но корпус Desktop и питание от
rem  сети - это ИБП, а не ноутбук. Ложный блок тут не нужен.
rem ============================================================
:G_NOTLAPTOP
set "_GT=%~1"
if "%DETECT_MODE%"=="fallback" goto :G_NOTLAPTOP_UNKNOWN
if not "!IS_LAPTOP!"=="1" exit /b 0
if /i not "!CHASSIS!"=="Desktop" goto :G_NOTLAPTOP_BLOCK
if "!ON_BATTERY!"=="1" goto :G_NOTLAPTOP_BLOCK
call "%WP_LIB%\core.cmd" :WARN "!_GT!: батарея есть, но корпус Desktop и питание от сети, похоже ИБП"
exit /b 0
:G_NOTLAPTOP_BLOCK
call :G_HARD "!_GT!" "ноутбук: перегрев и потеря автономности"
exit /b 2
:G_NOTLAPTOP_UNKNOWN
call :G_HARD "!_GT!" "тип корпуса не определён, ноутбук не исключён"
exit /b 2

rem ============================================================
rem  G_ACPOWER  %1 TAG - только питание от сети
rem ============================================================
:G_ACPOWER
set "_GT=%~1"
if "%DETECT_MODE%"=="fallback" (
    call :G_HARD "!_GT!" "состояние питания не определено"
    exit /b 2
)
if "!ON_BATTERY!"=="1" (
    call :G_HARD "!_GT!" "работа от батареи"
    exit /b 2
)
exit /b 0

rem ============================================================
rem  G_CPU_HYBRID  %1 TAG - реальные E-cores, а не "имя похожее"
rem ============================================================
:G_CPU_HYBRID
set "_GT=%~1"
if "!CPU_HYBRID!"=="1" exit /b 0
call :G_HARD "!_GT!" "CPU не гибридный, E-cores не обнаружены"
exit /b 2

rem ============================================================
rem  G_CPU_OLD  %1 max Intel gen  %2 max AMD series  %3 TAG
rem  Новее порога - жёсткий блок. Неизвестное поколение - тоже.
rem ============================================================
:G_CPU_OLD
set "_GI=%~1"
set "_GA=%~2"
set "_GT=%~3"
if /i "!CPU_VENDOR!"=="Intel" goto :G_CPU_OLD_I
if /i "!CPU_VENDOR!"=="AMD" goto :G_CPU_OLD_A
call :G_HARD "!_GT!" "вендор CPU не определён"
exit /b 2
:G_CPU_OLD_I
if !CPU_SERIES! leq 0 (
    call :G_HARD "!_GT!" "поколение Intel не определено"
    exit /b 2
)
if !CPU_SERIES! gtr !_GI! (
    call :G_HARD "!_GT!" "Intel gen !CPU_SERIES!, разрешено gen !_GI! и старше"
    exit /b 2
)
exit /b 0
:G_CPU_OLD_A
if !CPU_SERIES! leq 0 (
    call :G_HARD "!_GT!" "серия AMD не определена"
    exit /b 2
)
if !CPU_SERIES! gtr !_GA! (
    call :G_HARD "!_GT!" "Ryzen series !CPU_SERIES!, разрешено !_GA! и старше"
    exit /b 2
)
exit /b 0

rem ============================================================
rem  G_GPU_VENDOR  %1 AMD|NVIDIA|Intel  %2 TAG
rem  Не тот вендор - INFO, а не блок: предупреждать не о чем.
rem ============================================================
:G_GPU_VENDOR
set "_GV=%~1"
set "_GT=%~2"
if /i "!GPU_VENDOR!"=="!_GV!" exit /b 0
call :G_INFO "!_GT!" "твик только для !_GV!, обнаружено !GPU_VENDOR!"
exit /b 1

rem ============================================================
rem  G_HWID  %1 TAG - без HWID ветка Enum\PCI не строится
rem ============================================================
:G_HWID
set "_GT=%~1"
if defined GPU_HWID exit /b 0
call :G_HARD "!_GT!" "instance path GPU не определён, делайте вручную через MSI Utility v3"
exit /b 2

rem ============================================================
rem  G_BUILD  %1 минимальный build  %2 TAG
rem ============================================================
:G_BUILD
set "_GB=%~1"
set "_GT=%~2"
if !WIN_BUILD! geq !_GB! exit /b 0
call :G_HARD "!_GT!" "build !WIN_BUILD!, требуется !_GB!+"
exit /b 2

rem ============================================================
rem  G_SECURITY_REFRESH - снимок безопасности, один раз за прогон.
rem  Если PS недоступен, SEC_AV_ACTIVE останется 0 и guard
rem  закроет твик. Это и есть fail-closed.
rem ============================================================
:G_SECURITY_REFRESH
if "%WP_SEC_LOADED%"=="1" exit /b 0
if not exist "%WP_RUN%" mkdir "%WP_RUN%" >nul 2>&1
set "_SF=%WP_RUN%\security.txt"
if exist "%_SF%" del /f /q "%_SF%" >nul 2>&1
call "%WP_LIB%\core.cmd" :PS_RUN get-security "%_SF%"
call "%WP_LIB%\backup.cmd" :LOAD_KV "%_SF%"
if not defined SEC_AV_ACTIVE set "SEC_AV_ACTIVE=0"
if not defined SEC_AV_THIRD set "SEC_AV_THIRD=none"
if not defined SEC_TAMPER set "SEC_TAMPER=Unknown"
if not defined SEC_RP_COUNT set "SEC_RP_COUNT=0"
if not defined SEC_RP_ENABLED set "SEC_RP_ENABLED=0"
if not defined SEC_BITLOCKER set "SEC_BITLOCKER=Unknown"
if not defined SEC_UAC set "SEC_UAC=-1"
if not defined SEC_GPU_DRIVER_AGE_DAYS set "SEC_GPU_DRIVER_AGE_DAYS=-1"
if not defined SEC_VBS set "SEC_VBS=Unknown"
if not defined SEC_HVCI set "SEC_HVCI=Unknown"
if not defined SEC_CREDENTIAL_GUARD set "SEC_CREDENTIAL_GUARD=Unknown"
if not defined SEC_SECUREBOOT set "SEC_SECUREBOOT=Unknown"
if not defined SEC_RISK_COUNT set "SEC_RISK_COUNT=0"
set "WP_SEC_LOADED=1"
exit /b 0

rem ============================================================
rem  G_SECURITY_INVALIDATE - после мутаций Defender снимок устарел
rem ============================================================
:G_SECURITY_INVALIDATE
set "WP_SEC_LOADED=0"
exit /b 0


rem ============================================================
rem  ЧАСТЬ 2/2. Безопасность, составные гейты, отчётность.
rem ============================================================

rem ============================================================
rem  G_AV  %1 TAG - нужен хоть какой-то активный антивирус
rem ============================================================
:G_AV
set "_GT=%~1"
call :G_SECURITY_REFRESH
if "!SEC_AV_ACTIVE!"=="1" exit /b 0
call :G_HARD "!_GT!" "активный антивирус не обнаружен"
exit /b 2

rem ============================================================
rem  G_AV_THIRD  %1 TAG - нужен именно сторонний AV.
rem  Для отключения Defender сам Defender уже не считается.
rem ============================================================
:G_AV_THIRD
set "_GT=%~1"
call :G_SECURITY_REFRESH
if not "!SEC_AV_THIRD!"=="none" exit /b 0
call :G_HARD "!_GT!" "стороннего AV нет, система останется без защиты вообще"
exit /b 2

rem ============================================================
rem  G_TAMPER  %1 TAG - Tamper всё равно не даст изменить Defender.
rem  INFO, а не блок: пользователь может снять Tamper сам.
rem ============================================================
:G_TAMPER
set "_GT=%~1"
call :G_SECURITY_REFRESH
if "!SEC_TAMPER!"=="1" (
    call :G_INFO "!_GT!" "Tamper Protection включён, снимите вручную в Безопасности Windows"
    exit /b 1
)
exit /b 0

rem ============================================================
rem  G_DISKSPACE  %1 минимум GB  %2 TAG
rem  Место нужно точке восстановления. Неизвестно - WARN, не блок:
rem  факт берётся из DriveInfo и неизвестным почти не бывает.
rem ============================================================
:G_DISKSPACE
set "_GN=%~1"
set "_GT=%~2"
if not "!FREE_SPACE_KNOWN!"=="1" (
    if "%WP_GUARD_PROBE%"=="1" exit /b 0
    call "%WP_LIB%\core.cmd" :WARN "!_GT!: свободное место не определено, проверка пропущена"
    exit /b 0
)
if !FREE_SPACE_GB! lss !_GN! (
    call :G_HARD "!_GT!" "свободно !FREE_SPACE_GB! GB, нужно !_GN!+ GB для точки восстановления"
    exit /b 2
)
exit /b 0

rem ============================================================
rem  G_NETWORK  %1 TAG - конфликт с Zapret/winws
rem ============================================================
:G_NETWORK
set "_GT=%~1"
if not "!ZAPRET_FOUND!"=="1" exit /b 0
if "%WP_GUARD_PROBE%"=="1" exit /b 1
call "%WP_LIB%\core.cmd" :WARN "Обнаружен Zapret или winws"
echo   После сетевых твиков он будет работать хуже, это ожидаемо.
echo   Лечение: переустановить Zapret из его собственного меню.
call :G_CONFIRM "!_GT!" "сетевые твики при активном Zapret могут оборвать интернет"
exit /b !errorlevel!

rem ============================================================
rem  G_GLOBAL  %1 TAG - общий гейт перед любым режимом.
rem  Деградация детекта НЕ блокирует режим целиком: телеметрия,
rem  задачи, UX и службы не зависят от железа и должны работать.
rem  Железозависимые твики закроются своими guard'ами.
rem ============================================================
:G_GLOBAL
set "_GT=%~1"
if not defined _GT set "_GT=MODE"
if not "!WIN_SUPPORTED!"=="1" (
    call :G_HARD "!_GT!" "сборка !WIN_BUILD! вне поддержки, нужен Win10 22H2 или Win11"
    exit /b 2
)
call :G_DISKSPACE 2 "!_GT!"
if errorlevel 1 exit /b 2
if "!PENDING_REBOOT!"=="1" (
    call :G_CONFIRM "!_GT!" "Windows ожидает перезагрузку, твики могут примениться некорректно"
    if errorlevel 1 exit /b 1
)
if "%WP_GUARD_PROBE%"=="1" exit /b 0
if defined DETECT_TIER (
    if not "!DETECT_TIER!"=="full" call "%WP_LIB%\core.cmd" :WARN "детект деградирован: !DETECT_TIER!, железозависимые твики будут закрыты"
)
if "!WP_RP_SKIPPED!"=="1" call "%WP_LIB%\core.cmd" :WARN "точка восстановления пропущена пользователем"
exit /b 0

rem ============================================================
rem  G_BANNER - компактная строка состояния для шапки меню.
rem  Метки про обойденную защиту видны постоянно, чтобы про них
rem  нельзя было забыть через два экрана.
rem ============================================================
:G_BANNER
set "_BT=full"
if defined DETECT_TIER set "_BT=!DETECT_TIER!"
if "!WP_DRYRUN!"=="1" echo   [DRY-RUN] ПЕСОЧНИКА: в систему ничего не пишется
echo   Detect: !_BT!   RAM: !RAM_GB! GB   Boot: !BOOT_DISK_TYPE!   Class: !SYSTEM_CLASS!
if "!WP_RP_OK!"=="1" echo   Restore point: !WP_RP_SEQ!
if "!WP_RP_SKIPPED!"=="1" echo   Restore point: SKIPPED BY USER
if "!WP_DEF_PROTECTION_REDUCED!"=="1" echo   Defender protection: REDUCED
if "!WP_SECURITY_REDUCED!"=="1" echo   System protection: REDUCED
if "!WP_BCD_SUSPENDED!"=="1" echo   BitLocker: SUSPENDED for one reboot
exit /b 0

rem ============================================================
rem  G_SUMMARY - отдельная секция сводки.
rem  Твик не "пропал", а осознанно не применён. Это разные вещи,
rem  и в 6.x они выглядели одинаково.
rem ============================================================
:G_SUMMARY
set /a "_GTOT=WP_GUARD_HARD+WP_GUARD_SOFT+WP_GUARD_INFO"
if !_GTOT! equ 0 exit /b 0
echo.
echo == ЗАБЛОКИРОВАНО ЗАЩИТОЙ ==
echo.
echo   Жёстких блокировок:     !WP_GUARD_HARD!
echo   Отказов пользователя:   !WP_GUARD_SOFT!
echo   Неприменимо к системе:  !WP_GUARD_INFO!
echo.
if not defined GUARD_LOG exit /b 0
if not exist "%GUARD_LOG%" exit /b 0
for /f "usebackq tokens=1,2,* delims=|" %%a in ("%GUARD_LOG%") do (
    if /i not "%%a"=="SOFT_OK" echo   [%%a] %%b - %%c
)
exit /b 0

rem ============================================================
rem  G_MVERDICT  %1 текст  %2 код возврата guard
rem ============================================================
:G_MVERDICT
set "_MT=%~1"
set "_MC=%~2"
if defined WP_DESKTOP_TOKEN echo !WP_DESKTOP_TOKEN!:guard^|!_MC!^|!_MT!
if "!_MC!"=="0" echo   [OK]    !_MT!
if "!_MC!"=="1" echo   [ASK]   !_MT!
if "!_MC!"=="2" echo   [BLOCK] !_MT!
exit /b 0

rem ============================================================
rem  G_MATRIX - экран "почему именно мне заблокировано".
rem  Вызывает НАСТОЯЩИЕ guard'ы в режиме пробника, поэтому
rem  пороги не дублируются и не разъезжаются с реальной логикой.
rem ============================================================
:G_MATRIX
set "WP_GUARD_PROBE=1"
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == ФАКТЫ СИСТЕМЫ ==
echo.
echo   OS:             !WIN_VER!
echo   Supported:      !WIN_SUPPORTED!    build !WIN_BUILD!.!WIN_UBR!
echo   Detect tier:    !DETECT_TIER!    не определено:!DETECT_MISSING!
echo   RAM:            !RAM_GB! GB    valid=!RAM_VALID!    source=!RAM_SOURCE!
echo   CPU:            !CPU_NAME!
echo   Cores/Threads:  !CPU_CORES! / !CPU_THREADS!    SMT=!CPU_SMT!
echo   Vendor/Series:  !CPU_VENDOR! / !CPU_SERIES!    gen=!CPU_GENERATION!
echo   Hybrid E-cores: !CPU_HYBRID!    topo=!CPU_TOPO_SOURCE!
echo   GPU:            !GPU_NAME!    vendor=!GPU_VENDOR!
if defined GPU_HWID (echo   GPU instance:   !GPU_HWID!) else (echo   GPU instance:   не определён)
echo   Boot disk:      !BOOT_DISK_TYPE!    bus=!BOOT_DISK_BUS!    source=!BOOT_DISK_SOURCE!
echo   Disks:          total=!DISK_COUNT!  hdd=!HDD_COUNT!  unknown=!DISK_UNKNOWN!  allSSD=!ALL_SSD!
echo   Chassis:        !CHASSIS!    laptop=!IS_LAPTOP!    onBattery=!ON_BATTERY!
echo   Free space:     !FREE_SPACE_GB! GB    known=!FREE_SPACE_KNOWN!
echo   Pending reboot: !PENDING_REBOOT!    Zapret=!ZAPRET_FOUND!
call :G_SECURITY_REFRESH
echo   AV active:      !SEC_AV_ACTIVE!    third=!SEC_AV_THIRD!    tamper=!SEC_TAMPER!
echo   VBS:            !SEC_VBS!    HVCI=!SEC_HVCI!    CredGuard=!SEC_CREDENTIAL_GUARD!
echo   Secure Boot:    !SEC_SECUREBOOT!    BitLocker=!SEC_BITLOCKER!
echo   UAC:            !SEC_UAC!    firewall domain/private/public=!SEC_FW_DOMAIN!/!SEC_FW_PRIVATE!/!SEC_FW_PUBLIC!
echo   GPU driver age: !SEC_GPU_DRIVER_AGE_DAYS! дней    дата !SEC_GPU_DRIVER_DATE!
echo   Restore points: !SEC_RP_COUNT!    enabled=!SEC_RP_ENABLED!
echo.
echo == ВЕРДИКТЫ ПО КЛЮЧЕВЫМ ТВИКАМ ==
echo.
call :G_GLOBAL "PROBE"
call :G_MVERDICT "Любой режим целиком" !errorlevel!
call :G_ALLSSD "PROBE"
call :G_MVERDICT "SysMain OFF / defragsvc OFF / Superfetch override" !errorlevel!
call :G_SSD "PROBE"
call :G_MVERDICT "Только для SSD-загрузки" !errorlevel!
call :G_RAM 8 "PROBE"
call :G_MVERDICT "MEMORY: DisablePagingExecutive" !errorlevel!
call :G_RAM 32 "PROBE"
call :G_MVERDICT "Kernel Paging combo / Memory Compression OFF" !errorlevel!
call :G_NOTLAPTOP "PROBE"
call :G_MVERDICT "C-states / Ultimate / BCD-таймеры - корпус" !errorlevel!
call :G_ACPOWER "PROBE"
call :G_MVERDICT "C-states / Ultimate / BCD-таймеры - питание" !errorlevel!
call :G_CPU_HYBRID "PROBE"
call :G_MVERDICT "Heterogeneous Thread Scheduling OFF" !errorlevel!
call :G_CPU_OLD 11 4000 "PROBE"
call :G_MVERDICT "TSC sync Legacy" !errorlevel!
call :G_HWID "PROBE"
call :G_MVERDICT "MSI Mode GPU" !errorlevel!
call :G_GPU_VENDOR AMD "PROBE"
call :G_MVERDICT "AMD ULPS OFF" !errorlevel!
call :G_GPU_VENDOR NVIDIA "PROBE"
call :G_MVERDICT "NVIDIA HDCP OFF" !errorlevel!
call :G_AV "PROBE"
call :G_MVERDICT "VBS / Spectre mitigations OFF" !errorlevel!
call :G_AV_THIRD "PROBE"
call :G_MVERDICT "Defender Realtime OFF" !errorlevel!
call :G_TAMPER "PROBE"
call :G_MVERDICT "Исключения и настройки Defender" !errorlevel!
call :G_BUILD 22000 "PROBE"
call :G_MVERDICT "Только Win11-специфичные твики" !errorlevel!
call :G_NETWORK "PROBE"
call :G_MVERDICT "Сетевые блоки при активном Zapret" !errorlevel!
echo.
echo   OK    применится без вопросов
echo   ASK   нужен Advanced Mode и ввод YES, либо отказ пользователя
echo   BLOCK не применится, причина в фактах выше
echo.
echo   Блокировка - не ошибка. Это защита от применения не на своей системе.
echo.
set "WP_GUARD_PROBE=0"
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
exit /b 0

:: END OF FILE | Всего твиков в файле: 0

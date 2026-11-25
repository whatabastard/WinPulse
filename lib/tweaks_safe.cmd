@echo off
rem ============================================================
rem  WinPulse 7.1 "Rebuild"  |  lib\tweaks_safe.cmd  |  ЧАСТЬ 1/3
rem  Безопасные твики: 132 операции в 19 блоках.
rem
rem  Кодировка: UTF-8 БЕЗ BOM, CRLF. Символ "!" в echo запрещён.
rem  Вызов:  call "%WP_LIB%\tweaks_safe.cmd" :T_ИМЯ [args]
rem  Свой setlocal ЗАПРЕЩЁН.
rem
rem  ЖЁСТКИЕ ПРАВИЛА ЭТОГО МОДУЛЯ:
rem  1. Ни одной прямой reg add / sc config / powercfg / netsh.
rem     Только обёртки core.cmd и backup.cmd, иначе мимо журнала.
rem  2. Guard вызывается ДО BLOCK_BEGIN, иначе аудит соврёт.
rem  3. HKCU только через !WP_HKCU!: при запуске от другого
rem     админа твики должны идти в куст реального пользователя.
rem  4. Число в BLOCK_BEGIN = число из инвентаря.
rem     BLOCK_END сам сверит факт с ожиданием.
rem
rem  Блоки части 1: TELEMETRY NET_STD NET_PORTS POWER POWER_THROTTLE
rem ============================================================
if "%~1"=="" exit /b 9009
if not defined WP_LIB exit /b 9009
if not defined JOURNAL exit /b 9009
set "__EP=%~1"
shift
goto %__EP%

rem ============================================================
rem  NET_IF_LOAD - список активных интерфейсов для Nagle.
rem  TcpAckFrequency и TCPNoDelay в Tcpip\Parameters ГЛОБАЛЬНО
rem  не работают: стек читает их из подключей Interfaces\{GUID}.
rem  В 6.x они писались в корень и не делали ничего.
rem ============================================================
:NET_IF_LOAD
if defined IF_COUNT (
    for /l %%i in (1,1,%IF_COUNT%) do (
        set "IF_%%i_GUID="
        set "IF_%%i_NAME="
    )
)
set "IF_COUNT="
if not exist "%WP_RUN%" mkdir "%WP_RUN%" >nul 2>&1
set "_NIF=%WP_RUN%\ifaces.txt"
if exist "%_NIF%" del /f /q "%_NIF%" >nul 2>&1
call "%WP_LIB%\core.cmd" :PS_RUN get-interfaces "%_NIF%"
call "%WP_LIB%\backup.cmd" :LOAD_KV "%_NIF%"
if not defined IF_COUNT set "IF_COUNT=0"
exit /b 0

rem ============================================================
rem  IFACE_SET  %1 имя значения  %2 тип  %3 данные
rem  Пишет в каждый активный интерфейс, но считается ОДНОЙ
rem  операцией по инвентарю. Журнал содержит каждую запись
rem  отдельно, поэтому откат вернёт все адаптеры.
rem ============================================================
:IFACE_SET
set "_IV=%~1"
set "_IT=%~2"
set "_ID=%~3"
if "!IF_COUNT!"=="0" (
    call "%WP_LIB%\core.cmd" :SKIP "нет активных интерфейсов для !_IV!"
    exit /b 0
)
call "%WP_LIB%\core.cmd" :AGG_BEGIN
for /l %%i in (1,1,!IF_COUNT!) do (
    set "_IG=!IF_%%i_GUID!"
    if defined _IG call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\!_IG!" "!_IV!" "!_IT!" "!_ID!"
)
call "%WP_LIB%\core.cmd" :AGG_END "!_IV! = !_ID! по адаптерам"
exit /b 0

rem ============================================================
rem  T_TELEMETRY - 24 операции
rem  Guard не нужен: приватность безопасна на любой конфигурации.
rem ============================================================
:T_TELEMETRY
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "TELEMETRY" 24
call "%WP_LIB%\core.cmd" :SC_SET "DiagTrack" "disabled"
call "%WP_LIB%\core.cmd" :SC_SET "dmwappushservice" "disabled"
call "%WP_LIB%\core.cmd" :SC_STOP "DiagTrack"
call "%WP_LIB%\core.cmd" :SC_STOP "dmwappushservice"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" "AllowTelemetry" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "DoNotShowFeedbackNotifications" REG_DWORD "1"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_TrackProgs" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\Siuf\Rules" "NumberOfSIUFInPeriod" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-310093Enabled" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338387Enabled" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338388Enabled" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338389Enabled" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338393Enabled" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-353694Enabled" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-353696Enabled" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-353698Enabled" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SystemPaneSuggestionsEnabled" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SilentInstalledAppsEnabled" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" "EnableActivityFeed" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" "UploadUserActivities" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat" "AITEnable" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting" "Disabled" REG_DWORD "1"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_NET_STD - 10 операций
rem ============================================================
:T_NET_STD
call "%WP_LIB%\guard.cmd" :G_NETWORK "NET_STD"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "NET_STD" 10
call "%WP_LIB%\core.cmd" :MSG "Стек TCP перестроится, интернет может моргнуть на 10-30 секунд"
call :NET_IF_LOAD
call :IFACE_SET "TcpAckFrequency" REG_DWORD "1"
call :IFACE_SET "TCPNoDelay" REG_DWORD "1"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" "DefaultTTL" REG_DWORD "64"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" "CacheHashTableBucketSize" REG_DWORD "1"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" "CacheHashTableSize" REG_DWORD "384"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" "MaxCacheEntryTtlLimit" REG_DWORD "86400"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" "MaxSOACacheEntryTtlLimit" REG_DWORD "300"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex" REG_DWORD "4294967295"
call "%WP_LIB%\core.cmd" :NETSH_TCP "autotuninglevel" "normal" "normal"
call "%WP_LIB%\core.cmd" :NET_FLUSH "dns"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_NET_PORTS - 4 операции
rem  SackOpts и AFD NonblockingSendSpecialCase - легаси из XP.
rem  Значения сохранены как в исходном списке, вреда не несут,
rem  но на Win10/11 стек их игнорирует. Помечено в логе.
rem ============================================================
:T_NET_PORTS
call "%WP_LIB%\guard.cmd" :G_NETWORK "NET_PORTS"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "NET_PORTS" 4
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" "MaxUserPort" REG_DWORD "65534"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" "TcpTimedWaitDelay" REG_DWORD "30"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" "SackOpts" REG_DWORD "1"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Services\AFD\Parameters" "NonblockingSendSpecialCase" REG_DWORD "1"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_POWER - 5 операций
rem  DC везде KEEP: на ноутбуке эти значения съедают батарею,
rem  а игровой смысл имеют только от сети.
rem  powercfg -attributes не вызываем: setacvalueindex работает
rem  и по скрытым настройкам, а видимость в GUI - не твик
rem  и в журнал не попадёт. Лишнее незаметное изменение не нужно.
rem ============================================================
:T_POWER
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "POWER" 5
if "!IS_LAPTOP!"=="1" call "%WP_LIB%\core.cmd" :WARN "ноутбук: значения применяются только к питанию от сети"
call "%WP_LIB%\core.cmd" :POWER_SCHEME "SCHEME_MIN"
call "%WP_LIB%\core.cmd" :POWER_SET "SUB_PROCESSOR" "CPMINCORES" "100" "KEEP"
call "%WP_LIB%\core.cmd" :POWER_SET "SUB_PROCESSOR" "CPMAXCORES" "100" "KEEP"
call "%WP_LIB%\core.cmd" :POWER_SET "2a737441-1930-4402-8d77-b2bebba308a3" "48e6b7a6-50f5-4782-a5d4-53bb8f07e226" "0" "KEEP"
call "%WP_LIB%\core.cmd" :POWER_SET "SUB_PROCESSOR" "PERFBOOSTMODE" "2" "KEEP"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_POWER_THROTTLE - 2 операции
rem  Создание ключа считается отдельно, как в инвентаре.
rem  REG_KEY с COUNT учитывает создание или пропуск.
rem ============================================================
:T_POWER_THROTTLE
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "POWER_THROTTLE" 2
if "%WP_DRYRUN%"=="1" (
    call "%WP_LIB%\core.cmd" :PLAN "create key PowerThrottling"
) else (
    call "%WP_LIB%\core.cmd" :REG_KEY "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" COUNT
    if errorlevel 1 (
        call "%WP_LIB%\core.cmd" :SKIP "зависимое значение: ключ недоступен"
        call "%WP_LIB%\core.cmd" :BLOCK_END
        exit /b 1
    )
)
call "%WP_LIB%\core.cmd" :MSG "Троттлинг фона оставляем включённым: EcoQoS снижает частоту фоновых задач, не игры"
call "%WP_LIB%\core.cmd" :MSG "PowerThrottlingOff=1 из чужих оптимизаторов разрешает фону отбирать CPU у игры"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" "PowerThrottlingOff" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0


rem ============================================================
rem  T_UWP  %1 selective|full   (по умолчанию selective)
rem  full включает Microsoft.BingSearch и пакет Widgets,
rem  поэтому спрашиваем и при отказе уходим на selective.
rem  В dry-run CONFIRM берёт дефолт Y и показывает полный план.
rem  Удаление только для целевого SID, provisioned не трогаем.
rem ============================================================
:T_UWP
set "_UM=%~1"
if /i "!_UM!"=="full" (
    call "%WP_LIB%\core.cmd" :WARN "full удаляет Bing-приложения, поиск в Пуске и пакет Widgets"
    call "%WP_LIB%\core.cmd" :CONFIRM "Удалять Bing, поиск и Widgets" Y
    if errorlevel 1 set "_UM=selective"
)
set "_UN=6"
if /i "!_UM!"=="full" (set "_UM=full" & set "_UN=13")
if /i not "!_UM!"=="full" set "_UM=selective"
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "UWP" !_UN!
call "%WP_LIB%\core.cmd" :MSG "Удаление только для текущего пользователя, необратимо"
call "%WP_LIB%\backup.cmd" :APPX_REMOVE "!_UM!"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_SCHTASKS - 7 операций
rem ============================================================
:T_SCHTASKS
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "SCHTASKS" 7
call "%WP_LIB%\core.cmd" :TASK_DISABLE "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator"
call "%WP_LIB%\core.cmd" :TASK_DISABLE "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip"
call "%WP_LIB%\core.cmd" :TASK_DISABLE "\Microsoft\Windows\Application Experience\ProgramDataUpdater"
call "%WP_LIB%\core.cmd" :TASK_DISABLE "\Microsoft\Windows\Feedback\Siuf\DmClient"
call "%WP_LIB%\core.cmd" :TASK_DISABLE "\Microsoft\Windows\Windows Error Reporting\QueueReporting"
call "%WP_LIB%\core.cmd" :TASK_DISABLE "\Microsoft\Windows\MemoryDiagnostic\RunFullMemoryDiagnostic"
call "%WP_LIB%\core.cmd" :TASK_DISABLE "\Microsoft\Windows\Maintenance\WinSAT"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_DEFENDER_EXC - 10 операций
rem  Tamper защищает и исключения тоже, поэтому guard стоит
rem  ДО блока: иначе получим 10 честных FAIL вместо одного
rem  понятного SKIP с причиной.
rem ============================================================
:T_DEFENDER_EXC
call "%WP_LIB%\guard.cmd" :G_TAMPER "DEFENDER_EXC"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "DEFENDER_EXC" 10
call "%WP_LIB%\backup.cmd" :DEF_EXCL "path" "C:\Program Files (x86)\Steam" "add"
call "%WP_LIB%\backup.cmd" :DEF_EXCL "path" "C:\Program Files\Steam" "add"
call "%WP_LIB%\backup.cmd" :DEF_EXCL "path" "C:\Program Files\Epic Games" "add"
call "%WP_LIB%\backup.cmd" :DEF_EXCL "path" "C:\Games" "add"
call "%WP_LIB%\backup.cmd" :DEF_EXCL "path" "D:\Games" "add"
call "%WP_LIB%\backup.cmd" :DEF_EXCL "proc" "cs2.exe" "add"
call "%WP_LIB%\backup.cmd" :DEF_EXCL "proc" "csgo.exe" "add"
call "%WP_LIB%\backup.cmd" :DEF_EXCL "proc" "steam.exe" "add"
call "%WP_LIB%\backup.cmd" :DEF_EXCL "proc" "steamwebhelper.exe" "add"
call "%WP_LIB%\backup.cmd" :DEF_EXCL "proc" "Discord.exe" "add"
call "%WP_LIB%\core.cmd" :BLOCK_END
call "%WP_LIB%\guard.cmd" :G_SECURITY_INVALIDATE
exit /b 0

rem ============================================================
rem  T_SERVICES - 3 операции
rem ============================================================
:T_SERVICES
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "SERVICES" 3
call "%WP_LIB%\core.cmd" :SC_SET "Fax" "disabled"
call "%WP_LIB%\core.cmd" :SC_SET "RemoteRegistry" "disabled"
call "%WP_LIB%\core.cmd" :SC_SET "RetailDemo" "disabled"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_SPOOLER - 2 операции
rem  Спрашиваем всех, а не только десктопы: принтер бывает
rem  и у ноутбука, и у десктопа его может не быть.
rem  Отказ = блок не начинается, счётчики не тронуты.
rem ============================================================
:T_SPOOLER
call "%WP_LIB%\core.cmd" :MSG "Диспетчер печати нужен для печати и для части PDF-принтеров"
call "%WP_LIB%\core.cmd" :CONFIRM "Отключить диспетчер печати" N
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :MSG "Spooler оставлен включённым"
    exit /b 0
)
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "SPOOLER" 2
call "%WP_LIB%\core.cmd" :SC_STOP "Spooler"
call "%WP_LIB%\core.cmd" :SC_SET "Spooler" "disabled"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_DEFRAG - 1 операция
rem  G_ALLSSD закрывает сценарий "HDD плюс отключить дефраг".
rem  G_CONFIRM про Retrim: отключение defragsvc убивает и
rem  плановый TRIM для SSD, это не очевидно из названия твика.
rem  На Novice блок не применится, дефраг останется включён.
rem ============================================================
:T_DEFRAG
call "%WP_LIB%\guard.cmd" :G_ALLSSD "DEFRAG"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_CONFIRM "DEFRAG" "Отключение defragsvc убирает и плановый Retrim для SSD. TRIM по требованию продолжит работать, но обслуживать диск придётся вручную через defrag /L"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "DEFRAG" 1
call "%WP_LIB%\core.cmd" :SC_SET "defragsvc" "disabled"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0


rem ============================================================
rem  ЧАСТЬ 3/3. Визуал, игры, UX, работа, обслуживание плюс
rem  новые блоки из сверки с OptimizerDuck: INPUT, PRIVACY_EXT, WEBDAV.
rem
rem  WP_VISUAL_PROFILE выставляется здесь и читается warn-блоком
rem  VISUAL_AGG. При Keep визуал не трогают ОБА блока.
rem ============================================================

rem ============================================================
rem  MAINT_PATHS - пути РЕАЛЬНОГО пользователя, а не админа.
rem  При запуске "от имени администратора" %TEMP% и %LocalAppData%
rem  указывают в профиль админа, и чистка ушла бы не туда.
rem  ProfileImagePath у обычных юзеров литеральный; у системных
rem  аккаунтов там %SystemRoot%, но их SID мы не берём.
rem ============================================================
:MAINT_PATHS
set "_U_PROFILE="
set "_U_SID=!CONSOLE_SID!"
if not defined _U_SID set "_U_SID=!CURRENT_SID!"
if defined _U_SID call "%WP_LIB%\detect.cmd" :DQ "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\!_U_SID!" "ProfileImagePath" _U_PROFILE
if not defined _U_PROFILE set "_U_PROFILE=%USERPROFILE%"
set "_U_TEMP=!_U_PROFILE!\AppData\Local\Temp"
set "_U_LOCAL=!_U_PROFILE!\AppData\Local"
exit /b 0

rem ============================================================
rem  T_VISUAL  %1 Performance|Balanced|Comfort|Work|Keep
rem  10 операций. Профиль-зависимые пункты честно рапортуют SKIP,
rem  поэтому итог всегда 10 и аудит не врёт.
rem  Keep - блок не начинается вообще, счётчики не тронуты.
rem ============================================================
:T_VISUAL
set "_VP=%~1"
if /i not "%~2"=="explicit" if defined WP_VISUAL_CHOICE if /i not "!WP_VISUAL_CHOICE!"=="Auto" set "_VP=!WP_VISUAL_CHOICE!"
if not defined _VP set "_VP=!WP_VISUAL_PROFILE!"
if not defined _VP set "_VP=Balanced"
set "_VPOK=0"
for %%p in (Performance Balanced Comfort Work Keep MotionOnly) do (
    if /i "!_VP!"=="%%p" (set "_VP=%%p" & set "_VPOK=1")
)
if "!_VPOK!"=="0" set "_VP=Balanced"
if not "%WP_TWEAK_PROBE%"=="1" set "WP_VISUAL_PROFILE=!_VP!"
if /i "!_VP!"=="Keep" (
    call "%WP_LIB%\core.cmd" :MSG "Визуал сохранён по выбору пользователя, блоки VISUAL и VISUAL_AGG пропущены"
    exit /b 0
)
set "_V_MSD="
set "_V_ANIM=0"
set "_V_TRANS=0"
set "_V_FX=0"
set "_V_COMPACT=0"
if /i "!_VP!"=="MotionOnly" set "_V_ANIM=1"
if /i "!_VP!"=="Performance" (set "_V_ANIM=1" & set "_V_FX=1" & set "_V_COMPACT=1")
if /i "!_VP!"=="Balanced"    (set "_V_MSD=100" & set "_V_ANIM=1" & set "_V_COMPACT=1")
if /i "!_VP!"=="Comfort"     (set "_V_MSD=200")
if /i "!_VP!"=="Work"        (set "_V_MSD=100" & set "_V_TRANS=1")
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "VISUAL" 10
call "%WP_LIB%\core.cmd" :MSG "Профиль визуала: !_VP!"
if "!_V_MSD!"=="100" (
    call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Control Panel\Desktop" "MenuShowDelay" REG_SZ "100"
) else (
    call "%WP_LIB%\core.cmd" :SKIP "MenuShowDelay=100 не для профиля !_VP!"
)
if "!_V_MSD!"=="200" (
    call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Control Panel\Desktop" "MenuShowDelay" REG_SZ "200"
) else (
    call "%WP_LIB%\core.cmd" :SKIP "MenuShowDelay=200 не для профиля !_VP!"
)
if "!_V_ANIM!"=="1" (
    call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Control Panel\Desktop\WindowMetrics" "MinAnimate" REG_SZ "0"
) else (
    call "%WP_LIB%\core.cmd" :SKIP "анимации сохранены профилем !_VP!"
)
if "!_V_TRANS!"=="1" (
    call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" REG_DWORD "1"
) else (
    call "%WP_LIB%\core.cmd" :SKIP "прозрачностью управляет VISUAL_AGG, профиль !_VP!"
)
if "!_V_FX!"=="1" (
    call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" "VisualFXSetting" REG_DWORD "2"
) else (
    call "%WP_LIB%\core.cmd" :SKIP "VisualFXSetting сохранён профилем !_VP!"
)
if "!_V_FX!"=="1" (
    call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Control Panel\Desktop" "UserPreferencesMask" REG_BINARY "9012038010000000"
) else (
    call "%WP_LIB%\core.cmd" :SKIP "UserPreferencesMask сохранён профилем !_VP!"
)
if "!_V_COMPACT!"=="1" (
    call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "UseCompactMode" REG_DWORD "1"
) else (
    call "%WP_LIB%\core.cmd" :SKIP "компактный проводник не для профиля !_VP!"
)
if /i "!_VP!"=="MotionOnly" (
    call "%WP_LIB%\core.cmd" :SKIP "уведомления Проводника"
    call "%WP_LIB%\core.cmd" :SKIP "оформление входа"
    call "%WP_LIB%\core.cmd" :SKIP "фон экрана блокировки"
) else (
    call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSyncProviderNotifications" REG_DWORD "0"
    call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" "DisableAcrylicBackgroundOnLogon" REG_DWORD "1"
    call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "RotatingLockScreenEnabled" REG_DWORD "0"
)
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_GAMING - 10 операций
rem ============================================================
:T_GAMING
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "GAMING" 10
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\GameBar" "AllowAutoGameMode" REG_DWORD "1"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\GameBar" "AutoGameModeEnabled" REG_DWORD "1"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\GameBar" "UseNexusForGameBarEnabled" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\System\GameConfigStore" "GameDVR_Enabled" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\System\GameConfigStore" "GameDVR_FSEBehaviorMode" REG_DWORD "2"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\System\GameConfigStore" "GameDVR_HonorUserFSEBehaviorMode" REG_DWORD "1"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\System\GameConfigStore" "GameDVR_FSEBehavior" REG_DWORD "2"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\System\GameConfigStore" "GameDVR_DXGIHonorFSEWindowsCompatible" REG_DWORD "1"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_UX - 6 операций
rem  TaskbarDa на Win10 не существует, там другой механизм Feeds.
rem  Пишется только на Win11, иначе честный SKIP.
rem ============================================================
:T_UX
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "UX" 6
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" REG_DWORD "1"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "DisableWebSearch" REG_DWORD "1"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" "ConnectedSearchUseWeb" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" REG_DWORD "1"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" REG_DWORD "1"
if !WIN_BUILD! geq 22000 (
    call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarDa" REG_DWORD "0"
) else (
    call "%WP_LIB%\core.cmd" :SKIP "TaskbarDa: Widgets только на Win11, build !WIN_BUILD!"
)
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_WORK - 5 операций
rem  HAGS на старых GPU просто игнорируется драйвером,
rem  поэтому не блокируем, но предупреждаем и требуем ребут.
rem ============================================================
:T_WORK
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "WORK" 5
if /i "!GPU_VENDOR!"=="Unknown" call "%WP_LIB%\core.cmd" :WARN "вендор GPU не определён, HAGS может не примениться"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" REG_DWORD "2"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Control Panel\Desktop" "WaitToKillAppTimeout" REG_SZ "2000"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Control" "WaitToKillServiceTimeout" REG_SZ "2000"
call "%WP_LIB%\core.cmd" :SC_SET "WSearch" "delayed"
call "%WP_LIB%\core.cmd" :NETSH_SUPP "Internet" "ctcp" "default"
set "WP_REBOOT_REQUIRED=1"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_MAINT - 9 операций
rem  Свой .run лежит внутри WP_ROOT, а не в TEMP, поэтому
rem  чистка TEMP не может снести лок и рабочие файлы сессии.
rem  FontCache останавливается с NOCOUNT: это подготовка,
rem  а не операция по инвентарю.
rem ============================================================
:T_MAINT
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "MAINT" 9
call :MAINT_PATHS
call "%WP_LIB%\core.cmd" :MSG "Профиль для чистки: !_U_PROFILE!"
call "%WP_LIB%\core.cmd" :PURGE_FILES "!_U_TEMP!\*" "S"
call "%WP_LIB%\core.cmd" :PURGE_FILES "%WINDIR%\Temp\*" "S"
call "%WP_LIB%\core.cmd" :SC_STOP "FontCache" "NOCOUNT"
call "%WP_LIB%\core.cmd" :PURGE_FILES "%WINDIR%\ServiceProfiles\LocalService\AppData\Local\FontCache\*.dat" "N"
call "%WP_LIB%\core.cmd" :SC_START "FontCache"
call "%WP_LIB%\core.cmd" :PURGE_FILES "!_U_LOCAL!\Microsoft\Windows\Explorer\thumbcache_*.db" "N"
if "%WP_DRYRUN%"=="1" (
    call "%WP_LIB%\core.cmd" :PLAN "wsreset.exe"
) else (
    call "%WP_LIB%\core.cmd" :MSG "wsreset открывает окно Microsoft Store и ждёт около 30 секунд"
    call "%WP_LIB%\core.cmd" :CONFIRM "Сбросить кэш Microsoft Store" N
    if errorlevel 1 (
        call "%WP_LIB%\core.cmd" :SKIP "wsreset пропущен пользователем"
    ) else (
        start "" /wait wsreset.exe
        call "%WP_LIB%\core.cmd" :OK "wsreset выполнен"
    )
)
call "%WP_LIB%\core.cmd" :FSUTIL_SET "disable8dot3" "1" "NtfsDisable8dot3NameCreation" "2"
call "%WP_LIB%\core.cmd" :FSUTIL_SET "disablelastaccess" "1" "NtfsDisableLastAccessUpdate" "2"
call "%WP_LIB%\core.cmd" :FSUTIL_SET "memoryusage" "2" "NtfsMemoryUsage" "0"
call "%WP_LIB%\core.cmd" :FSUTIL_SET "disabledeletenotify" "0" "NONE" "0"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_INPUT - 5 операций, новый блок из сверки с OptimizerDuck
rem  Повтор клавиш и отключение залипания спец. возможностей.
rem  Flags - строковые значения, так их хранит Windows.
rem ============================================================
:T_INPUT
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "INPUT" 5
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Control Panel\Keyboard" "KeyboardDelay" REG_SZ "0"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Control Panel\Keyboard" "KeyboardSpeed" REG_SZ "31"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Control Panel\Accessibility\StickyKeys" "Flags" REG_SZ "506"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Control Panel\Accessibility\ToggleKeys" "Flags" REG_SZ "58"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Control Panel\Accessibility\Keyboard Response" "Flags" REG_SZ "126"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_PRIVACY_EXT - 5 операций, новый блок
rem  Геолокация, сенсоры, ConsumerFeatures, фоновые приложения.
rem ============================================================
:T_PRIVACY_EXT
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "PRIVACY_EXT" 5
call "%WP_LIB%\core.cmd" :WARN "геолокация off: перестанут работать карты, погода по месту и поиск устройства"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" "Value" REG_SZ "Deny"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" "DisableLocation" REG_DWORD "1"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" "DisableSensors" REG_DWORD "1"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" REG_DWORD "1"
call "%WP_LIB%\core.cmd" :WARN "GlobalUserDisabled ломает фоновые уведомления мессенджеров"
call "%WP_LIB%\core.cmd" :CONFIRM "Запретить фон сразу для приложений Windows? Для настройки по одному выбери N и пункт Фон приложений" N
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :SKIP "фоновые приложения оставлены включёнными"
) else (
    call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" "GlobalUserDisabled" REG_DWORD "1"
)
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_WEBDAV - 1 операция, новый блок
rem  Снятие лимита 50 МБ для WebDAV. Если службы WebClient нет,
rem  писать значение бессмысленно, блок не начинается.
rem ============================================================
:T_WEBDAV
sc query WebClient >nul 2>&1
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :MSG "Служба WebClient не установлена, лимит WebDAV неактуален"
    exit /b 0
)
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "WEBDAV" 1
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Services\WebClient\Parameters" "FileSizeLimitInBytes" REG_DWORD "4294967295"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_SMB1 - 1 операция. Отключение SMB1 сервера и клиента.
rem  SMB1 - вектор WannaCry, на Win11 обычно уже отсутствует.
rem ============================================================
:T_SMB1
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "SMB1" 1
call "%WP_LIB%\core.cmd" :WARN "SMB1 off: старый NAS или сетевой принтер по SMB1 перестанут отвечать"
call "%WP_LIB%\core.cmd" :AGG_BEGIN
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" "SMB1" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :SC_SET "mrxsmb10" "disabled"
call "%WP_LIB%\core.cmd" :AGG_END "SMB1: сервер и клиент отключены"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_IFEO_ECO - 1 операция. Приоритет фоновых апдейтеров.
rem  Приближение Efficiency Mode через IFEO PerfOptions.
rem  Сам EcoQoS задаётся только через API, реестром его нет.
rem ============================================================
:T_IFEO_ECO
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "IFEO_ECO" 1
call "%WP_LIB%\core.cmd" :MSG "Апдейтеры получают BelowNormal CPU, Low IO, PagePriority 3"
call "%WP_LIB%\core.cmd" :MSG "Это приближение Efficiency Mode, не EcoQoS: он задаётся только API"
call "%WP_LIB%\core.cmd" :AGG_BEGIN
for %%a in (GoogleUpdate.exe AdobeARM.exe armsvc.exe jucheck.exe jusched.exe MozillaMaintenance.exe DropboxUpdate.exe SpotifyWebHelper.exe) do (
    call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\%%a\PerfOptions" "CpuPriorityClass" REG_DWORD "5"
    call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\%%a\PerfOptions" "IoPriority" REG_DWORD "1"
    call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\%%a\PerfOptions" "PagePriority" REG_DWORD "3"
)
call "%WP_LIB%\core.cmd" :AGG_END "IFEO_ECO: приоритеты для 8 апдейтеров"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0
rem ============================================================
rem  T_AUTORUN - 8 операций, по одной на источник автозагрузки.
rem  Whititelist по имени плюс валидная подпись файла.
rem  Реестр через REG_DEL, задачи через TASK_DISABLE, ярлыки LNK_MOVE.
rem ============================================================
:T_AUTORUN
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :MSG "Автозагрузка: только известные апдейтеры и предзагрузка в трей"
call "%WP_LIB%\core.cmd" :MSG "Браузерные апдейтеры, драйверы и ваши инструменты не трогаются"
set /a _ar_o=WP_OP_OK
set /a _ar_f=WP_OP_FAIL
set /a _ar_s=WP_OP_SKIP
set /a _ar_p=WP_OP_PLAN
call "%WP_LIB%\core.cmd" :PS_RUN get-autorun "%WP_RUN%\ar.txt"
call "%WP_LIB%\backup.cmd" :LOAD_KV "%WP_RUN%\ar.txt"
set /a WP_OP_OK=_ar_o
set /a WP_OP_FAIL=_ar_f
set /a WP_OP_SKIP=_ar_s
set /a WP_OP_PLAN=_ar_p
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "AUTORUN" 8

set /a _n=AR_CHKCU_RUN_COUNT
call "%WP_LIB%\core.cmd" :AGG_BEGIN
for /l %%i in (1,1,!_n!) do (
    set "_nm=!AR_CHKCU_RUN_%%i!"
    call "%WP_LIB%\core.cmd" :REG_DEL "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" "!_nm!"
)
call "%WP_LIB%\core.cmd" :AGG_END "AUTORUN HKCU Run"

set /a _n=AR_CHKCU_RUNONCE_COUNT
call "%WP_LIB%\core.cmd" :AGG_BEGIN
for /l %%i in (1,1,!_n!) do (
    set "_nm=!AR_CHKCU_RUNONCE_%%i!"
    call "%WP_LIB%\core.cmd" :REG_DEL "HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce" "!_nm!"
)
call "%WP_LIB%\core.cmd" :AGG_END "AUTORUN HKCU RunOnce"

set /a _n=AR_CHKLM_RUN_COUNT
call "%WP_LIB%\core.cmd" :AGG_BEGIN
for /l %%i in (1,1,!_n!) do (
    set "_nm=!AR_CHKLM_RUN_%%i!"
    call "%WP_LIB%\core.cmd" :REG_DEL "HKLM\Software\Microsoft\Windows\CurrentVersion\Run" "!_nm!"
)
call "%WP_LIB%\core.cmd" :AGG_END "AUTORUN HKLM Run"

set /a _n=AR_CHKLM_RUNONCE_COUNT
call "%WP_LIB%\core.cmd" :AGG_BEGIN
for /l %%i in (1,1,!_n!) do (
    set "_nm=!AR_CHKLM_RUNONCE_%%i!"
    call "%WP_LIB%\core.cmd" :REG_DEL "HKLM\Software\Microsoft\Windows\CurrentVersion\RunOnce" "!_nm!"
)
call "%WP_LIB%\core.cmd" :AGG_END "AUTORUN HKLM RunOnce"

set /a _n=AR_CHKLM_WOW_RUN_COUNT
call "%WP_LIB%\core.cmd" :AGG_BEGIN
for /l %%i in (1,1,!_n!) do (
    set "_nm=!AR_CHKLM_WOW_RUN_%%i!"
    call "%WP_LIB%\core.cmd" :REG_DEL "HKLM\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Run" "!_nm!"
)
call "%WP_LIB%\core.cmd" :AGG_END "AUTORUN Wow64 Run"

set /a _n=AR_CSTARTUP_USER_COUNT
call "%WP_LIB%\core.cmd" :AGG_BEGIN
for /l %%i in (1,1,!_n!) do (
    set "_nm=!AR_CSTARTUP_USER_%%i!"
    call "%WP_LIB%\core.cmd" :LNK_MOVE "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\!_nm!.lnk"
)
call "%WP_LIB%\core.cmd" :AGG_END "AUTORUN Startup пользователя"

set /a _n=AR_CSTARTUP_COMMON_COUNT
call "%WP_LIB%\core.cmd" :AGG_BEGIN
for /l %%i in (1,1,!_n!) do (
    set "_nm=!AR_CSTARTUP_COMMON_%%i!"
    call "%WP_LIB%\core.cmd" :LNK_MOVE "%ProgramData%\Microsoft\Windows\Start Menu\Programs\Startup\!_nm!.lnk"
)
call "%WP_LIB%\core.cmd" :AGG_END "AUTORUN Startup общий"

set /a _n=AR_CTASKS_LOGON_COUNT
call "%WP_LIB%\core.cmd" :AGG_BEGIN
for /l %%i in (1,1,!_n!) do (
    set "_nm=!AR_CTASKS_LOGON_%%i!"
    call "%WP_LIB%\core.cmd" :TASK_DISABLE "!_nm!"
)
call "%WP_LIB%\core.cmd" :AGG_END "AUTORUN задачи с logon-триггером"

call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0
rem ============================================================
rem  T_STORAGE_SAFE - 4 операции. Только регенерируемые кэши.
rem  Temp, шрифты и миниатюры уже чистит T_MAINT, здесь их нет.
rem  Каждая группа свёрнута в одну операцию через AGG.
rem ============================================================
:T_STORAGE_SAFE
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "STORAGE_SAFE" 4
call "%WP_LIB%\core.cmd" :MSG "Кэши регенерируются, пользовательские файлы не затрагиваются"
call "%WP_LIB%\core.cmd" :WARN "После чистки кэша шейдеров возможен микрофриз при первом запуске игр"

call "%WP_LIB%\core.cmd" :AGG_BEGIN
call "%WP_LIB%\core.cmd" :PURGE_FILES "%WINDIR%\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache\*" "S"
call "%WP_LIB%\core.cmd" :PURGE_FILES "%WINDIR%\SoftwareDistribution\DeliveryOptimization\*" "S"
call "%WP_LIB%\core.cmd" :AGG_END "STORAGE Delivery Optimization"

call "%WP_LIB%\core.cmd" :AGG_BEGIN
call "%WP_LIB%\core.cmd" :PURGE_FILES "%ProgramData%\Microsoft\Windows\WER\ReportQueue\*" "S"
call "%WP_LIB%\core.cmd" :PURGE_FILES "%ProgramData%\Microsoft\Windows\WER\ReportArchive\*" "S"
call "%WP_LIB%\core.cmd" :PURGE_FILES "%LOCALAPPDATA%\CrashDumps\*" "S"
call "%WP_LIB%\core.cmd" :AGG_END "STORAGE отчёты WER и дампы"

call "%WP_LIB%\core.cmd" :AGG_BEGIN
call "%WP_LIB%\core.cmd" :PURGE_FILES "%WINDIR%\SoftwareDistribution\Download\*" "S"
call "%WP_LIB%\core.cmd" :AGG_END "STORAGE кэш загрузок обновлений"

call "%WP_LIB%\core.cmd" :AGG_BEGIN
call "%WP_LIB%\core.cmd" :PURGE_FILES "%LOCALAPPDATA%\D3DSCache\*" "S"
call "%WP_LIB%\core.cmd" :PURGE_FILES "%LOCALAPPDATA%\AMD\DxCache\*" "S"
call "%WP_LIB%\core.cmd" :PURGE_FILES "%LOCALAPPDATA%\NVIDIA\DXCache\*" "S"
call "%WP_LIB%\core.cmd" :AGG_END "STORAGE кэш шейдеров DirectX"

call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0
rem ============================================================
rem  T_DO_PEERING - 2 операции. Запрет раздачи обновлений пирам.
rem  Службу DoSvc не трогаем: она нужна для загрузки обновлений.
rem  DODownloadMode=0 - только HTTP с CDN, без peer caching.
rem ============================================================
:T_DO_PEERING
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "DO_PEERING" 2
call "%WP_LIB%\core.cmd" :MSG "Раздача обновлений пирам забивает исходящий канал и таблицу NAT роутера"
if "%WP_DRYRUN%"=="1" (
    call "%WP_LIB%\core.cmd" :PLAN "create key DeliveryOptimization policy"
) else (
    call "%WP_LIB%\core.cmd" :REG_KEY "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" COUNT
    if errorlevel 1 (
        call "%WP_LIB%\core.cmd" :SKIP "зависимое значение: ключ недоступен"
        call "%WP_LIB%\core.cmd" :BLOCK_END
        exit /b 1
    )
)
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0
:: END OF FILE | Всего твиков в файле: 148

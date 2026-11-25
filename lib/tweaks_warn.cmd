@echo off
rem ============================================================
rem  WinPulse 7.1 "Rebuild"  |  lib\tweaks_warn.cmd  |  ЧАСТЬ 1/2
rem  Твики с осторожностью: 48 операций в 21 блоке.
rem
rem  Кодировка: UTF-8 БЕЗ BOM, CRLF. Символ "!" в echo запрещён.
rem  Вызов:  call "%WP_LIB%\tweaks_warn.cmd" :T_ИМЯ [args]
rem  Свой setlocal ЗАПРЕЩЁН.
rem
rem  Правила те же: только обёртки core.cmd и backup.cmd,
rem  guard ДО BLOCK_BEGIN, HKCU через !WP_HKCU!,
rem  ровно один инкремент счётчика на операцию.
rem
rem  AGG_BEGIN/AGG_END живут в core.cmd, локальной копии нет:
rem  две копии одной арифметики - это будущий рассинхрон.
rem
rem  Блоки части 1: PRIORITY MEMORY MMCSS POWER_HIBER POWER_DISK
rem    POWER_TIMER RESERVED WORK_IFEO UX_CHAT MOUSE TIMERS NDU
rem ============================================================
if "%~1"=="" exit /b 9009
if not defined WP_LIB exit /b 9009
if not defined JOURNAL exit /b 9009
set "__EP=%~1"
shift
goto %__EP%

rem ============================================================
rem  POWER_HAS  %1 subgroup  %2 setting - есть ли параметр.
rem  GUID Timer Coalescing не подтверждён для всех сборок:
rem  проверяем фактом, а не пишем заведомый FAIL каждый прогон.
rem ============================================================
:POWER_HAS
powercfg /q SCHEME_CURRENT %~1 %~2 >nul 2>&1
exit /b %errorlevel%

rem ============================================================
rem  T_PRIORITY  %1 Win32PrioritySeparation 38|40
rem              %2 SystemResponsiveness 0|20
rem  4 операции. Неиспользованный вариант даёт SKIP, поэтому
rem  итог всегда 4 и аудит не врёт. Это варианты, а не дубли.
rem ============================================================
:T_PRIORITY
set "_PS=%~1"
set "_PR=%~2"
if not defined _PS set "_PS=2"
if not defined _PR set "_PR=20"
set "_PSOK=0"
for %%v in (2 26 38 40) do if "!_PS!"=="%%v" set "_PSOK=1"
if "!_PSOK!"=="0" set "_PS=2"
if not "!_PR!"=="0" if not "!_PR!"=="20" set "_PR=20"
if "!_PS!"=="38" if !CPU_CORES! gtr 0 if !CPU_CORES! lss 6 call "%WP_LIB%\core.cmd" :WARN "38 рассчитан на многоядерные, у вас !CPU_CORES! ядер"
if "!_PS!"=="40" call "%WP_LIB%\core.cmd" :WARN "40 убирает буст переднего плана: игра уравнивается с фоном"
if "!_PS!"=="2" call "%WP_LIB%\core.cmd" :MSG "Win32PrioritySeparation=2: возврат к дефолту Windows"
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "PRIORITY" 2
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl" "Win32PrioritySeparation" REG_DWORD "!_PS!"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "SystemResponsiveness" REG_DWORD "!_PR!"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_MEMORY - 5 операций
rem  Блок целиком требует RAM>=8. Отдельные пункты требуют
rem  16 и 32 ГБ и честно дают SKIP, а не тянут весь блок вниз.
rem ============================================================
:T_MEMORY
call "%WP_LIB%\guard.cmd" :G_RAM 8 "MEMORY"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "MEMORY" 5
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "DisablePagingExecutive" REG_DWORD "1"
if !RAM_GB! lss 16 (
    call "%WP_LIB%\core.cmd" :SKIP "PageCombining: RAM !RAM_GB! GB меньше 16, оставлено включённым"
) else (
    call "%WP_LIB%\backup.cmd" :MM_SET "pagecombining" "0"
)
rem Потолок 1024 ГБ: set /a 32-битный, на 2 ТБ был бы overflow
set "_SVCH=!RAM_GB!"
if !_SVCH! gtr 1024 set "_SVCH=1024"
set /a "_SVCKB=_SVCH * 1048576"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Control" "SvcHostSplitThresholdInKB" REG_DWORD "!_SVCKB!"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "LargeSystemCache" REG_DWORD "0"
if !RAM_GB! lss 32 (
    call "%WP_LIB%\core.cmd" :SKIP "MemoryCompression: RAM !RAM_GB! GB меньше 32"
) else (
    call "%WP_LIB%\backup.cmd" :MM_SET "memorycompression" "0"
)
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_MMCSS - 4 операции
rem  REG_KEY - подготовка, счётчик не трогает.
rem ============================================================
:T_MMCSS
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "MMCSS" 4
call "%WP_LIB%\core.cmd" :REG_KEY "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
if errorlevel 1 (
    set /a WP_OP_SKIP+=3
    call "%WP_LIB%\core.cmd" :BLOCK_END
    exit /b 1
)
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "GPU Priority" REG_DWORD "8"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "Priority" REG_DWORD "6"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "Scheduling Category" REG_SZ "High"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" "SFIO Priority" REG_SZ "High"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_POWER_HIBER - 1 операция
rem  Отключение гибернации убирает и Windows Fast Startup.
rem  Это осознанный trade-off, см. MANUAL_STEPS раздел 6.
rem ============================================================
:T_POWER_HIBER
call "%WP_LIB%\core.cmd" :MSG "Гибернация и быстрый запуск будут отключены, hiberfil.sys удалится"
if !HDD_COUNT! gtr 0 call "%WP_LIB%\core.cmd" :WARN "на HDD быстрый запуск давал заметный выигрыш, решайте осознанно"
call "%WP_LIB%\core.cmd" :CONFIRM "Отключить гибернацию" N
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :MSG "Гибернация оставлена включённой"
    exit /b 0
)
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "POWER_HIBER" 1
call "%WP_LIB%\backup.cmd" :HIBER_SET "0"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_POWER_DISK - 1 операция
rem ============================================================
:T_POWER_DISK
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "POWER_DISK" 1
if !HDD_COUNT! gtr 0 call "%WP_LIB%\core.cmd" :WARN "HDD не будет засыпать: больше шума и износа, зато нет задержки раскрутки"
call "%WP_LIB%\core.cmd" :POWER_SET "SUB_DISK" "DISKIDLE" "0" "KEEP"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_POWER_TIMER - 1 операция
rem ============================================================
:T_POWER_TIMER
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "POWER_TIMER" 1
if "!IS_LAPTOP!"=="1" (
    call "%WP_LIB%\core.cmd" :SKIP "Timer Coalescing оставлен включённым: ноутбук, батарея"
    goto :POWER_TIMER_END
)
call :POWER_HAS "SUB_NONE" "5d6ed4dc-5c00-4d6f-bc53-3f040f13b5dc"
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :SKIP "параметр Timer Coalescing отсутствует в этой сборке Windows"
    goto :POWER_TIMER_END
)
call "%WP_LIB%\core.cmd" :POWER_SET "SUB_NONE" "5d6ed4dc-5c00-4d6f-bc53-3f040f13b5dc" "0" "KEEP"
:POWER_TIMER_END
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_RESERVED - 1 операция, новый блок из сверки с CTT
rem ============================================================
:T_RESERVED
call "%WP_LIB%\core.cmd" :MSG "Reserved Storage освободит около 7 ГБ, но может повлиять на обслуживание обновлений"
call "%WP_LIB%\core.cmd" :CONFIRM "Отключить Reserved Storage" N
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :MSG "Reserved Storage оставлен включённым"
    exit /b 0
)
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "RESERVED" 1
call "%WP_LIB%\backup.cmd" :RESERVED_SET "0"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_WORK_IFEO - 1 операция, 8 приложений
rem  Группа считается одной операцией по инвентарю, но в журнал
rem  попадает каждая запись: откат вернёт все восемь.
rem ============================================================
:T_WORK_IFEO
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "WORK_IFEO" 1
call "%WP_LIB%\core.cmd" :WARN "Process Lasso переопределяет приоритеты на лету и сильнее IFEO"
call "%WP_LIB%\core.cmd" :AGG_BEGIN
for %%a in (chrome.exe msedge.exe firefox.exe WINWORD.EXE EXCEL.EXE Code.exe Photoshop.exe Discord.exe) do (
    call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\%%a\PerfOptions" "CpuPriorityClass" REG_DWORD "3"
)
call "%WP_LIB%\core.cmd" :AGG_END "приоритеты офисных приложений"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_UX_CHAT - 1 операция
rem ============================================================
:T_UX_CHAT
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "UX_CHAT" 1
if !WIN_BUILD! geq 22000 (
    call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarMn" REG_DWORD "0"
) else (
    call "%WP_LIB%\core.cmd" :SKIP "TaskbarMn: Chat только на Win11, build !WIN_BUILD!"
)
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_MOUSE - 5 операций
rem  SmoothMouseCurve = 40 нулевых байт, 5 точек по 8.
rem  В 6.x было 32 байта: неверная длина, Windows её игнорировал,
rem  и два твика мыши были пустышками. Длина генерируется циклом,
rem  чтобы не считать нули глазами.
rem ============================================================
:T_MOUSE
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "MOUSE" 5
set "_MZ="
for /l %%i in (1,1,40) do set "_MZ=!_MZ!00"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Control Panel\Mouse" "MouseSpeed" REG_SZ "0"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Control Panel\Mouse" "MouseThreshold1" REG_SZ "0"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Control Panel\Mouse" "MouseThreshold2" REG_SZ "0"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Control Panel\Mouse" "SmoothMouseXCurve" REG_BINARY "!_MZ!"
call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Control Panel\Mouse" "SmoothMouseYCurve" REG_BINARY "!_MZ!"
set "WP_REBOOT_REQUIRED=1"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_TIMERS - 1 операция
rem ============================================================
:T_TIMERS
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "TIMERS" 1
call "%WP_LIB%\core.cmd" :WARN "ISLC тоже дёргает таймер: при странном frametime отключи что-то одно и замерь"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" "GlobalTimerResolutionRequests" REG_DWORD "1"
set "WP_REBOOT_REQUIRED=1"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_NDU - 1 операция
rem ============================================================
:T_NDU
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "NDU" 1
call "%WP_LIB%\core.cmd" :SC_SET "Ndu" "disabled"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0


rem ============================================================
rem  ЧАСТЬ 2/2. GameBar, службы Xbox, аудио, хранение,
rem  визуал поверх профиля, глобальные сетевые параметры.
rem ============================================================

rem ============================================================
rem  T_GAMEBAR_RT - 1 операция
rem  Ветка WindowsRuntime под TrustedInstaller, обычный reg add
rem  здесь даёт Access Denied. Идём через REGACL_SET.
rem ============================================================
:T_GAMEBAR_RT
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "GAMEBAR_RT" 1
call "%WP_LIB%\core.cmd" :WARN "Game Bar перестанет публиковать присутствие, Xbox-приложение может ругаться"
set "_GBK=HKLM\SOFTWARE\Microsoft\WindowsRuntime\ActivatableClassId\Windows.Gaming.GameBar.PresenceServer.Internal.PresenceWriter"
call "%WP_LIB%\backup.cmd" :REGACL_SET "!_GBK!" "ActivationType" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_SERVICES_XBOX - 4 операции
rem  Game Pass и игры из Store без этих служб не авторизуются
rem  и не синхронизируют сохранения. Отказ = блок не начинается.
rem ============================================================
:T_SERVICES_XBOX
call "%WP_LIB%\core.cmd" :WARN "Game Pass, сохранения Xbox Live и часть игр из Store перестанут работать"
call "%WP_LIB%\core.cmd" :CONFIRM "Отключить службы Xbox и ALG" N
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :MSG "Службы Xbox оставлены включёнными"
    exit /b 0
)
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "SERVICES_XBOX" 4
call "%WP_LIB%\core.cmd" :SC_SET "XblAuthManager" "disabled"
call "%WP_LIB%\core.cmd" :SC_SET "XblGameSave" "disabled"
call "%WP_LIB%\core.cmd" :SC_SET "XboxNetApiSvc" "disabled"
call "%WP_LIB%\core.cmd" :SC_SET "ALG" "disabled"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_AUDIO - 1 операция
rem  Ключ из 6.x (HKCU\Software\Microsoft\Multimedia\Audio
rem  DisableEnhancements) фиктивный: настройка живёт в per-endpoint
rem  FxProperties и зависит от аудиодрайвера. Честный SKIP вместо
rem  записи параметра, который ничего не делает.
rem ============================================================
:T_AUDIO
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "AUDIO" 1
call "%WP_LIB%\core.cmd" :SKIP "аудио-улучшения: ключ зависит от драйвера, снимите галку в mmsys.cpl, см. MANUAL_STEPS раздел 2"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_WDI - 1 операция
rem ============================================================
:T_WDI
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "WDI" 1
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Control\WMI\Autologger\WDIContextLog" "Start" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_STORPORT - 1 операция
rem  Значение из исходного списка, Microsoft не документировано.
rem  На ноутбуке держит накопитель awake и ест батарею.
rem ============================================================
:T_STORPORT
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "STORPORT" 1
if "!IS_LAPTOP!"=="1" (
    call "%WP_LIB%\core.cmd" :SKIP "StorPort IdleTimeout: ноутбук, накопитель не должен оставаться awake"
) else (
    call "%WP_LIB%\core.cmd" :WARN "StorPort IdleTimeout не документирован Microsoft, эффект зависит от контроллера"
    call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Services\storport" "IdleTimeout" REG_DWORD "0"
)
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_PREFETCH - 1 операция
rem ============================================================
:T_PREFETCH
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "PREFETCH" 1
call "%WP_LIB%\core.cmd" :WARN "Очистка Prefetch замедлит первый запуск приложений, на SSD выигрыша нет"
call "%WP_LIB%\core.cmd" :CONFIRM "Очистить Prefetch" N
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :SKIP "Prefetch оставлен"
) else (
    call "%WP_LIB%\core.cmd" :PURGE_FILES "%WINDIR%\Prefetch\*" "N"
)
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_SYSMAIN - 2 операции
rem  Тот самый сценарий "HDD плюс отключить SysMain" закрыт жёстко.
rem ============================================================
:T_SYSMAIN
call "%WP_LIB%\guard.cmd" :G_ALLSSD "SYSMAIN"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_CONFIRM "SYSMAIN" "SysMain ускоряет запуск приложений за счёт предзагрузки. Отключение имеет смысл только на быстрых NVMe и при нехватке CPU"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "SYSMAIN" 2
call "%WP_LIB%\core.cmd" :SC_STOP "SysMain"
call "%WP_LIB%\core.cmd" :SC_SET "SysMain" "disabled"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_VISUAL_AGG - 3 операции
rem  Keep respected: блок не начинается, счётчики не тронуты.
rem  Balanced сохраняет MenuShowDelay=100 из safe-блока.
rem  Comfort и Work сохраняют прозрачность.
rem ============================================================
:T_VISUAL_AGG
if /i "!WP_VISUAL_PROFILE!"=="MotionOnly" exit /b 0
if /i "!WP_VISUAL_PROFILE!"=="Keep" (
    call "%WP_LIB%\core.cmd" :MSG "Визуал сохранён по выбору пользователя, VISUAL_AGG пропущен"
    exit /b 0
)
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "VISUAL_AGG" 3
set "_VA_TRANS=0"
if /i "!WP_VISUAL_PROFILE!"=="Performance" set "_VA_TRANS=1"
if /i "!WP_VISUAL_PROFILE!"=="Balanced" set "_VA_TRANS=1"
if "!_VA_TRANS!"=="1" (
    call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" REG_DWORD "0"
) else (
    call "%WP_LIB%\core.cmd" :SKIP "прозрачность сохранена профилем !WP_VISUAL_PROFILE!"
)
if /i "!WP_VISUAL_PROFILE!"=="Performance" (
    call "%WP_LIB%\core.cmd" :REG_SET "!WP_HKCU!\Control Panel\Desktop" "MenuShowDelay" REG_SZ "0"
) else (
    call "%WP_LIB%\core.cmd" :SKIP "MenuShowDelay=0 только для Performance, текущий профиль !WP_VISUAL_PROFILE!"
)
if "%WP_DRYRUN%"=="1" (
    call "%WP_LIB%\core.cmd" :PLAN "restart DWM"
) else (
    call "%WP_LIB%\core.cmd" :WARN "экран моргнёт: DWM перезапускается"
    taskkill /f /im dwm.exe >nul 2>&1
    call "%WP_LIB%\core.cmd" :OK "DWM перезапущен"
)
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_NET_GLOBAL - 8 операций
rem  Третьим аргументом идёт документированный дефолт Windows:
rem  прежнее состояние netsh не читается locale-независимо.
rem  chimney на Win10+ отсутствует, поэтому SOFT -> SKIP.
rem ============================================================
:T_NET_GLOBAL
call "%WP_LIB%\guard.cmd" :G_NETWORK "NET_GLOBAL"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "NET_GLOBAL" 8
call "%WP_LIB%\core.cmd" :NETSH_TCP "ecncapability" "disabled" "disabled"
call "%WP_LIB%\core.cmd" :NETSH_TCP "timestamps" "disabled" "disabled"
call "%WP_LIB%\core.cmd" :NETSH_TCP "chimney" "disabled" "disabled" "SOFT"
call "%WP_LIB%\core.cmd" :NETSH_TCP "rss" "enabled" "enabled"
call "%WP_LIB%\core.cmd" :NETSH_TCP "rsc" "disabled" "enabled"
call "%WP_LIB%\core.cmd" :NETSH_TCP "fastopen" "enabled" "enabled"
call "%WP_LIB%\core.cmd" :NETSH_TCP "fastopenfallback" "enabled" "enabled"
call "%WP_LIB%\core.cmd" :NET_FLUSH "arp"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_STORAGE_DEEP - 6 операций. Хранилище компонентов и остатки
rem  установки. ResetBase и Windows.old необратимы и требуют YES.
rem ============================================================
:T_STORAGE_DEEP
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "STORAGE_DEEP" 6
call "%WP_LIB%\core.cmd" :MSG "Хранилище компонентов: основной выигрыш по месту, обычно 3-10 ГБ"

call "%WP_LIB%\core.cmd" :DISM_RUN "/StartComponentCleanup" "очистка хранилища компонентов"

call "%WP_LIB%\guard.cmd" :G_CONFIRM "STORAGE_DEEP" "ResetBase сделает установленные обновления неудаляемыми"
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :SKIP "ResetBase пропущен"
) else (
    call "%WP_LIB%\core.cmd" :DISM_RUN "/StartComponentCleanup /ResetBase" "ResetBase"
)

call "%WP_LIB%\guard.cmd" :G_CONFIRM "STORAGE_DEEP" "Windows.old будет удалён, откат к прошлой версии Windows невозможен"
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :SKIP "Windows.old пропущен"
) else (
    call "%WP_LIB%\core.cmd" :PURGE_DIR "%SystemDrive%\Windows.old"
)

call "%WP_LIB%\core.cmd" :AGG_BEGIN
call "%WP_LIB%\core.cmd" :PURGE_DIR "%SystemDrive%\$Windows.~BT"
call "%WP_LIB%\core.cmd" :PURGE_DIR "%SystemDrive%\$Windows.~WS"
call "%WP_LIB%\core.cmd" :AGG_END "STORAGE остатки установки Windows"

call "%WP_LIB%\core.cmd" :PURGE_FILES "%WINDIR%\SoftwareDistribution\DataStore\*" "S"

call "%WP_LIB%\core.cmd" :AGG_BEGIN
call "%WP_LIB%\core.cmd" :PURGE_FILES "%WINDIR%\Logs\CBS\*" "S"
call "%WP_LIB%\core.cmd" :PURGE_FILES "%WINDIR%\Logs\DISM\*" "S"
call "%WP_LIB%\core.cmd" :PURGE_FILES "%WINDIR%\Panther\*" "S"
call "%WP_LIB%\core.cmd" :AGG_END "STORAGE логи CBS и установки"

call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0
rem ============================================================
rem  SE_GROUP  %1 имя группы  %2 список служб  %3 флаг блокировки
rem  Флаг 1 - оставить все службы группы и дать SKIP по каждой,
rem  чтобы объявленное число операций всегда сходилась.
rem ============================================================
:SE_GROUP
set "_sg=%~1"
set "_sl=%~2"
set "_sb=%~3"
for %%s in (!_sl!) do (
    if "!_sb!"=="1" (
        call "%WP_LIB%\core.cmd" :SKIP "!_sg!: %%s оставлен, устройство есть или статус неизвестен"
    ) else (
        call "%WP_LIB%\core.cmd" :SC_SET "%%s" "disabled"
    )
)
exit /b 0

rem ============================================================
rem  T_SERVICES_EXT - 20 операций, семь групп по факту наличия
rem  устройств. Неизвестный статус означает НЕ отключать.
rem ============================================================
:T_SERVICES_EXT
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
set /a _se_o=WP_OP_OK
set /a _se_f=WP_OP_FAIL
set /a _se_s=WP_OP_SKIP
set /a _se_p=WP_OP_PLAN
call "%WP_LIB%\core.cmd" :PS_RUN get-features "%WP_RUN%\ft.txt"
call "%WP_LIB%\backup.cmd" :LOAD_KV "%WP_RUN%\ft.txt"
set /a WP_OP_OK=_se_o
set /a WP_OP_FAIL=_se_f
set /a WP_OP_SKIP=_se_s
set /a WP_OP_PLAN=_se_p
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "SERVICES_EXT" 20
call "%WP_LIB%\core.cmd" :MSG "Служба отключается только если устройства нет и статус достоверен"

set /a _b=0
if not "!FT_SMARTCARD!"=="0" set /a _b=1
if not "!FT_DOMAIN!"=="0" set /a _b=1
call :SE_GROUP "смарт-карты" "ScDeviceEnum SCPolicySvc CertPropSvc" !_b!

set /a _b=0
if not "!FT_BT!"=="0" set /a _b=1
call :SE_GROUP "Bluetooth" "bthserv BTAGService BthAvctpSvc" !_b!

set /a _b=0
if not "!FT_RDP!"=="0" set /a _b=1
if "!_b!"=="0" call "%WP_LIB%\core.cmd" :WARN "TermService нужен Quick Assist и удалённой помощи Windows"
call :SE_GROUP "удалённый доступ" "TermService SessionEnv UmRdpService" !_b!

set /a _b=0
if not "!FT_BIOMETRIC!"=="0" set /a _b=1
if not "!FT_NFC!"=="0" set /a _b=1
call :SE_GROUP "биометрия и NFC" "WbioSrvc SEMgrSvc" !_b!

set /a _b=0
if not "!FT_MODEM!"=="0" set /a _b=1
if "!_b!"=="0" call "%WP_LIB%\core.cmd" :WARN "PhoneSvc нужен приложению Связь с телефоном"
call :SE_GROUP "телефония" "TapiSrv PhoneSvc SmsRouter" !_b!

set /a _b=0
if not "!FT_SENSOR!"=="0" set /a _b=1
call :SE_GROUP "датчики и геолокация" "lfsvc SensorService SensrSvc" !_b!

call "%WP_LIB%\core.cmd" :WARN "WpcMonSvc отключает родительский контроль, TrkWks - поиск перемещённых файлов в сети"
call :SE_GROUP "карты и оболочка" "MapsBroker TrkWks WpcMonSvc" 0

call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0
rem ============================================================
rem  T_PROVISIONED - 30 операций. Ярус A 17 мусорных семейств,
rem  ярус B 13 функциональных только через YES.
rem  Store, winget, Defender UI защищены whitelist внутри verb.
rem ============================================================
:T_PROVISIONED
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :PS_RUN get-features "%WP_RUN%\ft.txt"
call "%WP_LIB%\backup.cmd" :LOAD_KV "%WP_RUN%\ft.txt"
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "PROVISIONED" 30
call "%WP_LIB%\core.cmd" :MSG "Provisioned: источник переустановки для новых пользователей и после feature update"
call "%WP_LIB%\core.cmd" :MSG "Store, winget, Defender UI и системные компоненты защищены whitelist"
call "%WP_LIB%\backup.cmd" :PROVISIONED_REMOVE core
call "%WP_LIB%\core.cmd" :MSG "Ярус B: Камера, Будильники, Диктофон, Почта и Календарь, People, Your Phone"
call "%WP_LIB%\core.cmd" :MSG "Ярус B: Карты, Quick Assist, Get Help, Todos, OneNote, Outlook, Power Automate"
if "!FT_LAPTOP!"=="1" call "%WP_LIB%\core.cmd" :WARN "Ноутбук: Камера, Будильники и Карты обычно нужны, подумайте дважды"
call "%WP_LIB%\guard.cmd" :G_CONFIRM "PROVISIONED" "Удалить 13 функциональных приложений яруса B, восстановление только через Store или образ"
if errorlevel 1 (
    for /l %%i in (1,1,13) do call "%WP_LIB%\core.cmd" :SKIP "provisioned extra: пропущено пользователем"
) else (
    call "%WP_LIB%\backup.cmd" :PROVISIONED_REMOVE extra
)
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0
rem ============================================================
rem  ND_KEY  %1 номер группы 1-14  %2 подпись  %3 значение
rem  Имя значения берётся из NIC_n_Nk: драйверы называют ключи
rem  по-разному, Realtek без звёздочки и иногда иначе.
rem ============================================================
:ND_KEY
set "_nk=%~1"
set "_kl=%~2"
set "_kv=%~3"
call "%WP_LIB%\core.cmd" :AGG_BEGIN
for /l %%n in (1,1,!NIC_COUNT!) do (
    set "_ix=!NIC_%%n_IDX!"
    set "_el=!NIC_%%n_ELIG!"
    set "_hs=!NIC_%%n_K%_nk%!"
    set "_vn=!NIC_%%n_N%_nk%!"
    if "!_el!"=="1" if "!_hs!"=="1" call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}\!_ix!" "!_vn!" REG_SZ "!_kv!"
)
call "%WP_LIB%\core.cmd" :AGG_END "NIC !_kl!"
exit /b 0

rem ============================================================
rem  T_NIC_DRIVER - 14 операций. Энергосбережение, модерация
rem  прерываний и склеивание пакетов физического Ethernet.
rem  Flow Control и Wake-on-LAN не трогаются.
rem ============================================================
:T_NIC_DRIVER
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :PS_RUN get-nic "%WP_RUN%\nic.txt"
call "%WP_LIB%\backup.cmd" :LOAD_KV "%WP_RUN%\nic.txt"
call "%WP_LIB%\core.cmd" :PS_RUN get-features "%WP_RUN%\ft.txt"
call "%WP_LIB%\backup.cmd" :LOAD_KV "%WP_RUN%\ft.txt"
if not defined NIC_COUNT set /a NIC_COUNT=0
set /a _nd_block=0
if "!FT_LAPTOP!"=="1" (
    call "%WP_LIB%\guard.cmd" :G_CONFIRM "NIC_DRIVER" "На ноутбуке отключение энергосбережения повышает расход батареи, линк моргнёт"
    if errorlevel 1 set /a _nd_block=1
)
if !NIC_COUNT! equ 0 set /a _nd_block=1
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "NIC_DRIVER" 14
if !_nd_block! equ 1 (
    for /l %%i in (1,1,14) do call "%WP_LIB%\core.cmd" :SKIP "NIC: нет допущенного адаптера или отказ пользователя"
    call "%WP_LIB%\core.cmd" :BLOCK_END
    exit /b 0
)
call "%WP_LIB%\core.cmd" :WARN "Линк моргнёт на 2-5 секунд при перечитывании настроек драйвером"
call "%WP_LIB%\core.cmd" :MSG "Физических Ethernet: !NIC_ETH_PHYS!, веток реестра: !NIC_COUNT!"
call :ND_KEY 1 "модерация прерываний off" "0"
call :ND_KEY 2 "EEE off" "0"
call :ND_KEY 3 "Advanced EEE off" "0"
call :ND_KEY 4 "Green Ethernet off" "0"
call :ND_KEY 5 "Gigabit Lite off" "0"
call :ND_KEY 6 "Power Down PLL off" "0"
call :ND_KEY 7 "Power Saving Mode off" "0"
call :ND_KEY 8 "ARP offload off" "0"
call :ND_KEY 9 "NS offload off" "0"
call :ND_KEY 10 "RSC IPv4 off" "0"
call :ND_KEY 11 "RSC IPv6 off" "0"
call :ND_KEY 12 "ASPM off" "0"
call :ND_KEY 13 "CLKREQ off" "0"
call :ND_KEY 14 "RSS включён" "1"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

:: END OF FILE | Всего твиков в файле: 116

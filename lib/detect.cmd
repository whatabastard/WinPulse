@echo off
rem ============================================================
rem  WinPulse 7.1 "Rebuild"  |  lib\detect.cmd
rem  Детект ОС и железа тремя независимыми каналами.
rem
rem  Кодировка: UTF-8 БЕЗ BOM, CRLF. Символ "!" в echo запрещён.
rem  Вызов:  call "%WP_LIB%\detect.cmd" :DETECT_ALL
rem  Свой setlocal ЗАПРЕЩЁН.
rem
rem  Канал 1  get-detect      WMI/CIM + реестр
rem  Канал 2  get-detect-api  kernel32 P/Invoke + реестр, без WMI
rem  Канал 3  DETECT_FALLBACK только реестр и env, без PowerShell
rem
rem  Слияние НЕ перезаписывает валидный факт худшим каналом.
rem  Каждый факт несёт *_SOURCE: wmi api registry smbios none
rem  DETECT_TIER: full partial api registry
rem
rem  FAIL-CLOSED: неизвестный факт ЗАКРЫВАЕТ зависимый твик.
rem  В 6.4 упавший Get-PhysicalDisk давал ALL_SSD=1 и дефраг
rem  отключался на HDD. Здесь наоборот.
rem
rem  ПРАВИЛО: внутри pipe и FOR /F только %VAR%, не !VAR!.
rem ============================================================
if "%~1"=="" exit /b 9009
if not defined WP_LIB exit /b 9009
if not defined JOURNAL exit /b 9009
set "__EP=%~1"
shift
goto %__EP%

rem ============================================================
rem  DETECT_ALL - оркестрация каналов
rem ============================================================
:DETECT_ALL
call "%WP_LIB%\core.cmd" :HEAD "Сбор данных о системе"
if not exist "%WP_RUN%" mkdir "%WP_RUN%" >nul 2>&1
call :DETECT_TIER1
call :DETECT_AUDIT
if "!DETECT_CRITICAL_OK!"=="1" goto :DETECT_FINAL
call :DETECT_TIER2
call :DETECT_MERGE
call :DETECT_AUDIT
if "!DETECT_CRITICAL_OK!"=="1" goto :DETECT_FINAL
call :DETECT_TIER3
call :DETECT_AUDIT
:DETECT_FINAL
call :DETECT_DEFAULTS
call :DETECT_SANITIZE
call :DETECT_OS_FIX
call :DETECT_ENV
call :DETECT_CLASSIFY
call :DETECT_HKCU
call :DETECT_TIER_LABEL
call :DETECT_SOURCES_FIX
call :DETECT_SYSINFO
call "%WP_LIB%\core.cmd" :MSG "Детект завершён: !WIN_VER! [tier=!DETECT_TIER!]"
exit /b 0

rem ============================================================
rem  DETECT_LOAD / LOAD_KV_PFX - чтение KEY=VALUE без дочернего cmd
rem ============================================================
:DETECT_LOAD
if not exist "%WP_RUN%\detect.txt" exit /b 1
for /f "usebackq tokens=1,* delims==" %%a in ("%WP_RUN%\detect.txt") do (
    if not "%%a"=="" set "%%a=%%b"
)
exit /b 0

:LOAD_KV_PFX
if not exist "%~1" exit /b 1
for /f "usebackq tokens=1,* delims==" %%a in ("%~1") do (
    if not "%%a"=="" set "%~2%%a=%%b"
)
exit /b 0

rem ============================================================
rem  DETECT_TIER1 - канал WMI
rem ============================================================
:DETECT_TIER1
set "DETECT_MODE=full"
set "DETECT_T1_RC=99"
set "DETECT_T2_RC=99"
set "DETECT_T2_USED=0"
if not exist "%WP_LIB%\wp.ps1" (
    call "%WP_LIB%\core.cmd" :WARN "lib\wp.ps1 отсутствует, канал WMI пропущен"
    exit /b 1
)
if exist "%WP_RUN%\detect.txt" del /f /q "%WP_RUN%\detect.txt" >nul 2>&1
call "%WP_LIB%\core.cmd" :PS_RUN get-detect "%WP_RUN%\detect.txt"
set "DETECT_T1_RC=!errorlevel!"
if not exist "%WP_RUN%\detect.txt" (
    call "%WP_LIB%\core.cmd" :WARN "канал WMI не отдал данные"
    exit /b 1
)
call :DETECT_LOAD
call :DETECT_SOURCES_WMI
if "!DETECT_T1_RC!"=="2" call "%WP_LIB%\core.cmd" :WARN "часть WMI-запросов недоступна"
exit /b 0

:DETECT_SOURCES_WMI
set "OS_SOURCE=registry"
set "RAM_SOURCE=wmi"
set "CPU_SOURCE=wmi"
set "CPU_TOPO_SOURCE=wmi"
set "DISK_SOURCE=wmi"
set "BOOT_DISK_SOURCE=wmi"
set "GPU_SOURCE=wmi"
set "POWER_SOURCE=wmi"
set "CHASSIS_SOURCE=wmi"
set "FREE_SPACE_SOURCE=wmi"
exit /b 0

rem ============================================================
rem  DNUM - защита от мусора вместо числа. %1 имя %2 дефолт
rem ============================================================
:DNUM
set "_DV=!%~1!"
echo %_DV%| findstr /r "^[0-9][0-9]*$" >nul 2>&1
if errorlevel 1 set "%~1=%~2"
exit /b 0

:DETECT_MISS
set "DETECT_CRITICAL_OK=0"
set "DETECT_MISSING=!DETECT_MISSING! %~1"
exit /b 0

rem ============================================================
rem  DETECT_AUDIT - чего не хватает для guard'ов.
rem  Идёт ДО DETECT_DEFAULTS, поэтому DNUM здесь обязателен.
rem ============================================================
:DETECT_AUDIT
set "DETECT_MISSING="
set "DETECT_CRITICAL_OK=1"
call :DNUM RAM_GB 0
call :DNUM RAM_MB 0
call :DNUM CPU_CORES 0
call :DNUM CPU_THREADS 0
call :DNUM CPU_SERIES 0
call :DNUM CPU_HYBRID 0
call :DNUM DISK_COUNT 0
call :DNUM HDD_COUNT 0
call :DNUM ALL_SSD 0
call :DNUM WIN_BUILD 0
call :DNUM WIN_UBR 0
call :DNUM FREE_SPACE_GB 0
call :DNUM FREE_SPACE_KNOWN 0
if not defined BOOT_DISK_TYPE set "BOOT_DISK_TYPE=Unknown"
if !RAM_GB! leq 0 call :DETECT_MISS "RAM"
if !CPU_THREADS! leq 0 call :DETECT_MISS "CPU"
if !DISK_COUNT! leq 0 call :DETECT_MISS "DISKCOUNT"
if !WIN_BUILD! leq 0 call :DETECT_MISS "OSBUILD"
if not "!FREE_SPACE_KNOWN!"=="1" call :DETECT_MISS "FREESPACE"
if /i "!BOOT_DISK_TYPE!"=="SSD" goto :AUDIT_DISK_OK
if /i "!BOOT_DISK_TYPE!"=="HDD" goto :AUDIT_DISK_OK
call :DETECT_MISS "BOOTDISK"
:AUDIT_DISK_OK
exit /b 0

rem ============================================================
rem  DETECT_TIER2 - канал Win32 API, грузим в P2_
rem ============================================================
:DETECT_TIER2
if not exist "%WP_LIB%\wp.ps1" exit /b 1
call "%WP_LIB%\core.cmd" :MSG "Не хватает:!DETECT_MISSING! - опрашиваю Win32 API напрямую"
if exist "%WP_RUN%\detect_api.txt" del /f /q "%WP_RUN%\detect_api.txt" >nul 2>&1
call "%WP_LIB%\core.cmd" :PS_RUN get-detect-api "%WP_RUN%\detect_api.txt"
set "DETECT_T2_RC=!errorlevel!"
if not exist "%WP_RUN%\detect_api.txt" (
    call "%WP_LIB%\core.cmd" :WARN "API-канал не отдал данные"
    exit /b 1
)
call :LOAD_KV_PFX "%WP_RUN%\detect_api.txt" "P2_"
set "DETECT_T2_USED=1"
exit /b 0

rem ============================================================
rem  DETECT_MERGE - берём из API только то, чего нет в WMI
rem ============================================================
:DETECT_MERGE
if !RAM_GB! gtr 0 goto :MERGE_CPU
if not defined P2_RAM_GB goto :MERGE_CPU
if "!P2_RAM_GB!"=="0" goto :MERGE_CPU
set "RAM_GB=!P2_RAM_GB!"
set "RAM_MB=!P2_RAM_MB!"
set "RAM_SOURCE=api"
call "%WP_LIB%\core.cmd" :OK "RAM через GlobalMemoryStatusEx: !RAM_GB! GB"

:MERGE_CPU
if !CPU_THREADS! gtr 0 goto :MERGE_CPU_HYBRID
if not defined P2_CPU_THREADS goto :MERGE_CPU_HYBRID
if "!P2_CPU_THREADS!"=="0" goto :MERGE_CPU_HYBRID
set "CPU_THREADS=!P2_CPU_THREADS!"
set "CPU_CORES=!P2_CPU_CORES!"
if defined P2_CPU_NAME set "CPU_NAME=!P2_CPU_NAME!"
if defined P2_CPU_VENDOR set "CPU_VENDOR=!P2_CPU_VENDOR!"
if defined P2_CPU_SERIES set "CPU_SERIES=!P2_CPU_SERIES!"
if defined P2_CPU_GENERATION set "CPU_GENERATION=!P2_CPU_GENERATION!"
set "CPU_SOURCE=registry+api"
if defined P2_CPU_TOPO_SOURCE set "CPU_TOPO_SOURCE=!P2_CPU_TOPO_SOURCE!"
call "%WP_LIB%\core.cmd" :OK "Топология CPU через GetLogicalProcessorInformation"

:MERGE_CPU_HYBRID
rem Смешанные SMT и non-SMT ядра точнее эвристики по имени
if not "!P2_CPU_TOPO_SOURCE!"=="api" goto :MERGE_BOOTDISK
if not defined P2_CPU_HYBRID goto :MERGE_BOOTDISK
set "CPU_HYBRID=!P2_CPU_HYBRID!"
set "CPU_TOPO_SOURCE=api"

:MERGE_BOOTDISK
if /i "!BOOT_DISK_TYPE!"=="SSD" goto :MERGE_DISKCOUNT
if /i "!BOOT_DISK_TYPE!"=="HDD" goto :MERGE_DISKCOUNT
if not defined P2_BOOT_DISK_TYPE goto :MERGE_DISKCOUNT
if /i "!P2_BOOT_DISK_TYPE!"=="Unknown" goto :MERGE_DISKCOUNT
set "BOOT_DISK_TYPE=!P2_BOOT_DISK_TYPE!"
set "BOOT_DISK_NAME=!P2_BOOT_DISK_NAME!"
set "BOOT_DISK_BUS=!P2_BOOT_DISK_BUS!"
set "BOOT_DISK_SOURCE=api"
call "%WP_LIB%\core.cmd" :OK "Тип загрузочного диска через seek penalty: !BOOT_DISK_TYPE!"

:MERGE_DISKCOUNT
if !DISK_COUNT! gtr 0 goto :MERGE_FREE
if not defined P2_DISK_COUNT goto :MERGE_FREE
if "!P2_DISK_COUNT!"=="0" goto :MERGE_FREE
set "DISK_COUNT=!P2_DISK_COUNT!"
set "HDD_COUNT=!P2_HDD_COUNT!"
set "DISK_UNKNOWN=!P2_DISK_UNKNOWN!"
set "ALL_SSD=!P2_ALL_SSD!"
set "ALL_DISKS=!P2_ALL_DISKS!"
set "DISK_SOURCE=api"

:MERGE_FREE
if "!FREE_SPACE_KNOWN!"=="1" goto :MERGE_GPUHWID
if not "!P2_FREE_SPACE_KNOWN!"=="1" goto :MERGE_GPUHWID
set "FREE_SPACE_GB=!P2_FREE_SPACE_GB!"
set "FREE_SPACE_KNOWN=1"
set "FREE_SPACE_SOURCE=api"

:MERGE_GPUHWID
if defined GPU_HWID goto :MERGE_GPUVENDOR
if not defined P2_GPU_HWID goto :MERGE_GPUVENDOR
set "GPU_HWID=!P2_GPU_HWID!"
set "GPU_INSTANCE=!P2_GPU_INSTANCE!"
set "GPU_CLASSKEY=!P2_GPU_CLASSKEY!"
call "%WP_LIB%\core.cmd" :OK "Instance path GPU найден в реестре Enum\PCI"

:MERGE_GPUVENDOR
if defined GPU_VENDOR if not "!GPU_VENDOR!"=="Unknown" goto :MERGE_GPUNAME
if not defined P2_GPU_VENDOR goto :MERGE_GPUNAME
set "GPU_VENDOR=!P2_GPU_VENDOR!"

:MERGE_GPUNAME
if defined GPU_NAME if not "!GPU_NAME!"=="Unknown GPU" goto :MERGE_PLATFORM
if not defined P2_GPU_NAME goto :MERGE_PLATFORM
set "GPU_NAME=!P2_GPU_NAME!"
set "GPU_DRIVER=!P2_GPU_DRIVER!"
set "GPU_DRIVER_DATE=!P2_GPU_DRIVER_DATE!"
set "GPU_COUNT=!P2_GPU_COUNT!"
set "GPU_SOURCE=registry"

:MERGE_PLATFORM
rem CHASSIS не определён = шаг platform в канале 1 упал целиком
if defined CHASSIS goto :MERGE_OS
if defined P2_CHASSIS (
    set "CHASSIS=!P2_CHASSIS!"
    set "CHASSIS_SOURCE=smbios"
)
if defined P2_IS_LAPTOP set "IS_LAPTOP=!P2_IS_LAPTOP!"
if not defined P2_AC_STATUS goto :MERGE_OS
rem AC_STATUS 255 = питание неизвестно, не принимаем за "от сети"
if "!P2_AC_STATUS!"=="255" goto :MERGE_OS
if defined P2_ON_BATTERY set "ON_BATTERY=!P2_ON_BATTERY!"
set "POWER_SOURCE=api"

:MERGE_OS
if !WIN_BUILD! gtr 0 goto :MERGE_BOOTMODE
if not defined P2_WIN_BUILD goto :MERGE_BOOTMODE
if "!P2_WIN_BUILD!"=="0" goto :MERGE_BOOTMODE
set "WIN_BUILD=!P2_WIN_BUILD!"
set "WIN_UBR=!P2_WIN_UBR!"
set "WIN_PRODUCT=!P2_WIN_PRODUCT!"
set "WIN_DISPLAY=!P2_WIN_DISPLAY!"
set "WIN_FAMILY=!P2_WIN_FAMILY!"
set "WIN_SUPPORTED=!P2_WIN_SUPPORTED!"
set "OS_SOURCE=registry"

:MERGE_BOOTMODE
if defined BOOT_MODE if not "!BOOT_MODE!"=="Unknown" goto :MERGE_DONE
if not defined P2_BOOT_MODE goto :MERGE_DONE
set "BOOT_MODE=!P2_BOOT_MODE!"
if defined P2_SECURE_BOOT set "SECURE_BOOT=!P2_SECURE_BOOT!"
:MERGE_DONE
exit /b 0

rem ============================================================
rem  DETECT_TIER3 - только реестр и env
rem ============================================================
:DETECT_TIER3
call "%WP_LIB%\core.cmd" :WARN "Оба PS-канала недоступны, работаю только на реестре"
call :DETECT_FALLBACK
call :DETECT_T3_CPU
call :DETECT_T3_GPU
exit /b 0

:DETECT_FALLBACK
set "DETECT_MODE=fallback"
call :DQ "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" "ProductName" WIN_PRODUCT
call :DQ "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" "CurrentBuild" WIN_BUILD
call :DQ "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" "DisplayVersion" WIN_DISPLAY
call :DQ "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" "UBR" WIN_UBR
call :DQ "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion" "EditionID" WIN_EDITION
call :DQ "HKLM\HARDWARE\DESCRIPTION\System\CentralProcessor\0" "ProcessorNameString" CPU_NAME
call :DQ "HKLM\HARDWARE\DESCRIPTION\System\CentralProcessor\0" "VendorIdentifier" _CVENDOR
set "CPU_THREADS=%NUMBER_OF_PROCESSORS%"
set "CPU_VENDOR=Unknown"
if defined CPU_NAME (
    echo %CPU_NAME%| findstr /i /c:"Intel" >nul 2>&1
    if not errorlevel 1 set "CPU_VENDOR=Intel"
)
if defined CPU_NAME (
    echo %CPU_NAME%| findstr /i /c:"AMD" >nul 2>&1
    if not errorlevel 1 set "CPU_VENDOR=AMD"
)
if defined _CVENDOR (
    echo %_CVENDOR%| findstr /i /c:"GenuineIntel" >nul 2>&1
    if not errorlevel 1 set "CPU_VENDOR=Intel"
    echo %_CVENDOR%| findstr /i /c:"AuthenticAMD" >nul 2>&1
    if not errorlevel 1 set "CPU_VENDOR=AMD"
)
set "OS_SOURCE=registry"
set "CPU_SOURCE=registry"
set "FREE_SPACE_KNOWN=0"
set "FREE_SPACE_GB=0"
set "RAM_GB=0"
set "RAM_VALID=0"
set "DISK_COUNT=0"
set "ALL_SSD=0"
set "BOOT_DISK_TYPE=Unknown"
call "%WP_LIB%\core.cmd" :WARN "RAM, диски и место не определены, зависимые твики будут закрыты"
exit /b 0

:DETECT_T3_CPU
set "_T3N=0"
for /f "tokens=* delims=" %%L in ('reg query "HKLM\HARDWARE\DESCRIPTION\System\CentralProcessor" 2^>nul ^| findstr /i /c:"CentralProcessor\"') do set /a _T3N+=1
if !_T3N! gtr 0 (
    set "CPU_THREADS=!_T3N!"
    set "CPU_TOPO_SOURCE=registry"
)
exit /b 0

:DETECT_T3_GPU
set "_T3K=HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
set "_T3FOUND="
for /l %%i in (0,1,9) do (
    if not defined _T3FOUND (
        set "_T3DESC="
        set "_T3PROV="
        call :DQ "%_T3K%\000%%i" "DriverDesc" _T3DESC
        if defined _T3DESC (
            set "GPU_NAME=!_T3DESC!"
            set "_T3FOUND=1"
            set "GPU_SOURCE=registry"
            call :DQ "%_T3K%\000%%i" "DriverVersion" GPU_DRIVER
            call :DQ "%_T3K%\000%%i" "ProviderName" _T3PROV
            if defined _T3PROV (
                if not "!_T3PROV:NVIDIA=!"=="!_T3PROV!" set "GPU_VENDOR=NVIDIA"
                if not "!_T3PROV:AMD=!"=="!_T3PROV!" set "GPU_VENDOR=AMD"
                if not "!_T3PROV:ATI=!"=="!_T3PROV!" set "GPU_VENDOR=AMD"
                if not "!_T3PROV:Intel=!"=="!_T3PROV!" set "GPU_VENDOR=Intel"
            )
        )
    )
)
exit /b 0

rem ============================================================
rem  DETECT_DEFAULTS - ни одна переменная не останется пустой
rem ============================================================
:DETECT_DEFAULTS
if not defined WIN_PRODUCT      set "WIN_PRODUCT=Windows"
if not defined WIN_FAMILY       set "WIN_FAMILY=Windows"
if not defined WIN_EDITION      set "WIN_EDITION=Unknown"
if not defined WIN_DISPLAY      set "WIN_DISPLAY=N/A"
if not defined WIN_BUILD        set "WIN_BUILD=0"
if not defined WIN_UBR          set "WIN_UBR=0"
if not defined WIN_SUPPORTED    set "WIN_SUPPORTED=0"
if not defined LAST_UPDATE      set "LAST_UPDATE=Unknown"
if not defined CPU_NAME         set "CPU_NAME=Unknown CPU"
if not defined CPU_VENDOR       set "CPU_VENDOR=Unknown"
if not defined CPU_CORES        set "CPU_CORES=0"
if not defined CPU_THREADS      set "CPU_THREADS=0"
if not defined CPU_SERIES       set "CPU_SERIES=0"
if not defined CPU_GENERATION   set "CPU_GENERATION=unknown"
if not defined CPU_HYBRID       set "CPU_HYBRID=0"
if not defined GPU_NAME         set "GPU_NAME=Unknown GPU"
if not defined GPU_VENDOR       set "GPU_VENDOR=Unknown"
if not defined GPU_DRIVER       set "GPU_DRIVER=Unknown"
if not defined GPU_DRIVER_DATE  set "GPU_DRIVER_DATE=Unknown"
if not defined GPU_COUNT        set "GPU_COUNT=0"
if not defined RAM_GB           set "RAM_GB=0"
if not defined RAM_MB           set "RAM_MB=0"
if not defined RAM_SPEED        set "RAM_SPEED=0"
if not defined RAM_SLOTS        set "RAM_SLOTS=0"
if not defined BOOT_DISK_TYPE   set "BOOT_DISK_TYPE=Unknown"
if not defined BOOT_DISK_NAME   set "BOOT_DISK_NAME=Unknown"
if not defined BOOT_DISK_BUS    set "BOOT_DISK_BUS=Unknown"
if not defined ALL_SSD          set "ALL_SSD=0"
if not defined HDD_COUNT        set "HDD_COUNT=0"
if not defined DISK_COUNT       set "DISK_COUNT=0"
if not defined DISK_UNKNOWN     set "DISK_UNKNOWN=0"
if not defined ALL_DISKS        set "ALL_DISKS=none"
if not defined FREE_SPACE_GB    set "FREE_SPACE_GB=0"
if not defined FREE_SPACE_KNOWN set "FREE_SPACE_KNOWN=0"
if not defined SYS_DRIVE        set "SYS_DRIVE=C:"
if not defined BOOT_MODE        set "BOOT_MODE=Unknown"
if not defined SECURE_BOOT      set "SECURE_BOOT=Unknown"
if not defined BITLOCKER_STATUS set "BITLOCKER_STATUS=Unknown"
if not defined VBS_STATUS       set "VBS_STATUS=Unknown"
if not defined HVCI_STATUS      set "HVCI_STATUS=Unknown"
if not defined DEFENDER_RT      set "DEFENDER_RT=Unknown"
if not defined DEFENDER_TAMPER  set "DEFENDER_TAMPER=Unknown"
if not defined AV_THIRD         set "AV_THIRD=none"
if not defined RESTORE_COUNT    set "RESTORE_COUNT=0"
if not defined RESTORE_ENABLED  set "RESTORE_ENABLED=0"
if not defined IS_LAPTOP        set "IS_LAPTOP=0"
if not defined ON_BATTERY       set "ON_BATTERY=0"
if not defined CHASSIS          set "CHASSIS=Desktop"
if not defined CONSOLE_USER     set "CONSOLE_USER=Unknown"
call :DNUM WIN_BUILD 0
call :DNUM WIN_UBR 0
call :DNUM CPU_CORES 0
call :DNUM CPU_THREADS 0
call :DNUM CPU_SERIES 0
call :DNUM CPU_HYBRID 0
call :DNUM GPU_COUNT 0
call :DNUM RAM_GB 0
call :DNUM RAM_MB 0
call :DNUM RAM_SPEED 0
call :DNUM RAM_SLOTS 0
call :DNUM HDD_COUNT 0
call :DNUM DISK_COUNT 0
call :DNUM DISK_UNKNOWN 0
call :DNUM ALL_SSD 0
call :DNUM RESTORE_COUNT 0
call :DNUM RESTORE_ENABLED 0
call :DNUM IS_LAPTOP 0
call :DNUM ON_BATTERY 0
if "!FREE_SPACE_GB!"=="-1" (
    set "FREE_SPACE_KNOWN=0"
    set "FREE_SPACE_GB=0"
) else (
    call :DNUM FREE_SPACE_GB 0
)
set "RAM_VALID=0"
if !RAM_GB! gtr 0 set "RAM_VALID=1"
exit /b 0

rem ============================================================
rem  DETECT_SANITIZE - скобки и операторы в именах устройств.
rem  Символы ! ^ %% вырезает wp.ps1, здесь их не трогаем:
rem  удалить ! через delayed expansion невозможно.
rem ============================================================
:DETECT_SANITIZE
set "CPU_NAME=!CPU_NAME:(=!"
set "CPU_NAME=!CPU_NAME:)=!"
set "CPU_NAME=!CPU_NAME:&=!"
set "CPU_NAME=!CPU_NAME:|=!"
set "CPU_NAME=!CPU_NAME:<=!"
set "CPU_NAME=!CPU_NAME:>=!"
set "GPU_NAME=!GPU_NAME:(=!"
set "GPU_NAME=!GPU_NAME:)=!"
set "GPU_NAME=!GPU_NAME:&=!"
set "GPU_NAME=!GPU_NAME:|=!"
set "GPU_NAME=!GPU_NAME:<=!"
set "GPU_NAME=!GPU_NAME:>=!"
for /f "tokens=* delims= " %%a in ("!CPU_NAME!") do set "CPU_NAME=%%a"
for /f "tokens=* delims= " %%a in ("!GPU_NAME!") do set "GPU_NAME=%%a"
if not defined CPU_NAME set "CPU_NAME=Unknown CPU"
if not defined GPU_NAME set "GPU_NAME=Unknown GPU"
exit /b 0

rem ============================================================
rem  DETECT_OS_FIX - ProductName врёт на Win11, верим только build
rem ============================================================
:DETECT_OS_FIX
if !WIN_BUILD! geq 22000 set "WIN_FAMILY=Windows 11"
if !WIN_BUILD! lss 22000 if !WIN_BUILD! geq 10240 set "WIN_FAMILY=Windows 10"
if "!WIN_EDITION!"=="Unknown" (
    set "WIN_EDITION=!WIN_PRODUCT!"
    set "WIN_EDITION=!WIN_EDITION:Windows 10 =!"
    set "WIN_EDITION=!WIN_EDITION:Windows 11 =!"
)
set "WIN_EDITION=!WIN_EDITION:Professional=Pro!"
set "WIN_EDITION=!WIN_EDITION:CoreSingleLanguage=Home SL!"
set "WIN_EDITION=!WIN_EDITION:Core=Home!"
if not defined WIN_EDITION set "WIN_EDITION=Unknown"
set "WIN_SUPPORTED=0"
if !WIN_BUILD! geq 22000 set "WIN_SUPPORTED=1"
if !WIN_BUILD! geq 19045 if !WIN_BUILD! lss 22000 set "WIN_SUPPORTED=1"
set "WIN_VER=!WIN_FAMILY! !WIN_EDITION! !WIN_DISPLAY! build !WIN_BUILD!.!WIN_UBR!"
if "!WIN_SUPPORTED!"=="0" call "%WP_LIB%\core.cmd" :WARN "сборка !WIN_BUILD! вне поддержки: нужен Win10 22H2 или Win11"
exit /b 0

rem ============================================================
rem  DETECT_ENV - то, что не требует PowerShell
rem ============================================================
:DETECT_ENV
set "WIN_ARCH=32"
if /i "%PROCESSOR_ARCHITECTURE%"=="AMD64" set "WIN_ARCH=64"
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "WIN_ARCH=ARM64"
if defined PROCESSOR_ARCHITEW6432 set "WIN_ARCH=64"
set "ZAPRET_FOUND=0"
tasklist 2>nul | findstr /i /c:"winws.exe" /c:"zapret.exe" >nul 2>&1
if not errorlevel 1 set "ZAPRET_FOUND=1"
sc query winws >nul 2>&1
if not errorlevel 1 set "ZAPRET_FOUND=1"
sc query zapret >nul 2>&1
if not errorlevel 1 set "ZAPRET_FOUND=1"
set "PENDING_REBOOT=0"
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v PendingFileRenameOperations >nul 2>&1
if not errorlevel 1 set "PENDING_REBOOT=1"
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" >nul 2>&1
if not errorlevel 1 set "PENDING_REBOOT=1"
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" >nul 2>&1
if not errorlevel 1 set "PENDING_REBOOT=1"
if "!BOOT_MODE!"=="Unknown" (
    bcdedit /enum {current} 2>nul | findstr /i /c:"winload.efi" >nul 2>&1
    if not errorlevel 1 (set "BOOT_MODE=UEFI") else (set "BOOT_MODE=Legacy")
)
exit /b 0

rem ============================================================
rem  DETECT_CLASSIFY - класс системы и защитные флаги
rem ============================================================
:DETECT_CLASSIFY
set "WEAK_PC=0"
set "WEAK_REASONS="
if "!RAM_VALID!"=="1" if !RAM_GB! lss 8 call :WEAK_ADD "RAM<8GB"
if !CPU_CORES! gtr 0 if !CPU_CORES! lss 4 call :WEAK_ADD "CPU<4cores"
if /i "!BOOT_DISK_TYPE!"=="HDD" call :WEAK_ADD "HDD"
if "!IS_LAPTOP!"=="1" set "WEAK_REASONS=!WEAK_REASONS! Laptop"
if not defined WEAK_REASONS set "WEAK_REASONS=none"
set "CPU_SMT=0"
if !CPU_THREADS! gtr !CPU_CORES! set "CPU_SMT=1"
rem Нет данных о дисках - считаем что HDD, чтобы не убить TRIM и SysMain
if !DISK_COUNT! equ 0 set "ALL_SSD=0"
if !HDD_COUNT! gtr 0 set "ALL_SSD=0"
if !DISK_UNKNOWN! gtr 0 set "ALL_SSD=0"
if /i "!BOOT_DISK_TYPE!"=="HDD" set "ALL_SSD=0"
if /i "!BOOT_DISK_TYPE!"=="Unknown" set "ALL_SSD=0"
set "SYSTEM_CLASS=MAINSTREAM"
if "!WEAK_PC!"=="1" set "SYSTEM_CLASS=WEAK"
if !RAM_GB! geq 32 if !CPU_CORES! geq 8 if /i "!BOOT_DISK_TYPE!"=="SSD" set "SYSTEM_CLASS=STRONG"
if "!CPU_GENERATION!"=="unknown" call "%WP_LIB%\core.cmd" :WARN "поколение CPU не определено, рисковые твики будут закрыты"
exit /b 0

:WEAK_ADD
set "WEAK_PC=1"
set "WEAK_REASONS=!WEAK_REASONS! %~1"
exit /b 0

rem ============================================================
rem  DETECT_HKCU - твики пользователя идут в его куст, а не
rem  в куст админа, от имени которого запущен скрипт
rem ============================================================
:DETECT_HKCU
set "HKCU_MISMATCH=0"
if not defined CONSOLE_SID goto :HKCU_DEFAULT
if not defined CURRENT_SID goto :HKCU_DEFAULT
if /i "!CONSOLE_SID!"=="!CURRENT_SID!" goto :HKCU_DEFAULT
reg query "HKU\!CONSOLE_SID!" >nul 2>&1
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :WARN "куст пользователя консоли не загружен, HKCU остаётся текущим"
    goto :HKCU_DEFAULT
)
set "WP_HKCU=HKU\!CONSOLE_SID!"
set "HKCU_MISMATCH=1"
call "%WP_LIB%\core.cmd" :WARN "запуск от другого админа: пользовательские твики пойдут в !WP_HKCU!"
exit /b 0
:HKCU_DEFAULT
set "WP_HKCU=HKCU"
exit /b 0

rem ============================================================
rem  DETECT_TIER_LABEL / SOURCES_FIX
rem ============================================================
:DETECT_TIER_LABEL
set "DETECT_TIER=full"
if "!DETECT_T1_RC!"=="2" set "DETECT_TIER=partial"
if "!DETECT_T2_USED!"=="1" set "DETECT_TIER=api"
if "!DETECT_MODE!"=="fallback" set "DETECT_TIER=registry"
exit /b 0

:DETECT_SOURCES_FIX
if !RAM_GB! leq 0 set "RAM_SOURCE=none"
if !CPU_THREADS! leq 0 set "CPU_TOPO_SOURCE=none"
if !DISK_COUNT! leq 0 set "DISK_SOURCE=none"
if /i "!BOOT_DISK_TYPE!"=="Unknown" set "BOOT_DISK_SOURCE=none"
if not "!FREE_SPACE_KNOWN!"=="1" set "FREE_SPACE_SOURCE=none"
if not defined GPU_HWID set "GPU_HWID="
if not defined GPU_INSTANCE set "GPU_INSTANCE="
if not defined GPU_CLASSKEY set "GPU_CLASSKEY="
if not defined DETECT_MISSING set "DETECT_MISSING=none"
exit /b 0

rem ============================================================
rem  DQ - reg query без привязки к длине имени значения
rem  %1 ключ  %2 имя значения  %3 имя переменной-приёмника
rem ============================================================
:DQ
set "_DL="
set "_DR="
for /f "tokens=* delims=" %%L in ('reg query "%~1" /v "%~2" 2^>nul') do set "_DL=%%L"
if not defined _DL (
    set "%~3="
    exit /b 1
)
set "_DR=!_DL:*REG_=REG_!"
for /f "tokens=1,*" %%a in ("!_DR!") do set "%~3=%%b"
exit /b 0

rem ============================================================
rem  DETECT_SYSINFO - снимок системы в папку сессии
rem ============================================================
:DETECT_SYSINFO
if not defined WP_SESSION_DIR exit /b 0
>"%WP_SESSION_DIR%\sysinfo.txt" (
    echo WinPulse %WP_VERSION% system snapshot
    echo Session: %STAMP%
    echo Collected: %DATE% %TIME%
    echo Detect mode: !DETECT_MODE!    tier: !DETECT_TIER!
    echo Missing facts:!DETECT_MISSING!
    echo ----------------------------------------
    echo OS: !WIN_VER!
    echo Supported: !WIN_SUPPORTED!    arch: !WIN_ARCH!
    echo OS source: !OS_SOURCE!
    echo Last update: !LAST_UPDATE!
    echo Console user: !CONSOLE_USER!
    echo HKCU target: !WP_HKCU!    mismatch: !HKCU_MISMATCH!
    echo ----------------------------------------
    echo CPU: !CPU_NAME!
    echo Vendor: !CPU_VENDOR!    source: !CPU_SOURCE!
    echo Cores/Threads: !CPU_CORES! / !CPU_THREADS!    topo: !CPU_TOPO_SOURCE!
    echo Series/Gen: !CPU_SERIES! / !CPU_GENERATION!
    echo Hybrid: !CPU_HYBRID!    SMT: !CPU_SMT!
    echo GPU: !GPU_NAME!
    echo GPU vendor: !GPU_VENDOR!    source: !GPU_SOURCE!
    echo GPU driver: !GPU_DRIVER!    date: !GPU_DRIVER_DATE!
    echo GPU instance: !GPU_INSTANCE!
    echo GPU hwid: !GPU_HWID!
    echo GPU classkey: !GPU_CLASSKEY!
    echo RAM GB: !RAM_GB!    valid: !RAM_VALID!    speed: !RAM_SPEED!    source: !RAM_SOURCE!
    echo ----------------------------------------
    echo System drive: !SYS_DRIVE!
    echo Free space GB: !FREE_SPACE_GB!    known: !FREE_SPACE_KNOWN!    source: !FREE_SPACE_SOURCE!
    echo Boot disk: !BOOT_DISK_NAME!
    echo Boot disk type: !BOOT_DISK_TYPE!    bus: !BOOT_DISK_BUS!    source: !BOOT_DISK_SOURCE!
    echo Disks total: !DISK_COUNT!    HDD: !HDD_COUNT!    unknown: !DISK_UNKNOWN!    allSSD: !ALL_SSD!
    echo Disk source: !DISK_SOURCE!
    echo All disks: !ALL_DISKS!
    echo ----------------------------------------
    echo Boot mode: !BOOT_MODE!    Secure boot: !SECURE_BOOT!
    echo BitLocker: !BITLOCKER_STATUS!
    echo VBS: !VBS_STATUS!    HVCI: !HVCI_STATUS!
    echo Defender RT: !DEFENDER_RT!    Tamper: !DEFENDER_TAMPER!
    echo Third-party AV: !AV_THIRD!
    echo Restore enabled: !RESTORE_ENABLED!    points: !RESTORE_COUNT!
    echo Chassis: !CHASSIS!    source: !CHASSIS_SOURCE!
    echo Laptop: !IS_LAPTOP!    on battery: !ON_BATTERY!    power source: !POWER_SOURCE!
    echo Zapret: !ZAPRET_FOUND!    pending reboot: !PENDING_REBOOT!
    echo ----------------------------------------
    echo System class: !SYSTEM_CLASS!
    echo Weak PC: !WEAK_PC!    reasons:!WEAK_REASONS!
)
exit /b 0

rem ============================================================
rem  DETECT_REPAIR - починка источников детекта.
rem  Службы включаются через SC_SET, то есть попадают в журнал.
rem  Salvage репозитория WMI необратим и помечается явно.
rem ============================================================
:DETECT_REPAIR
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == ПОЧИНКА ДЕТЕКТА ==
echo.
echo   Канал: !DETECT_TIER!    режим: !DETECT_MODE!
echo   Не определено:!DETECT_MISSING!
echo.
echo   Состояние служб-источников, Start: 2=auto 3=demand 4=disabled
for %%s in (Winmgmt StorSvc VSS swprv) do (
    set "_RS="
    call :DQ "HKLM\SYSTEM\CurrentControlSet\Services\%%s" "Start" _RS
    if not defined _RS (
        echo   %%s - отсутствует
    ) else (
        echo   %%s - Start=!_RS!
    )
)
echo.
set "_NEEDFIX=0"
for %%s in (Winmgmt StorSvc) do (
    set "_RS="
    call :DQ "HKLM\SYSTEM\CurrentControlSet\Services\%%s" "Start" _RS
    if defined _RS if /i "!_RS!"=="0x4" set "_NEEDFIX=1"
)
if "!_NEEDFIX!"=="1" (
    call "%WP_LIB%\core.cmd" :WARN "Winmgmt или StorSvc отключены, это и ломает детект"
    call "%WP_LIB%\core.cmd" :CONFIRM "Перевести их в Manual" Y
    if not errorlevel 1 (
        call "%WP_LIB%\core.cmd" :SC_SET "Winmgmt" "demand"
        call "%WP_LIB%\core.cmd" :SC_SET "StorSvc" "demand"
    )
)
echo.
call "%WP_LIB%\core.cmd" :CONFIRM "Проверить целостность репозитория WMI" Y
if errorlevel 1 goto :REPAIR_RERUN
winmgmt /verifyrepository
set "_WRC=!errorlevel!"
if "!_WRC!"=="0" (
    call "%WP_LIB%\core.cmd" :OK "Репозиторий WMI согласован"
    goto :REPAIR_RERUN
)
call "%WP_LIB%\core.cmd" :FAIL "Репозиторий WMI повреждён, код !_WRC!"
echo.
echo   winmgmt /salvagerepository попытается восстановить репозиторий.
echo   Операция необратима, может потребоваться перезагрузка.
echo   Введите YES заглавными для запуска.
set "_SAL="
set "WP_QUESTION=Ввод: "
call "%WP_LIB%\desktop_io.cmd" input _SAL
if not "!_SAL!"=="YES" goto :REPAIR_RERUN
if "!WP_DRYRUN!"=="1" (
    call "%WP_LIB%\core.cmd" :MSG "Предпросмотр: восстановление WMI пропущено"
    goto :REPAIR_RERUN
)
call "%WP_LIB%\core.cmd" :IRREVERSIBLE "winmgmt /salvagerepository"
winmgmt /salvagerepository
call "%WP_LIB%\core.cmd" :MSG "Salvage завершён с кодом !errorlevel!"
:REPAIR_RERUN
echo.
call "%WP_LIB%\core.cmd" :CONFIRM "Повторить детект сейчас" Y
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    exit /b 0
)
call :DETECT_ALL
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
exit /b 0

:: END OF FILE | Всего твиков в файле: 0
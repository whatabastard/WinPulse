@echo off
rem ============================================================
rem  WinPulse 7.1 "Rebuild"  |  lib\tweaks_danger.cmd
rem  Опасные твики: 14 операций. Только Advanced Mode.
rem
rem  Кодировка: UTF-8 БЕЗ BOM, CRLF. Символ "!" в echo запрещён.
rem  Вызов:  call "%WP_LIB%\tweaks_danger.cmd" :T_ИМЯ
rem  Свой setlocal ЗАПРЕЩЁН.
rem
rem  Отличия от 6.x:
rem  - Spectre/Meltdown вынесены из DPC в отдельный MITIGATIONS:
rem    разные риски, разный откат, разные подтверждения
rem  - useplatformtick больше не пишется yes и no в одном прогоне
rem  - ULPS/HDCP пишутся в реальные экземпляры адаптеров, не в 0000
rem  - MSI идёт через REGACL_SET, а не через Access Denied
rem  - перед BCD приостанавливается BitLocker, если он включён
rem
rem  Дополнительно к контракту: WP_SECURITY_REDUCED, WP_BCD_SUSPENDED
rem ============================================================
if "%~1"=="" exit /b 9009
if not defined WP_LIB exit /b 9009
if not defined JOURNAL exit /b 9009
set "__EP=%~1"
shift
goto %__EP%

rem ============================================================
rem  GPU_CLASS_LOAD - экземпляры Class\{4d36e968} из реестра
rem ============================================================
:GPU_CLASS_LOAD
if defined GC_COUNT (
    for /l %%i in (1,1,%GC_COUNT%) do (
        set "GC_%%i_INDEX="
        set "GC_%%i_VENDOR="
        set "GC_%%i_DESC="
        set "GC_%%i_KEY="
    )
)
set "GC_COUNT="
if not exist "%WP_RUN%" mkdir "%WP_RUN%" >nul 2>&1
set "_GCF=%WP_RUN%\gpuclass.txt"
if exist "%_GCF%" del /f /q "%_GCF%" >nul 2>&1
call "%WP_LIB%\core.cmd" :PS_RUN get-gpuclass "%_GCF%"
call "%WP_LIB%\backup.cmd" :LOAD_KV "%_GCF%"
if not defined GC_COUNT set "GC_COUNT=0"
exit /b 0

rem ============================================================
rem  T_VBS - 3 операции
rem  Без активного антивируса снимать защиту ядра нельзя.
rem ============================================================
:T_VBS
call "%WP_LIB%\guard.cmd" :G_ADVANCED "VBS"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_AV "VBS"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_CONFIRM "VBS" "Отключение VBS, HVCI и Credential Guard снимает защиту ядра и учётных данных. FaceIT и ESEA могут перестать запускаться. Прирост FPS не гарантирован"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "VBS" 3
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" "Enabled" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" "LsaCfgFlags" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard" "EnableVirtualizationBasedSecurity" REG_DWORD "0"
set "WP_REBOOT_REQUIRED=1"
set "WP_SECURITY_REDUCED=1"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_MITIGATIONS - 2 операции
rem ============================================================
:T_MITIGATIONS
call "%WP_LIB%\guard.cmd" :G_ADVANCED "MITIGATIONS"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_AV "MITIGATIONS"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_CONFIRM "MITIGATIONS" "Отключение защит от Spectre и Meltdown открывает спекулятивные атаки на память процесса. На современных CPU с аппаратными mitigations выигрыш близок к нулю"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "MITIGATIONS" 2
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "FeatureSettingsOverride" REG_DWORD "3"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "FeatureSettingsOverrideMask" REG_DWORD "3"
set "WP_REBOOT_REQUIRED=1"
set "WP_SECURITY_REDUCED=1"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_BCD_TIMERS - 3 операции
rem  useplatformtick пишется только no и только для старых CPU.
rem  В 6.x DPC ставил yes, а HPET_SMART следом no: два
rem  взаимоисключающих значения за один прогон.
rem ============================================================
:T_BCD_TIMERS
call "%WP_LIB%\guard.cmd" :G_ADVANCED "BCD_TIMERS"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_NOTLAPTOP "BCD_TIMERS"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_ACPOWER "BCD_TIMERS"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_CONFIRM "BCD_TIMERS" "Меняет загрузочные таймеры после перезагрузки. На ПК автора при опытах с dynamic tick и HPET наблюдались потеря буста и BSOD. Для обычной работы оставь выбор Windows"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\backup.cmd" :BCD_SUSPEND
if errorlevel 1 exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "BCD_TIMERS" 3
call "%WP_LIB%\core.cmd" :BCD_SET "disabledynamictick" "yes"
call "%WP_LIB%\core.cmd" :BCD_SET "useplatformclock" "no"
if /i "!CPU_GENERATION!"=="intel_old" goto :BCD_TICK_APPLY
if /i "!CPU_GENERATION!"=="zen_old" goto :BCD_TICK_APPLY
call "%WP_LIB%\core.cmd" :SKIP "useplatformtick: современный CPU !CPU_NAME!, принудительный platform tick не нужен"
goto :BCD_TICK_DONE
:BCD_TICK_APPLY
call "%WP_LIB%\core.cmd" :BCD_SET "useplatformtick" "no"
:BCD_TICK_DONE
set "WP_REBOOT_REQUIRED=1"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_BCD_TSC - 1 операция
rem  Неизвестное поколение CPU = блок не начинается.
rem ============================================================
:T_BCD_TSC
call "%WP_LIB%\guard.cmd" :G_ADVANCED "BCD_TSC"
if errorlevel 1 exit /b 0
if !CPU_SERIES! leq 0 (
    call "%WP_LIB%\core.cmd" :MSG "BCD_TSC: поколение CPU не определено, tscsyncpolicy не трогаем"
    exit /b 0
)
call "%WP_LIB%\guard.cmd" :G_NOTLAPTOP "BCD_TSC"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_CONFIRM "BCD_TSC" "tscsyncpolicy=Enhanced на части новых CPU ухудшает стабильность таймеров. Откат - группа B, требуется перезагрузка"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\backup.cmd" :BCD_SUSPEND
if errorlevel 1 exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "BCD_TSC" 1
call "%WP_LIB%\core.cmd" :BCD_SET "tscsyncpolicy" "Enhanced"
set "WP_REBOOT_REQUIRED=1"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_BCD_BOOT - 2 операции
rem  tpmbootentropy влияет на TPM, поэтому suspend обязателен.
rem ============================================================
:T_BCD_BOOT
call "%WP_LIB%\guard.cmd" :G_ADVANCED "BCD_BOOT"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_CONFIRM "BCD_BOOT" "tpmbootentropy ForceDisable снижает энтропию ранней загрузки. bootuxdisabled убирает анимацию и часть диагностических экранов загрузки"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\backup.cmd" :BCD_SUSPEND
if errorlevel 1 exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "BCD_BOOT" 2
call "%WP_LIB%\core.cmd" :BCD_SET "tpmbootentropy" "ForceDisable"
call "%WP_LIB%\core.cmd" :BCD_SET "bootuxdisabled" "on"
set "WP_REBOOT_REQUIRED=1"
set "WP_SECURITY_REDUCED=1"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_GPU_ULPS - 1 операция
rem  Пишется во ВСЕ экземпляры AMD, а не в слепой 0000,
rem  где мог оказаться Intel iGPU или другой адаптер.
rem ============================================================
:T_GPU_ULPS
call "%WP_LIB%\guard.cmd" :G_GPU_VENDOR "AMD" "GPU_ULPS"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_ACPOWER "GPU_ULPS"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "GPU_ULPS" 1
if "!IS_LAPTOP!"=="1" call "%WP_LIB%\core.cmd" :WARN "ноутбук: ULPS off повышает расход батареи и может затронуть переключение графики"
call :GPU_CLASS_LOAD
call "%WP_LIB%\core.cmd" :AGG_BEGIN
for /l %%i in (1,1,!GC_COUNT!) do (
    if /i "!GC_%%i_VENDOR!"=="AMD" call "%WP_LIB%\core.cmd" :REG_SET "!GC_%%i_KEY!" "EnableUlps" REG_DWORD "0"
)
call "%WP_LIB%\core.cmd" :AGG_END "AMD ULPS off"
set "WP_REBOOT_REQUIRED=1"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_GPU_HDCP - 1 операция
rem  Значение 4 нулевых байта как в исходном списке, не меняем.
rem ============================================================
:T_GPU_HDCP
call "%WP_LIB%\guard.cmd" :G_GPU_VENDOR "NVIDIA" "GPU_HDCP"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_CONFIRM "GPU_HDCP" "Отключение HDCP ломает защищённое видео: Netflix, Disney+, Amazon Prime и часть Blu-ray софта перестанут выводить картинку"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "GPU_HDCP" 1
call :GPU_CLASS_LOAD
call "%WP_LIB%\core.cmd" :AGG_BEGIN
for /l %%i in (1,1,!GC_COUNT!) do (
    if /i "!GC_%%i_VENDOR!"=="NVIDIA" call "%WP_LIB%\core.cmd" :REG_SET "!GC_%%i_KEY!" "RMHdcpKeyGlob" REG_BINARY "00000000"
)
call "%WP_LIB%\core.cmd" :AGG_END "NVIDIA HDCP off"
set "WP_REBOOT_REQUIRED=1"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  T_MSI_GPU - 1 операция
rem  Enum\PCI под TrustedInstaller: только REGACL_SET.
rem  Точный instance path из detect, не угаданный 0000.
rem ============================================================
:T_MSI_GPU
call "%WP_LIB%\guard.cmd" :G_ADVANCED "MSI_GPU"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_HWID "MSI_GPU"
if errorlevel 1 exit /b 0
if "!IS_LAPTOP!"=="1" (
    call "%WP_LIB%\guard.cmd" :G_CONFIRM "MSI_GPU" "Ноутбук с гибридной графикой: MSI может сломать переключение GPU и вывод через USB-C"
    if errorlevel 1 exit /b 0
)
call "%WP_LIB%\guard.cmd" :G_CONFIRM "MSI_GPU" "MSI Mode меняет обработку прерываний GPU. Неподдерживаемая конфигурация даёт BSOD при загрузке драйвера. Откат - группа G, может потребоваться безопасный режим"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "MSI_GPU" 1
call "%WP_LIB%\core.cmd" :MSG "GPU instance: !GPU_HWID!"
set "_MSIK=HKLM\SYSTEM\CurrentControlSet\Enum\PCI\!GPU_HWID!\Device Parameters\Interrupt Management"
call "%WP_LIB%\backup.cmd" :REGACL_SET "!_MSIK!\MessageSignaledInterruptProperties" "MSISupported" REG_DWORD "1"
set "WP_REBOOT_REQUIRED=1"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

:: END OF FILE | Всего твиков в файле: 14

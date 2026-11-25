@echo off
rem ============================================================
rem  WinPulse 7.1 "Rebuild"  |  lib\tweaks_exp.cmd
rem  Экспериментальные: 14 операций. Применяются ПО ОДНОМУ
rem  из меню Experimental, в MAXIMUM не входят.
rem
rem  Кодировка: UTF-8 БЕЗ BOM, CRLF. Символ "!" в echo запрещён.
rem  Вызов:  call "%WP_LIB%\tweaks_exp.cmd" :E_ИМЯ
rem  Свой setlocal ЗАПРЕЩЁН.
rem
rem  Правило модуля: сначала дешёвые проверки, подтверждение
rem  последним. Спрашивать YES и потом блокировать - бессмысленно.
rem  Guard ДО BLOCK_BEGIN. Ровно один инкремент на операцию.
rem ============================================================
if "%~1"=="" exit /b 9009
if not defined WP_LIB exit /b 9009
if not defined JOURNAL exit /b 9009
set "__EP=%~1"
shift
goto %__EP%

rem ============================================================
rem  E_DWM - 1 операция
rem ============================================================
:E_DWM
call "%WP_LIB%\guard.cmd" :G_ADVANCED "EXP_DWM"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_CONFIRM "EXP_DWM" "OverlayTestMode=5 - недокументированный режим DWM. На части GPU даёт артефакты и мерцание. Откат - группа G"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "EXP_DWM" 1
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Microsoft\Windows\DWM" "OverlayTestMode" REG_DWORD "5"
if not "%WP_DRYRUN%"=="1" taskkill /f /im dwm.exe >nul 2>&1
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  E_NX - 1 операция
rem ============================================================
:E_NX
call "%WP_LIB%\guard.cmd" :G_ADVANCED "EXP_NX"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_AV "EXP_NX"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_CONFIRM "EXP_NX" "DEP в режиме OptOut снижает защиту от эксплойтов памяти. Выигрыш в пределах погрешности. Откат - группа B, нужна перезагрузка"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\backup.cmd" :BCD_SUSPEND
if errorlevel 1 exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "EXP_NX" 1
call "%WP_LIB%\core.cmd" :BCD_SET "nx" "OptOut"
set "WP_SECURITY_REDUCED=1"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  E_PAGING_ENC - 1 операция
rem ============================================================
:E_PAGING_ENC
call "%WP_LIB%\guard.cmd" :G_ADVANCED "EXP_PAGING_ENC"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_CONFIRM "EXP_PAGING_ENC" "Без шифрования pagefile в нём читаемы фрагменты памяти процессов: пароли, ключи, токены. На большинстве систем шифрование и так выключено"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "EXP_PAGING_ENC" 1
call "%WP_LIB%\core.cmd" :FSUTIL_SET "encryptpagingfile" "0" "NtfsEncryptPagingFile" "0"
set "WP_SECURITY_REDUCED=1"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  E_DEF_SCRIPT - 1 операция
rem ============================================================
:E_DEF_SCRIPT
call "%WP_LIB%\guard.cmd" :G_ADVANCED "EXP_DEF_SCRIPT"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_TAMPER "EXP_DEF_SCRIPT"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_AV "EXP_DEF_SCRIPT"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_CONFIRM "EXP_DEF_SCRIPT" "Без проверки скриптов PowerShell, VBS и JS выполняются без анализа. Основной вектор fileless-атак"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "EXP_DEF_SCRIPT" 1
call "%WP_LIB%\backup.cmd" :DEF_SET "script" "0"
call "%WP_LIB%\guard.cmd" :G_SECURITY_INVALIDATE
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  E_TSC_LEGACY - 1 операция
rem  Жёстко закрыт на Intel 12+ и Ryzen 5000+, а также при
rem  неизвестном поколении CPU.
rem ============================================================
:E_TSC_LEGACY
call "%WP_LIB%\guard.cmd" :G_ADVANCED "EXP_TSC_LEGACY"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_CPU_OLD 11 4000 "EXP_TSC_LEGACY"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_NOTLAPTOP "EXP_TSC_LEGACY"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_CONFIRM "EXP_TSC_LEGACY" "Legacy TSC имеет смысл только на старых CPU. Замеряйте LatencyMon до и после, иначе эффект не отличить от шума"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\backup.cmd" :BCD_SUSPEND
if errorlevel 1 exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "EXP_TSC_LEGACY" 1
call "%WP_LIB%\core.cmd" :BCD_SET "tscsyncpolicy" "Legacy"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  E_SEHOP - 1 операция
rem ============================================================
:E_SEHOP
call "%WP_LIB%\guard.cmd" :G_ADVANCED "EXP_SEHOP"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_AV "EXP_SEHOP"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_CONFIRM "EXP_SEHOP" "Отключение SEHOP убирает проверку цепочки обработчиков исключений. Классический вектор SEH overwrite эксплойтов"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "EXP_SEHOP" 1
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" "DisableExceptionChainValidation" REG_DWORD "1"
set "WP_SECURITY_REDUCED=1"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  E_HETERO - 1 операция
rem  Требует РЕАЛЬНЫЕ E-cores и планировщик Win11.
rem ============================================================
:E_HETERO
call "%WP_LIB%\guard.cmd" :G_ADVANCED "EXP_HETERO"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_CPU_HYBRID "EXP_HETERO"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_BUILD 22000 "EXP_HETERO"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_CONFIRM "EXP_HETERO" "Отключение гетерогенного планирования на гибридном CPU может как помочь старым играм, так и просадить многопоток. Эффект спорный, замеряйте"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "EXP_HETERO" 1
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" "DisableHeterogeneousThreadScheduling" REG_DWORD "1"
set "WP_REBOOT_REQUIRED=1"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  E_DEF_RT - 1 операция
rem  Без стороннего AV система останется без защиты вообще.
rem ============================================================
:E_DEF_RT
call "%WP_LIB%\guard.cmd" :G_ADVANCED "EXP_DEF_RT"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_TAMPER "EXP_DEF_RT"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_AV_THIRD "EXP_DEF_RT"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_CONFIRM "EXP_DEF_RT" "Realtime-защита Defender выключится. Работает только при наличии стороннего антивируса. Сними Tamper Protection вручную, иначе изменение не применится"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "EXP_DEF_RT" 1
call "%WP_LIB%\backup.cmd" :DEF_SET "rt" "0"
call "%WP_LIB%\guard.cmd" :G_SECURITY_INVALIDATE
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  E_CSTATES - 1 операция, составная
rem  disabledynamictick плюс IDLEDISABLE считаются одной
rem  операцией по инвентарю, в журнал попадают обе записи.
rem ============================================================
:E_CSTATES
call "%WP_LIB%\guard.cmd" :G_ADVANCED "EXP_CSTATES"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_NOTLAPTOP "EXP_CSTATES"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_ACPOWER "EXP_CSTATES"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_CONFIRM "EXP_CSTATES" "Отключение C-states поднимет энергопотребление CPU и температуру. Может СНИЗИТЬ boost из-за нагрева. Нужен запас по охлаждению"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\backup.cmd" :BCD_SUSPEND
if errorlevel 1 exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "EXP_CSTATES" 1
call "%WP_LIB%\core.cmd" :AGG_BEGIN
call "%WP_LIB%\core.cmd" :BCD_SET "disabledynamictick" "yes"
call "%WP_LIB%\core.cmd" :POWER_SET "SUB_PROCESSOR" "IDLEDISABLE" "1" "KEEP"
call "%WP_LIB%\core.cmd" :AGG_END "CPU C-states off"
set "WP_REBOOT_REQUIRED=1"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  E_POOL - 2 операции
rem  Тот самый сценарий "8 ГБ и хочу твик для 32+".
rem ============================================================
:E_POOL
call "%WP_LIB%\guard.cmd" :G_ADVANCED "EXP_POOL"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_RAM 32 "EXP_POOL"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_RAM_SOFT 64 "EXP_POOL"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_CONFIRM "EXP_POOL" "Максимальные размеры пулов снимают лимиты ядра. При нехватке RAM это BSOD вместо деградации. Откат - группа M, нужна перезагрузка"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "EXP_POOL" 2
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "PoolUsageMaximum" REG_DWORD "4294967295"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "PagedPoolSize" REG_DWORD "4294967295"
set "WP_REBOOT_REQUIRED=1"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  E_SUPERFETCH - 1 операция
rem  EnableSuperfetch=0 запрещает Windows включать кэш обратно.
rem  SysMain Start=4 covered блоком SYSMAIN в warn.
rem ============================================================
:E_SUPERFETCH
call "%WP_LIB%\guard.cmd" :G_ADVANCED "EXP_SUPERFETCH"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_ALLSSD "EXP_SUPERFETCH"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_RAM_SOFT 16 "EXP_SUPERFETCH"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_CONFIRM "EXP_SUPERFETCH" "EnableSuperfetch=0 закрепляет отключение кэша предзагрузки. На медленных SSD и при малом RAM запуск приложений замедлится"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "EXP_SUPERFETCH" 1
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" "EnableSuperfetch" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

rem ============================================================
rem  E_ULTIMATE - 2 операции
rem  Ultimate Performance: тот же эффект, что точечные записи
rem  core parking, но схемой Microsoft и с откатом в одно действие.
rem  Только десктоп и только питание от сети.
rem ============================================================
:E_ULTIMATE
call "%WP_LIB%\guard.cmd" :G_ADVANCED "EXP_ULTIMATE"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_NOTLAPTOP "EXP_ULTIMATE"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_ACPOWER "EXP_ULTIMATE"
if errorlevel 1 exit /b 0
call "%WP_LIB%\guard.cmd" :G_CONFIRM "EXP_ULTIMATE" "Ultimate Performance отключает парковку ядер, USB suspend и ASPM пакетом. На Ryzen с CPPC может СНИЗИТЬ одноядерный boost из-за роста idle-температуры. Откат - группа P"
if errorlevel 1 exit /b 0
if "%WP_TWEAK_PROBE%"=="1" exit /b 0
call "%WP_LIB%\core.cmd" :BLOCK_BEGIN "EXP_ULTIMATE" 2
call "%WP_LIB%\backup.cmd" :POWER_ULTIMATE
call "%WP_LIB%\core.cmd" :BLOCK_END
exit /b 0

:: END OF FILE | Всего твиков в файле: 14

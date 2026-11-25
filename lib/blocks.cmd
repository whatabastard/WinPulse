@echo off
rem ============================================================
rem  WinPulse 7.1  |  lib\blocks.cmd  |  ЧАСТЬ 1/2
rem  Реестр блоков и состояние выбора для конструктора.
rem
rem  Кодировка: UTF-8 без BOM, CRLF.
rem  Символ "!" в echo запрещён: съедается delayed expansion.
rem
rem  Здесь НЕ определяется ни один твик. Только метаданные,
rem  выбор, вердикты и порядок вызова. Запись остаётся в модулях.
rem
rem  Формат записи реестра, rem  Формат записи реестра, семь полей через вертикальную черту::
rem    LABEL|module|category|ops|ID|description|flags
rem  flags: - обычное, NEW новое, REV ревизия, VAR число ops
rem         зависит от параметров, IRR содержит необратимое
rem ============================================================
if not defined WP_LIB exit /b 9009
if not defined JOURNAL exit /b 9009
set "__BEP=%~1"
if not defined __BEP exit /b 9009
if not "!__BEP:~0,1!"==":" exit /b 9009
shift
goto %__BEP%

rem ============================================================
rem  BLOCKS_DATA  реестр блоков
rem  Порядок номеров = порядок применения:
rem    01-19 safe, 20-40 warn, 41-48 danger, 49-60 exp
rem  Числа ops совпадают с TWEAKS_INVENTORY.txt и END OF FILE.
rem ============================================================
:BLOCKS_DATA
set "BLK_01=T_TELEMETRY|tweaks_safe|safe|24|B01|Телеметрия, реклама, DiagTrack|-"
set "BLK_02=T_NET_STD|tweaks_safe|safe|10|B02|Nagle, TTL, DNS-кэш, autotuning|-"
set "BLK_03=T_NET_PORTS|tweaks_safe|safe|4|B03|Динамические порты и backlog|-"
set "BLK_04=T_POWER|tweaks_safe|safe|5|B04|Схема High Perf, USB suspend|-"
set "BLK_05=T_POWER_THROTTLE|tweaks_safe|safe|2|B05|Power Throttling: ревизия|REV"
set "BLK_06=T_UWP|tweaks_safe|safe|13|B06|Удаление контентных UWP|VAR,IRR"
set "BLK_07=T_SCHTASKS|tweaks_safe|safe|7|B07|Задачи телеметрии и CEIP|-"
set "BLK_08=T_DEFENDER_EXC|tweaks_safe|safe|10|B08|Исключения Defender для игр|-"
set "BLK_09=T_SERVICES|tweaks_safe|safe|3|B09|DiagTrack, dmwappush, Fax|-"
set "BLK_10=T_SPOOLER|tweaks_safe|safe|2|B10|Печать: Spooler|-"
set "BLK_11=T_DEFRAG|tweaks_safe|safe|1|B11|Дефрагментация: defragsvc|-"
set "BLK_12=T_VISUAL|tweaks_safe|safe|10|B12|Визуал по профилю|VAR"
set "BLK_13=T_GAMING|tweaks_safe|safe|10|B13|Game Mode, GameDVR, FSE|-"
set "BLK_14=T_UX|tweaks_safe|safe|6|B14|Проводник, реклама в меню Пуск|-"
set "BLK_15=T_WORK|tweaks_safe|safe|5|B15|Рабочий профиль: таймауты, HAGS|-"
set "BLK_16=T_MAINT|tweaks_safe|safe|9|B16|TRIM, 8dot3, TEMP, кэши|IRR"
set "BLK_17=T_INPUT|tweaks_safe|safe|5|B17|Повтор клавиш, залипание|-"
set "BLK_18=T_PRIVACY_EXT|tweaks_safe|safe|5|B18|Фон приложений, локация, журнал|-"
set "BLK_19=T_WEBDAV|tweaks_safe|safe|1|B19|WebDAV-редиректор WebClient|-"
set "BLK_20=T_PRIORITY|tweaks_warn|warn|2|B20|Кванты и SystemResponsiveness|VAR"
set "BLK_21=T_MEMORY|tweaks_warn|warn|5|B21|Ядро в RAM, сжатие, пулы служб|VAR"
set "BLK_22=T_MMCSS|tweaks_warn|warn|4|B22|MMCSS: профиль Games|-"
set "BLK_23=T_POWER_HIBER|tweaks_warn|warn|1|B23|Гибернация и Fast Startup|-"
set "BLK_24=T_POWER_DISK|tweaks_warn|warn|1|B24|Отключение диска по простою|-"
set "BLK_25=T_POWER_TIMER|tweaks_warn|warn|1|B25|Таймер простоя платформы|-"
set "BLK_26=T_RESERVED|tweaks_warn|warn|1|B26|Reserved Storage|-"
set "BLK_27=T_WORK_IFEO|tweaks_warn|warn|1|B27|Приоритет рабочих приложений|-"
set "BLK_28=T_UX_CHAT|tweaks_warn|warn|1|B28|Чат на панели задач Win11|-"
set "BLK_29=T_MOUSE|tweaks_warn|warn|5|B29|Мышь 1:1, кривые ускорения|-"
set "BLK_30=T_TIMERS|tweaks_warn|warn|1|B30|GlobalTimerResolutionRequests|-"
set "BLK_31=T_NDU|tweaks_warn|warn|1|B31|Ndu: утечка nonpaged pool|-"
set "BLK_32=T_GAMEBAR_RT|tweaks_warn|warn|1|B32|GameBar PresenceWriter|-"
set "BLK_33=T_SERVICES_XBOX|tweaks_warn|warn|4|B33|Службы Xbox и ALG|-"
set "BLK_34=T_AUDIO|tweaks_warn|warn|1|B34|Аудио: только инструкция|-"
set "BLK_35=T_WDI|tweaks_warn|warn|1|B35|Autologger WDIContextLog|-"
set "BLK_36=T_STORPORT|tweaks_warn|warn|1|B36|storport IdleTimeout|-"
set "BLK_37=T_PREFETCH|tweaks_warn|warn|1|B37|Чистка Prefetch|IRR"
set "BLK_38=T_SYSMAIN|tweaks_warn|warn|2|B38|SysMain: стоп и отключение|-"
set "BLK_39=T_VISUAL_AGG|tweaks_warn|warn|3|B39|Прозрачность, меню, рестарт DWM|VAR"
set "BLK_40=T_NET_GLOBAL|tweaks_warn|warn|8|B40|ECN, RSS, RSC, FastOpen, ARP|-"
set "BLK_41=T_VBS|tweaks_danger|danger|3|B41|VBS, HVCI, Credential Guard|-"
set "BLK_42=T_MITIGATIONS|tweaks_danger|danger|2|B42|Spectre-митигации|-"
set "BLK_43=T_BCD_TIMERS|tweaks_danger|danger|3|B43|dynamic tick, platform clock|VAR"
set "BLK_44=T_BCD_TSC|tweaks_danger|danger|1|B44|tscsyncpolicy Enhanced|-"
set "BLK_45=T_BCD_BOOT|tweaks_danger|danger|2|B45|tpmbootentropy, bootux|-"
set "BLK_46=T_GPU_ULPS|tweaks_danger|danger|1|B46|ULPS: глубокий сон AMD|-"
set "BLK_47=T_GPU_HDCP|tweaks_danger|danger|1|B47|HDCP в драйвере NVIDIA|-"
set "BLK_48=T_MSI_GPU|tweaks_danger|danger|1|B48|MSI для GPU|-"
set "BLK_49=E_DWM|tweaks_exp|exp|1|B49|DWM OverlayTestMode|-"
set "BLK_50=E_NX|tweaks_exp|exp|1|B50|DEP: nx OptOut|-"
set "BLK_51=E_PAGING_ENC|tweaks_exp|exp|1|B51|Шифрование pagefile|-"
set "BLK_52=E_DEF_SCRIPT|tweaks_exp|exp|1|B52|Defender ScriptScanning|-"
set "BLK_53=E_TSC_LEGACY|tweaks_exp|exp|1|B53|tscsyncpolicy Legacy|-"
set "BLK_54=E_SEHOP|tweaks_exp|exp|1|B54|SEH chain validation|-"
set "BLK_55=E_HETERO|tweaks_exp|exp|1|B55|Гетерогенное планирование|-"
set "BLK_56=E_DEF_RT|tweaks_exp|exp|1|B56|Defender realtime|-"
set "BLK_57=E_CSTATES|tweaks_exp|exp|1|B57|C-states и idle disable|-"
set "BLK_58=E_POOL|tweaks_exp|exp|2|B58|PoolUsageMax, PagedPoolSize|-"
set "BLK_59=E_SUPERFETCH|tweaks_exp|exp|1|B59|EnableSuperfetch|-"
set "BLK_60=E_ULTIMATE|tweaks_exp|exp|2|B60|Схема Ultimate Performance|-"
set "BLK_61=T_SMB1|tweaks_safe|safe|1|B61|SMB1: сервер и клиент off|NEW"
set "BLK_62=T_IFEO_ECO|tweaks_safe|safe|1|B62|Фон: приоритет апдейтеров|NEW"
set "BLK_63=T_AUTORUN|tweaks_safe|safe|8|B63|Автозагрузка: 8 источников|NEW"
set "BLK_64=T_STORAGE_SAFE|tweaks_safe|safe|4|B64|Кэши: DO, WER, WU, шейдеры|NEW,IRR"
set "BLK_65=T_STORAGE_DEEP|tweaks_warn|warn|6|B65|WinSxS, Windows.old, логи|NEW,IRR"
set "BLK_66=T_SERVICES_EXT|tweaks_warn|warn|20|B66|Службы по факту устройств|NEW"
set "BLK_67=T_PROVISIONED|tweaks_warn|warn|30|B67|Provisioned: 17 плюс 13 по YES|NEW,IRR"
set "BLK_68=T_NIC_DRIVER|tweaks_warn|warn|14|B68|Ethernet: энергосбережение, RSC|NEW"
set "BLK_69=T_DO_PEERING|tweaks_safe|safe|2|B69|Запрет раздачи обновлений пирам|NEW"

rem --- Пресеты: номера блоков через пробел ---
set "PRESET_LIT=01 02 04 06 07 17 35 61 62"
set "PRESET_MIN=01 02 03 04 05 06 07 08 09 10 14 17 18 19 35 61 62 63 64 69"
set "PRESET_MED=01 02 03 04 05 06 07 08 09 10 12 13 14 16 17 18 19 20 22 35 61 62 63 64 65 69"
set "PRESET_WRK=01 02 03 04 05 06 07 09 10 12 14 15 16 17 18 19 20 27 35 61 62 63 64 69"

rem --- Пачки экспериментальных ---
set "PACK_E1=50 51 52 54 56"
set "PACK_E2=58 59"
set "PACK_E3=53 55 57"
set "PACK_E4=49 60"
set "PACK_E1_DESC=Защита: NX, pagefile, скрипты, SEH, realtime"
set "PACK_E2_DESC=Память: пулы и Superfetch"
set "PACK_E3_DESC=Планирование: TSC Legacy, гетеро, C-states"
set "PACK_E4_DESC=Загрузка и визуал: DWM, Ultimate"

rem --- Взаимоисключения: один ключ, разные значения ---
set "CONFLICT_1=44 53 tscsyncpolicy: Enhanced против Legacy"
set /a CONFLICT_COUNT=1
exit /b 0

rem ============================================================
rem  BLOCKS_LOAD  разбирает реестр в параллельные массивы.
rem  Идемпотентна: повторный вызов выходит сразу.
rem ============================================================
:BLOCKS_LOAD
if defined BLK_READY exit /b 0
call :BLOCKS_DATA
set /a BLK_COUNT=0
for /l %%i in (1,1,99) do (
    set "_bn=0%%i"
    set "_bn=!_bn:~-2!"
    if defined BLK_!_bn! set /a BLK_COUNT=%%i
)
if !BLK_COUNT! equ 0 exit /b 1
for /l %%i in (1,1,!BLK_COUNT!) do (
    set "_bn=0%%i"
    set "_bn=!_bn:~-2!"
    call :BLOCKS_PARSE !_bn!
)
for /l %%i in (1,1,!BLK_COUNT!) do (
    set "_bn=0%%i"
    set "_bn=!_bn:~-2!"
    if not defined SEL_!_bn! set "SEL_!_bn!=0"
    set "VD_!_bn!=?"
)
set "BLK_READY=1"
set "BLK_BASE=none"
set "WP_UWP_MODE=selective"
exit /b 0

:BLOCKS_PARSE
for /f "tokens=1-7 delims=|" %%a in ("!BLK_%~1!") do (
    set "BL_LBL_%~1=%%a"
    set "BL_MOD_%~1=%%b"
    set "BL_CAT_%~1=%%c"
    set "BL_OPS_%~1=%%d"
    set "BL_ID_%~1=%%e"
    set "BL_DESC_%~1=%%f"
    set "BL_FLAG_%~1=%%g"
)
exit /b 0

rem ============================================================
rem  BLOCKS_NORM  %1 номер в любом виде -> _NM две цифры.
rem  _NM пустая, если номер невалиден или вне диапазона.
rem  Проверка на цифры через delims, без запуска процессов.
rem ============================================================
:BLOCKS_NORM
set "_NM="
set "_iv=%~1"
if not defined _iv exit /b 0
set "_nbad="
for /f "delims=0123456789" %%z in ("!_iv!") do set "_nbad=1"
if defined _nbad exit /b 0
for /f "tokens=* delims=0" %%z in ("!_iv!") do set "_iv=%%z"
if not defined _iv set "_iv=0"
set /a _in=_iv
if !_in! lss 1 exit /b 0
if !_in! gtr !BLK_COUNT! exit /b 0
set "_NM=0!_in!"
set "_NM=!_NM:~-2!"
exit /b 0

rem ============================================================
rem  BLOCKS_CLEAR  снимает весь выбор
rem ============================================================
:BLOCKS_CLEAR
for /l %%i in (1,1,!BLK_COUNT!) do (
    set "_bn=0%%i"
    set "_bn=!_bn:~-2!"
    set "SEL_!_bn!=0"
)
set "BLK_BASE=none"
set "WP_UWP_MODE=selective"
exit /b 0

rem ============================================================
rem  BLOCKS_FLIP  %1 двузначный номер, инвертирует выбор
rem ============================================================
:BLOCKS_FLIP
if "!SEL_%~1!"=="1" (
    set "SEL_%~1=0"
) else (
    set "SEL_%~1=1"
)
exit /b 0

rem ============================================================
rem  BLOCKS_RANGE  %1 начало %2 конец, инвертирует каждый
rem ============================================================
:BLOCKS_RANGE
set /a _ra=1%~1-100
set /a _rb=1%~2-100
if !_ra! gtr !_rb! (
    set /a _rt=_ra
    set /a _ra=_rb
    set /a _rb=_rt
)
for /l %%i in (!_ra!,1,!_rb!) do (
    set "_bn=0%%i"
    set "_bn=!_bn:~-2!"
    call :BLOCKS_FLIP !_bn!
)
exit /b 0

rem ============================================================
rem  BLOCKS_TOGGLE  %1 строка вида "1,3,5-8,12"
rem  Одиночные номера и диапазоны инвертируются.
rem ============================================================
:BLOCKS_TOGGLE
set "_tl=%~1"
if not defined _tl exit /b 0
set "_tl=!_tl:,= !"
set "_tl=!_tl:;= !"
for %%t in (!_tl!) do (
    set "_tt=%%t"
    if "!_tt:-=!"=="!_tt!" (
        call :BLOCKS_NORM !_tt!
        if defined _NM call :BLOCKS_FLIP !_NM!
    ) else (
        for /f "tokens=1,2 delims=-" %%a in ("!_tt!") do (
            call :BLOCKS_NORM %%a
            set "_r1=!_NM!"
            call :BLOCKS_NORM %%b
            set "_r2=!_NM!"
            if defined _r1 if defined _r2 call :BLOCKS_RANGE !_r1! !_r2!
        )
    )
)
exit /b 0

rem ============================================================
rem  BLOCKS_ALL  %1 safe|warn|danger|exp|all -> выбирает, не инвертирует
rem ============================================================
:BLOCKS_ALL
set "_ac=%~1"
if not defined _ac exit /b 0
for /l %%i in (1,1,!BLK_COUNT!) do (
    set "_bn=0%%i"
    set "_bn=!_bn:~-2!"
    for %%v in (!_bn!) do (
        if /i "!_ac!"=="all" set "SEL_%%v=1"
        if /i "!BL_CAT_%%v!"=="!_ac!" set "SEL_%%v=1"
    )
)
exit /b 0

rem ============================================================
rem  BLOCKS_NEW  выбирает только помеченные NEW
rem ============================================================
:BLOCKS_NEW
set /a _nw=0
for /l %%i in (1,1,!BLK_COUNT!) do (
    set "_bn=0%%i"
    set "_bn=!_bn:~-2!"
    for %%v in (!_bn!) do (
        set "_bf=!BL_FLAG_%%v!"
        if not "!_bf:NEW=!"=="!_bf!" (
            set "SEL_%%v=1"
            set /a _nw+=1
        )
    )
)
set /a BLK_NEW_FOUND=_nw
exit /b 0

rem ============================================================
rem  BLOCKS_PACK  %1 E1|E2|E3|E4, добавляет пачку к выбору
rem ============================================================
:BLOCKS_PACK
set "_pk=%~1"
if not defined _pk exit /b 0
set "_pl="
if /i "!_pk!"=="E1" set "_pl=!PACK_E1!"
if /i "!_pk!"=="E2" set "_pl=!PACK_E2!"
if /i "!_pk!"=="E3" set "_pl=!PACK_E3!"
if /i "!_pk!"=="E4" set "_pl=!PACK_E4!"
if not defined _pl exit /b 1
for %%n in (!_pl!) do set "SEL_%%n=1"
exit /b 0

rem ============================================================
rem  BLOCKS_PRESET  %1 LIT|MIN|MED|WRK|MAX
rem  Задаёт базу и параметры режимов, которые влияют на число ops.
rem ============================================================
:BLOCKS_PRESET
set "_pn=%~1"
if not defined _pn exit /b 1
if /i not "!_pn!"=="LIT" if /i not "!_pn!"=="MIN" if /i not "!_pn!"=="MED" if /i not "!_pn!"=="WRK" if /i not "!_pn!"=="MAX" exit /b 1
call :BLOCKS_CLEAR
set "_pl="
if /i "!_pn!"=="LIT" (
    set "_pl=!PRESET_LIT!"
    set "WP_UWP_MODE=selective"
    set "BLK_BASE=LITE"
)
if /i "!_pn!"=="MIN" (
    set "_pl=!PRESET_MIN!"
    set "WP_UWP_MODE=full"
    set "BLK_BASE=MINIMUM"
)
if /i "!_pn!"=="MED" (
    set "_pl=!PRESET_MED!"
    set "WP_UWP_MODE=full"
    set "BLK_BASE=MEDIUM"
    if "!WEAK_PC!"=="1" (
        set "WP_VISUAL_PROFILE=Comfort"
    ) else (
        set "WP_VISUAL_PROFILE=Balanced"
    )
)
if /i "!_pn!"=="WRK" (
    set "_pl=!PRESET_WRK!"
    set "WP_UWP_MODE=selective"
    set "WP_VISUAL_PROFILE=Work"
    set "BLK_BASE=WORK"
)
if /i "!_pn!"=="MAX" (
    set "WP_UWP_MODE=full"
    set "BLK_BASE=MAXIMUM"
    for /l %%i in (1,1,!BLK_COUNT!) do (
        set "_bn=0%%i"
        set "_bn=!_bn:~-2!"
        for %%v in (!_bn!) do (
            if /i not "!BL_CAT_%%v!"=="exp" set "SEL_%%v=1"
        )
    )
)
if not defined _pl if /i not "!_pn!"=="MAX" exit /b 1
if defined _pl for %%n in (!_pl!) do set "SEL_%%n=1"
exit /b 0

rem ============================================================
rem  BLOCKS_CONFLICT  возвращает 1 если выбраны несовместимые.
rem  Пишет список в _CF_LIST, счётчик в BLK_CF_COUNT.
rem ============================================================
:BLOCKS_CONFLICT
set /a BLK_CF_COUNT=0
set "_CF_LIST="
for /l %%c in (1,1,!CONFLICT_COUNT!) do (
    for /f "tokens=1,2,*" %%a in ("!CONFLICT_%%c!") do (
        set "_c1=%%a"
        set "_c2=%%b"
        set "_cd=%%c"
        if "!SEL_%%a!"=="1" if "!SEL_%%b!"=="1" (
            set /a BLK_CF_COUNT+=1
            set "_CF_LIST=!_CF_LIST! !_cd!"
        )
    )
)
if !BLK_CF_COUNT! gtr 0 exit /b 1
exit /b 0

rem ============================================================
rem  BLOCKS_VERDICT  %1 двузначный номер.
rem  Пробник: гварды отрабатывают, запись не доходит.
rem  Код возврата блока и есть вердикт: 2 = HARD, 0 = разрешён.
rem  VD_nn = OK | SOFT | BLOCK | ?
rem ============================================================
:BLOCKS_VERDICT
if not defined SOFTLIST set "SOFTLIST=06 10 12 18 20 21 23 26 33 37 38 39"
set "_vn=%~1"
if not defined _vn exit /b 1
if not defined BL_LBL_%_vn% exit /b 1
set "WP_PROBE_KIND="
set "WP_GUARD_PROBE=1"
set "WP_TWEAK_PROBE=1"
call "%WP_LIB%\!BL_MOD_%_vn%!.cmd" :!BL_LBL_%_vn%!
set "_vv=!errorlevel!"
set "_vk=!WP_PROBE_KIND!"
set "WP_TWEAK_PROBE=0"
set "WP_GUARD_PROBE=0"
set "WP_PROBE_KIND="
if "!_vk!"=="HARD" (
    set "VD_%_vn%=BLOCK"
    exit /b 0
)
if !_vv! geq 2 (
    set "VD_%_vn%=BLOCK"
    exit /b 0
)
if "!_vk!"=="INFO" (
    set "VD_%_vn%=N/A"
    exit /b 0
)
if "!_vk!"=="SOFT" (
    set "VD_%_vn%=SOFT"
    exit /b 0
)
set "VD_%_vn%=OK"
set "_vc=!BL_CAT_%_vn%!"
if /i "!_vc!"=="danger" set "VD_%_vn%=SOFT"
if /i "!_vc!"=="exp" set "VD_%_vn%=SOFT"
for %%s in (!SOFTLIST!) do if "%%s"=="%_vn%" set "VD_%_vn%=SOFT"
exit /b 0

rem ============================================================
rem  BLOCKS_VERDICT_ALL  пробник по всем блокам.
rem  Security обновляется один раз, иначе 60 обращений к PS.
rem ============================================================
:BLOCKS_VERDICT_ALL
if defined WP_VISUAL_CHOICE if /i not "!WP_VISUAL_CHOICE!"=="Auto" set "WP_VISUAL_PROFILE=!WP_VISUAL_CHOICE!"
if not defined SOFTLIST set "SOFTLIST=06 10 12 18 20 21 23 26 33 37 38 39"
call "%WP_LIB%\guard.cmd" :G_SECURITY_REFRESH
for /l %%i in (1,1,!BLK_COUNT!) do (
    set "_bn=0%%i"
    set "_bn=!_bn:~-2!"
    call :BLOCKS_VERDICT !_bn!
)
set "WP_GUARD_PROBE=0"
set "WP_TWEAK_PROBE=0"
exit /b 0

rem ============================================================
rem  BLOCKS_SELSTAT  счётчики выбора. Ничего не печатает.
rem  BS_N блоков, BS_OPS номинальных операций, разбивка по категориям,
rem  BS_IRR необратимых, BS_BLOCK закрытых гвардом, BS_SOFT требующих YES.
rem  BS_VAR блоков с переменным числом ops.
rem ============================================================
:BLOCKS_SELSTAT
set /a BS_N=0
set /a BS_OPS=0
set /a BS_SAFE=0
set /a BS_WARN=0
set /a BS_DANGER=0
set /a BS_EXP=0
set /a BS_IRR=0
set /a BS_BLOCK=0
set /a BS_SOFT=0
set /a BS_NA=0
set /a BS_VAR=0

for /l %%i in (1,1,!BLK_COUNT!) do (
    set "_bn=0%%i"
    set "_bn=!_bn:~-2!"
    for %%v in (!_bn!) do (
        set "BS_COUNT_%%v=!BL_OPS_%%v!"
        if "%%v"=="06" if /i not "!WP_UWP_MODE!"=="full" set "BS_COUNT_%%v=6"
        if "!SEL_%%v!"=="1" (
            set /a BS_N+=1
            set /a BS_OPS+=BS_COUNT_%%v
            if /i "!BL_CAT_%%v!"=="safe" set /a BS_SAFE+=BS_COUNT_%%v
            if /i "!BL_CAT_%%v!"=="warn" set /a BS_WARN+=BS_COUNT_%%v
            if /i "!BL_CAT_%%v!"=="danger" set /a BS_DANGER+=BS_COUNT_%%v
            if /i "!BL_CAT_%%v!"=="exp" set /a BS_EXP+=BS_COUNT_%%v
            if "!VD_%%v!"=="BLOCK" set /a BS_BLOCK+=1
            if "!VD_%%v!"=="SOFT" set /a BS_SOFT+=1
            if "!VD_%%v!"=="N/A" set /a BS_NA+=1
            set "_sf=!BL_FLAG_%%v!"
            if not "!_sf:IRR=!"=="!_sf!" set /a BS_IRR+=1
            if not "!_sf:VAR=!"=="!_sf!" set /a BS_VAR+=1
        )
    )
)
exit /b 0

rem ============================================================
rem  BLOCKS_PLAN  превью выбора. В PLAN_LOG не пишет:
rem  туда попадают только реальные операции при применении.
rem ============================================================
:BLOCKS_PLAN
if defined WP_VISUAL_CHOICE if /i not "!WP_VISUAL_CHOICE!"=="Auto" set "WP_VISUAL_PROFILE=!WP_VISUAL_CHOICE!"
call :BLOCKS_SELSTAT
call :BLOCKS_CONFLICT
echo.
echo == ПЛАН КОНСТРУКТОРА ==
echo   База: !BLK_BASE!   Профиль визуала: !WP_VISUAL_PROFILE!   UWP: !WP_UWP_MODE!
echo   Выбрано блоков: !BS_N!   Номинально операций: !BS_OPS!
echo   safe !BS_SAFE!   warn !BS_WARN!   danger !BS_DANGER!   exp !BS_EXP!
echo.
if !BS_N! equ 0 (
    echo   Выбор пуст. Задайте базу командой B или отметьте блоки номерами.
    exit /b 0
)
echo   Блоки:
for /l %%i in (1,1,!BLK_COUNT!) do (
    set "_bn=0%%i"
    set "_bn=!_bn:~-2!"
    for %%v in (!_bn!) do (
        if "!SEL_%%v!"=="1" (
            set "_pd=!VD_%%v!      "
            set "_pd=!_pd:~0,6!"
            set "_po=   !BS_COUNT_%%v!"
            set "_po=!_po:~-3!"
            echo     %%v !BL_ID_%%v! !_pd! !_po!  !BL_LBL_%%v!
        )
    )
)
echo.
if !BS_VAR! gtr 0 (
    echo   [NOTE] Блоков с переменным числом операций: !BS_VAR!
    echo   Фактическое число зависит от профиля визуала, режима UWP и ответа
    echo   на подтверждения. Точный итог даст BLOCK_END при применении.
)
if !BS_NA! gtr 0 (
    echo   [NOTE] Неприменимы к конфигурации: !BS_NA! блоков. Тихий пропуск.
)
if !BS_SOFT! gtr 0 (
    echo   [NOTE] Требуют подтверждения: !BS_SOFT! блоков. В песочнице берут да.
)
if !BS_BLOCK! gtr 0 (
    echo   [WARN] Закрыто гвардом: !BS_BLOCK! блоков. Они не начнутся.
    for /l %%i in (1,1,!BLK_COUNT!) do (
        set "_bn=0%%i"
        set "_bn=!_bn:~-2!"
        for %%v in (!_bn!) do (
            if "!SEL_%%v!"=="1" if "!VD_%%v!"=="BLOCK" (
                echo     %%v !BL_LBL_%%v! - !BL_DESC_%%v!
            )
        )
    )
)
if !BS_IRR! gtr 0 (
    echo   [WARN] Содержат необратимое: !BS_IRR! блоков. Откат их не вернёт.
    for /l %%i in (1,1,!BLK_COUNT!) do (
        set "_bn=0%%i"
        set "_bn=!_bn:~-2!"
        for %%v in (!_bn!) do (
            if "!SEL_%%v!"=="1" (
                set "_sf=!BL_FLAG_%%v!"
                if not "!_sf:IRR=!"=="!_sf!" echo     %%v !BL_LBL_%%v!
            )
        )
    )
)
if !BLK_CF_COUNT! gtr 0 (
    echo   [CRITICAL] Конфликты:!_CF_LIST!
    echo   Применение заблокировано, снимите один из блоков пары.
)
>>"%SESSION_LOG%" echo [%TIME%] CONSTRUCTOR PLAN base=!BLK_BASE! blocks=!BS_N! ops=!BS_OPS! blocked=!BS_BLOCK! irr=!BS_IRR!
exit /b 0

rem ============================================================
rem  BLOCKS_SHOW  %1 номер страницы, по 20 блоков.
rem ============================================================
:BLOCKS_SHOW
set /a "_pgmax=(BLK_COUNT+19)/20"
set /a _pg=%~1
if !_pg! lss 1 set /a _pg=1
if !_pg! gtr !_pgmax! set /a _pg=!_pgmax!
set /a "_ps=(_pg-1)*20+1"
set /a _pe=_pg*20
if !_pe! gtr !BLK_COUNT! set /a _pe=BLK_COUNT
call :BLOCKS_SELSTAT
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == КОНСТРУКТОР ==  стр !_pg!/!_pgmax!   база !BLK_BASE!   выбрано !BS_N! блоков, !BS_OPS! ops
echo.
echo   N  выб блок             кат    ops верд  фл  описание
echo   ------------------------------------------------------------
for /l %%i in (!_ps!,1,!_pe!) do (
    set "_bn=0%%i"
    set "_bn=!_bn:~-2!"
    for %%v in (!_bn!) do (
        set "_mk= "
        if "!SEL_%%v!"=="1" set "_mk=x"
        set "_lb=!BL_LBL_%%v!                 "
        set "_lb=!_lb:~0,17!"
        set "_ct=!BL_CAT_%%v!      "
        set "_ct=!_ct:~0,6!"
        set "_po=   !BS_COUNT_%%v!"
        set "_po=!_po:~-3!"
        set "_pd=!VD_%%v!     "
        set "_pd=!_pd:~0,5!"
        set "_fg="
        set "_sf=!BL_FLAG_%%v!"
        if not "!_sf:NEW=!"=="!_sf!" set "_fg=!_fg!*"
        if not "!_sf:REV=!"=="!_sf!" set "_fg=!_fg!R"
        if not "!_sf:VAR=!"=="!_sf!" set "_fg=!_fg!V"
        if not "!_sf:IRR=!"=="!_sf!" set "_fg=!_fg!I"
        rem флаг уже собран кодами
        set "_fg=!_fg!    "
        set "_fg=!_fg:~0,2!"
        set "_ds=!BL_DESC_%%v!                                 "
        set "_ds=!_ds:~0,33!"
        echo   %%v [!_mk!] !_lb! !_ct! !_po! !_pd! !_fg! !_ds!
    )
)
echo.
echo   1,3,5-8 инвертировать   A safe^|warn^|danger^|exp^|all   N снять выбор
echo   B LIT^|MIN^|MED^|WRK^|MAX база   E1..E4 пачки экспов   W выбрать новые
echo   G гварды   P план   S страница   X применить   Q выход
echo   Метки в колонке фл, это НЕ команды, набирать их нельзя:
echo     * новое   R ревизия   V переменное ops   I необратимое
echo.
if !BLK_CF_COUNT! gtr 0 echo   [CRITICAL] Конфликт:!_CF_LIST!
exit /b 0

rem ============================================================
rem  BLOCKS_APPLY  применение выбранного.
rem  Порядок = номер блока. Категории перемежаются, сверка по blocks.cmd.
rem  Гвард остаётся единственным источником истины: заблокированный
rem  блок вызывается и выходит сам, счётчики не трогает.
rem  Точку восстановления готовит вызывающая сторона через MODE_PREP.
rem ============================================================
:BLOCKS_APPLY
if defined WP_VISUAL_CHOICE if /i not "!WP_VISUAL_CHOICE!"=="Auto" set "WP_VISUAL_PROFILE=!WP_VISUAL_CHOICE!"
call :BLOCKS_CONFLICT
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :FAIL "Конструктор: конфликт блоков!_CF_LIST!"
    exit /b 1
)
call :BLOCKS_SELSTAT
if !BS_N! equ 0 (
    call "%WP_LIB%\core.cmd" :WARN "Конструктор: выбор пуст, применять нечего"
    exit /b 1
)
call "%WP_LIB%\core.cmd" :HEAD "Конструктор: !BS_N! блоков, номинально !BS_OPS! операций"
>>"%SESSION_LOG%" echo [%TIME%] CONSTRUCTOR APPLY base=!BLK_BASE! blocks=!BS_N! ops=!BS_OPS!
set "WP_GUARD_PROBE=0"
set "WP_TWEAK_PROBE=0"
set /a _ap_done=0
set /a _ap_block=0
for %%c in (safe warn danger exp) do (
    for /l %%i in (1,1,!BLK_COUNT!) do (
        set "_bn=0%%i"
        set "_bn=!_bn:~-2!"
        for %%v in (!_bn!) do (
            if "!SEL_%%v!"=="1" if /i "!BL_CAT_%%v!"=="%%c" (
                >>"%SESSION_LOG%" echo [%TIME%] CONSTRUCTOR BLOCK %%v !BL_ID_%%v! !BL_LBL_%%v! probe=!VD_%%v!
                set "WP_GUARD_LAST="
                if /i "!BL_LBL_%%v!"=="T_UWP" (
                    call "%WP_LIB%\!BL_MOD_%%v!.cmd" :T_UWP "!WP_UWP_MODE!"
                ) else (
                    call "%WP_LIB%\!BL_MOD_%%v!.cmd" :!BL_LBL_%%v!
                )
                set "_ar=!errorlevel!"
                if "!WP_GUARD_LAST!"=="HARD" (
                    set /a _ap_block+=1
                    >>"%SESSION_LOG%" echo [%TIME%] CONSTRUCTOR BLOCKED %%v rc=!_ar!
                ) else (
                    set /a _ap_done+=1
                )
            )
        )
    )
)
set /a BLK_AP_DONE=_ap_done
set /a BLK_AP_BLOCK=_ap_block
call "%WP_LIB%\core.cmd" :OK "Конструктор: отработало блоков !_ap_done!, закрыто гвардом !_ap_block!"
>>"%SESSION_LOG%" echo [%TIME%] CONSTRUCTOR DONE ok=!_ap_done! blocked=!_ap_block!
exit /b 0

:: Суммы по категориям считаются из BLK_n.
:: END OF FILE | Всего твиков в файле: 0

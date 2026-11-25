@echo off
rem ============================================================
rem  WinPulse 7.1 "Rebuild"  |  lib\backup.cmd  |  ЧАСТЬ 1/4
rem  Состояние и возврат: сессии, журнал, точки восстановления,
rem  обёртки PS-мутаций, движок отката.
rem
rem  Кодировка: UTF-8 БЕЗ BOM, CRLF. Символ "!" в echo запрещён.
rem  Вызов:  call "%WP_LIB%\backup.cmd" :LABEL "arg1" ...
rem  Свой setlocal ЗАПРЕЩЁН.
rem
rem  Контракт от winpulse.bat дополнительно к core.cmd:
rem    WP_BACKUPS WP_LOGS WP_RUN WP_SESSION_DIR STAMP
rem    WP_VERSION WP_CODENAME ADVANCED_MODE
rem    WP_RP_OK WP_RP_SEQ WP_RP_SKIPPED
rem
rem  Схема журнала, 19 типов:
rem    REG|key|value|ABSENT / TYPE|DATA
rem    REGACL|key|value|ABSENT / TYPE|DATA
rem    KEY|key|ABSENT
rem    SVC|name|RUNNING
rem    BCD|element|ABSENT / value
rem    POWER|sub|setting|AC|DC
rem    POWERSCHEME|guid
rem    POWERNEW|guid
rem    NETSH|param|default
rem    NETSHSUPP|template|default
rem    FSUTIL|behavior|default
rem    TASK|path|ENABLED (старые журналы: DEFAULT_ENABLED)
rem    HIBER|0/1
rem    RESERVED|0/1/UNKNOWN
rem    BCDSUSPEND|drive
rem    MMAGENT|feature|oldstate
rem    DEFEXCL|kind|value|ABSENT/PRESENT
rem    DEFSTATE|target|oldstate
rem    IRREVERSIBLE|text
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
rem  LOAD_KV  %1 файл KEY=VALUE
rem  Общая утилита для всех модулей. Чтение через usebackq:
rem  дочерний cmd не участвует, кавычки и delayed expansion
rem  не ломаются. Повторный ключ перезаписывает предыдущий.
rem ============================================================
:LOAD_KV
if not exist "%~1" exit /b 1
for /f "usebackq tokens=1,* delims==" %%a in ("%~1") do (
    if not "%%a"=="" set "%%a=%%b"
)
exit /b 0

rem ============================================================
rem  SESSION_INIT - идемпотентно, можно звать повторно.
rem  В журнал НЕ пишем заголовок: каждая строка должна быть
rem  валидной записью, иначе replay споткнётся о комментарий.
rem ============================================================
:SESSION_INIT
if not defined WP_SESSION_DIR exit /b 1
if not exist "%WP_SESSION_DIR%" mkdir "%WP_SESSION_DIR%" >nul 2>&1
if not exist "%WP_SESSION_DIR%" exit /b 1
type nul >> "%JOURNAL%" || exit /b 1
type nul >> "%PLAN_LOG%" || exit /b 1
if not exist "%WP_RUN%" mkdir "%WP_RUN%" >nul 2>&1
if not exist "%JOURNAL%" exit /b 1
if not exist "%PLAN_LOG%" exit /b 1
for %%f in ("%JOURNAL%" "%PLAN_LOG%" "%WP_SESSION_DIR%\session.txt") do (
    set "_ATTR=%%~af"
    if /i "!_ATTR:~0,1!"=="d" exit /b 1
)
for %%d in ("%WP_RUN%") do set "_ATTR=%%~ad"
if /i not "!_ATTR:~0,1!"=="d" exit /b 1
if exist "%WP_SESSION_DIR%\session.txt" exit /b 0
>"%WP_SESSION_DIR%\session.txt" (
    echo WinPulse %WP_VERSION% %WP_CODENAME%
    echo Session: %STAMP%
    echo Started: %DATE% %TIME%
    echo Computer: %COMPUTERNAME%
    echo DryRun: %WP_DRYRUN%
    echo Advanced: %ADVANCED_MODE%
)
if not exist "%WP_SESSION_DIR%\session.txt" exit /b 1
exit /b 0

rem ============================================================
rem  SESSION_ROTATE  %1 сколько сессий хранить, по умолчанию 10
rem  Имена папок = yyyyMMdd_HHmmss, сортировка по имени = по времени.
rem  Текущая сессия не удаляется никогда.
rem  В 6.4 ротация удаляла мифические HKLM_*.reg, которых не было.
rem ============================================================
:SESSION_ROTATE
if "%WP_DRYRUN%"=="1" exit /b 0
set "_KEEP=%~1"
if not defined _KEEP set "_KEEP=10"
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WP_LIB%\wp.ps1" rotate-sessions
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :WARN "Ротация сессий не завершена"
    exit /b 1
)
exit /b 0

rem ============================================================
rem  SESSION_LIST - только сессии с журналом, свежие первыми
rem ============================================================
:SESSION_LIST
set "SESS_COUNT=0"
if not exist "%WP_BACKUPS%" exit /b 0
for /f "usebackq delims=" %%d in (`dir /b /ad /o:-n "%WP_BACKUPS%" 2^>nul`) do (
    if exist "%WP_BACKUPS%\%%d\journal.txt" (
        set /a SESS_COUNT+=1
        set "SESS_!SESS_COUNT!=%%d"
    )
)
exit /b 0

rem ============================================================
rem  RP_CLEAR - сброс результатов прошлого вызова.
rem  Без этого упавший PS оставит старые RP_CREATED=1
rem  и мы отрапортуем успех, которого не было.
rem ============================================================
:RP_CLEAR
set "RP_CREATED="
set "RP_SEQ="
set "RP_REASON="
set "RP_NEEDS_VSS="
set "RP_BLOCKED_POLICY="
set "RP_CHECKPOINT_ERROR="
set "RP_ENABLE_ERROR="
set "RP_COUNT_BEFORE="
set "RP_COUNT_AFTER="
set "RP_DRIVE_ENABLED="
exit /b 0

rem ============================================================
rem  RP_REQUIRE  %1 имя режима
rem  0 = точка есть или осознанный обход, 1 = режим НЕ запускать
rem  Лимит 24ч и DisableSR снимаются обёртками core, значит
rem  попадают в журнал и откатываются вместе со всем остальным.
rem  Службы тоже через SC_SET, а не напрямую из PowerShell.
rem ============================================================
:RP_REQUIRE
set "_MODE=%~1"
if not defined _MODE set "_MODE=SESSION"
if "%WP_DRYRUN%"=="1" (
    call "%WP_LIB%\core.cmd" :PLAN_NOTE "restore point before !_MODE!"
    exit /b 0
)
if "%WP_RP_OK%"=="1" (
    call "%WP_LIB%\core.cmd" :MSG "Точка восстановления уже создана в этой сессии, номер !WP_RP_SEQ!"
    exit /b 0
)
call "%WP_LIB%\core.cmd" :HEAD "Обязательная точка восстановления"
if not exist "%WP_RUN%" mkdir "%WP_RUN%" >nul 2>&1
set "_RPFILE=%WP_RUN%\rp.txt"
set "_RPDESC=WinPulse %WP_VERSION% %STAMP% !_MODE!"

call "%WP_LIB%\core.cmd" :REG_KEY "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
if errorlevel 1 goto :RP_REQUIRE_FAIL
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" "SystemRestorePointCreationFrequency" REG_DWORD "0"
call "%WP_LIB%\core.cmd" :REG_SET "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore" "DisableSR" REG_DWORD "0"

call :RP_CLEAR
if exist "%_RPFILE%" del /f /q "%_RPFILE%" >nul 2>&1
call "%WP_LIB%\core.cmd" :PS_RUN do-restorepoint "%_RPFILE%" "%_RPDESC%"
call :LOAD_KV "%_RPFILE%"
if "!RP_CREATED!"=="1" goto :RP_REQUIRE_OK
if "!RP_NEEDS_VSS!"=="1" goto :RP_REQUIRE_VSS
goto :RP_REQUIRE_FAIL

:RP_REQUIRE_VSS
call "%WP_LIB%\core.cmd" :WARN "VSS или swprv отключены, перевожу в Manual и повторяю попытку"
call "%WP_LIB%\core.cmd" :SC_SET "VSS" "demand"
call "%WP_LIB%\core.cmd" :SC_SET "swprv" "demand"
call :RP_CLEAR
if exist "%_RPFILE%" del /f /q "%_RPFILE%" >nul 2>&1
call "%WP_LIB%\core.cmd" :PS_RUN do-restorepoint "%_RPFILE%" "%_RPDESC%"
call :LOAD_KV "%_RPFILE%"
if "!RP_CREATED!"=="1" goto :RP_REQUIRE_OK
goto :RP_REQUIRE_FAIL

:RP_REQUIRE_OK
set "WP_RP_OK=1"
set "WP_RP_SEQ=!RP_SEQ!"
set "WP_RP_SKIPPED=0"
call "%WP_LIB%\core.cmd" :OK "Точка восстановления создана, номер !RP_SEQ!"
>>"%WP_SESSION_DIR%\session.txt" echo RestorePoint: !RP_SEQ!
exit /b 0

:RP_REQUIRE_FAIL
if /i "!_MODE!"=="MANUAL" (
    call "%WP_LIB%\core.cmd" :WARN "Создание точки восстановления не подтверждено Windows"
    exit /b 1
)
call "%WP_LIB%\core.cmd" :FAIL "Точка восстановления НЕ создана"
if defined RP_REASON call "%WP_LIB%\core.cmd" :MSG "Причина: !RP_REASON!"
if "!RP_BLOCKED_POLICY!"=="1" call "%WP_LIB%\core.cmd" :MSG "System Restore запрещён групповой политикой, снимите политику и повторите"
echo.
echo   Точка восстановления обязательна перед применением твиков.
echo   Журнал WinPulse вернёт отдельные значения, но полный возврат
echo   системы к состоянию "до" без точки невозможен.
echo.
if not "%ADVANCED_MODE%"=="1" (
    call "%WP_LIB%\core.cmd" :MSG "Режим остановлен. Обход доступен только в Advanced Mode."
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    exit /b 1
)
echo   Обход доступен только в Advanced Mode.
echo   Введите SKIP заглавными буквами, чтобы применить твики БЕЗ точки.
echo   Любой другой ввод означает отказ.
echo.
set "_OVR="
set "WP_QUESTION=Ввод: "
call "%WP_LIB%\desktop_io.cmd" input _OVR
if not "!_OVR!"=="SKIP" (
    call "%WP_LIB%\core.cmd" :MSG "Отменено пользователем"
    exit /b 1
)
set "WP_RP_OK=0"
set "WP_RP_SKIPPED=1"
call "%WP_LIB%\core.cmd" :WARN "ОБХОД: твики применяются без точки восстановления"
>>"%SESSION_LOG%" echo [%TIME%] [OVERRIDE] restore point skipped by user in Advanced Mode
>>"%WP_SESSION_DIR%\session.txt" echo RestorePoint: SKIPPED_BY_USER
exit /b 0

rem ============================================================
rem  RP_MENU - список точек и запуск штатного восстановления.
rem  Выбор точки не автоматизируем: rstrui делает это сам,
rem  подменять его GUI - значит сломать проверку целостности.
rem ============================================================
:RP_MENU
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == ТОЧКИ ВОССТАНОВЛЕНИЯ ==
echo.
if not exist "%WP_RUN%" mkdir "%WP_RUN%" >nul 2>&1
set "_RPF=%WP_RUN%\rplist.txt"
set "RP_COUNT="
set "RP_SR_DISABLED="
if exist "%_RPF%" del /f /q "%_RPF%" >nul 2>&1
call "%WP_LIB%\core.cmd" :PS_RUN get-restorepoints "%_RPF%"
call :LOAD_KV "%_RPF%"
if not defined RP_COUNT set "RP_COUNT=0"
if "!RP_SR_DISABLED!"=="1" echo   [WARN] System Restore отключён в конфигурации системы
if "!RP_COUNT!"=="0" (
    echo   Точек восстановления нет.
    echo   Создайте хотя бы одну перед применением твиков.
) else (
    echo   Найдено точек: !RP_COUNT!
    echo.
    for /l %%i in (1,1,!RP_COUNT!) do (
        if %%i leq 20 echo   [%%i] !RP_%%i_SEQ!  !RP_%%i_DATE!  !RP_%%i_DESC!
    )
    if !RP_COUNT! gtr 20 echo   ... показаны первые 20
)
echo.
echo   [C] Создать точку восстановления
echo   [R] Открыть восстановление системы
echo   [0] Назад
echo.
set "WP_QUESTION=Ваш выбор: "
call "%WP_LIB%\desktop_io.cmd" choice RC0
if errorlevel 3 exit /b 0
if errorlevel 2 goto :RP_MANUAL
start "" rstrui.exe
call "%WP_LIB%\core.cmd" :MSG "Запущен rstrui.exe, выберите точку в окне мастера"
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
exit /b 0


rem ============================================================
:RP_MANUAL
call "%WP_LIB%\core.cmd" :MSG "При необходимости движок включит защиту системного тома и подготовит службы VSS."
call "%WP_LIB%\core.cmd" :CONFIRM "Создать точку восстановления" N
if errorlevel 1 goto :RP_MENU
call :RP_REQUIRE "MANUAL"
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :RP_MENU

rem  ЧАСТЬ 2/4. Обёртки PS-мутаций.
rem  Единственный разрешённый путь менять MMAgent, Defender,
rem  ветки под TrustedInstaller, Appx, гибернацию, Reserved
rem  Storage и схему питания из модулей твиков.
rem
rem  Прямые вызовы PS_RUN do-* из твиков ЗАПРЕЩЕНЫ:
rem  изменение пройдёт мимо журнала и откат его не увидит.
rem
rem  Схема каждой обёртки:
rem    снимок -> журнал -> идемпотентность -> мутация ->
rem    верификация ФАКТА -> ровно один инкремент счётчика
rem
rem  Сентинел -1 в журнале = прежнее состояние неизвестно,
rem  replay обязан пропустить запись и показать вручную.
rem ============================================================

rem ============================================================
rem  MM_CLEAR - сброс результатов прошлого вызова MMAgent
rem ============================================================
:MM_CLEAR
set "MM_AVAILABLE="
set "MM_FEATURE="
set "MM_REQUESTED="
set "MM_APPLIED="
set "MM_BEFORE="
set "MM_ACTUAL="
set "MM_NEED_REBOOT="
set "MM_REBOOT_HINT="
set "MM_ERROR="
set "MM_MEMORYCOMPRESSION="
set "MM_PAGECOMBINING="
set "MM_APPLAUNCHPREFETCHING="
set "MM_APPLICATIONPRELAUNCH="
set "MM_OPERATIONAPI="
set "MM_MAXOPERATIONAPIFILES="
exit /b 0

rem ============================================================
rem  MM_SET  %1 feature  %2 state (1=вкл, 0=выкл)
rem  feature: memorycompression pagecombining
rem           applaunchprefetching applicationprelaunch operationapi
rem ============================================================
:MM_SET
set "_F=%~1"
set "_S=%~2"
if not defined _F (
    call "%WP_LIB%\core.cmd" :FAIL "MM_SET: feature не задан"
    exit /b 1
)
if /i "!_F!"=="memorytrim" (
    call "%WP_LIB%\core.cmd" :FAIL "MM_SET: параметра MemoryTrim у MMAgent не существует"
    exit /b 1
)
set "_FU="
if /i "!_F!"=="memorycompression"    (set "_F=memorycompression"    & set "_FU=MEMORYCOMPRESSION")
if /i "!_F!"=="pagecombining"        (set "_F=pagecombining"        & set "_FU=PAGECOMBINING")
if /i "!_F!"=="applaunchprefetching" (set "_F=applaunchprefetching" & set "_FU=APPLAUNCHPREFETCHING")
if /i "!_F!"=="applicationprelaunch" (set "_F=applicationprelaunch" & set "_FU=APPLICATIONPRELAUNCH")
if /i "!_F!"=="operationapi"         (set "_F=operationapi"         & set "_FU=OPERATIONAPI")
if not defined _FU (
    call "%WP_LIB%\core.cmd" :FAIL "MM_SET: неизвестный параметр !_F!"
    exit /b 1
)
if not "!_S!"=="0" if not "!_S!"=="1" (
    call "%WP_LIB%\core.cmd" :FAIL "MM_SET: state должен быть 0 или 1"
    exit /b 1
)
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo MM_SET^|!_F!^|!_S!
    echo     [PLAN] mmagent !_F! = !_S!
    set /a WP_OP_PLAN+=1
    exit /b 0
)
set "_MF=%WP_RUN%\mmagent.txt"
call :MM_CLEAR
if exist "%_MF%" del /f /q "%_MF%" >nul 2>&1
call "%WP_LIB%\core.cmd" :PS_RUN get-mmagent "%_MF%"
call :LOAD_KV "%_MF%"
if not "!MM_AVAILABLE!"=="1" (
    call "%WP_LIB%\core.cmd" :SKIP "MMAgent API недоступен, !_F! не тронут"
    exit /b 0
)
set "_OLD=!MM_%_FU%!"
if not defined _OLD (
    call "%WP_LIB%\core.cmd" :WARN "состояние !_F! неизвестно, откат будет ограничен"
    >>"%JOURNAL%" echo MMAGENT^|!_F!^|-1
) else (
    >>"%JOURNAL%" echo MMAGENT^|!_F!^|!_OLD!
)
if "!_OLD!"=="!_S!" (
    set /a WP_OP_OK+=1
    >>"%SESSION_LOG%" echo [%TIME%] [SAME] MMAgent !_F! = !_S!
    exit /b 0
)
call :MM_CLEAR
if exist "%_MF%" del /f /q "%_MF%" >nul 2>&1
call "%WP_LIB%\core.cmd" :PS_RUN do-mmagent "%_MF%" "!_F!" "!_S!"
call :LOAD_KV "%_MF%"
if "!MM_APPLIED!"=="1" (
    if "!MM_REBOOT_HINT!"=="1" set "WP_REBOOT_REQUIRED=1"
    call "%WP_LIB%\core.cmd" :OK "MMAgent !_F! = !_S!"
    exit /b 0
)
if "!MM_NEED_REBOOT!"=="1" (
    set "WP_REBOOT_REQUIRED=1"
    set /a WP_OP_OK+=1
    call "%WP_LIB%\core.cmd" :WARN "MMAgent !_F! = !_S! принят, вступит в силу после перезагрузки"
    exit /b 0
)
call "%WP_LIB%\core.cmd" :FAIL "MMAgent !_F!: !MM_ERROR!"
exit /b 1

rem ============================================================
rem  DEF_CLEAR - сброс снимка Defender, включая индексные ключи.
rem  Без чистки индексов хвост прошлого длинного списка дал бы
rem  ложное "исключение уже есть" и твик молча не применился бы.
rem ============================================================
:DEF_CLEAR
if defined DEF_EXCL_PATH_COUNT (
    for /l %%i in (1,1,%DEF_EXCL_PATH_COUNT%) do set "DEF_EXCL_PATH_%%i="
)
if defined DEF_EXCL_PROC_COUNT (
    for /l %%i in (1,1,%DEF_EXCL_PROC_COUNT%) do set "DEF_EXCL_PROC_%%i="
)
if defined DEF_EXCL_EXT_COUNT (
    for /l %%i in (1,1,%DEF_EXCL_EXT_COUNT%) do set "DEF_EXCL_EXT_%%i="
)
set "DEF_EXCL_PATH_COUNT="
set "DEF_EXCL_PROC_COUNT="
set "DEF_EXCL_EXT_COUNT="
set "DEF_EXCL_PATH_TRUNCATED="
set "DEF_EXCL_PROC_TRUNCATED="
set "DEF_AVAILABLE="
set "DEF_APPLIED="
set "DEF_BEFORE="
set "DEF_ACTUAL="
set "DEF_ACTION="
set "DEF_VALUE="
set "DEF_TAMPER="
set "DEF_TAMPER_BLOCKED="
set "DEF_ERROR="
set "DEF_RT_ENABLED="
set "DEF_RT_DISABLED="
set "DEF_SCRIPT_DISABLED="
exit /b 0

rem ============================================================
rem  DEF_SNAP - свежий снимок Defender. 0 = API доступен
rem ============================================================
:DEF_SNAP
set "_DF=%WP_RUN%\defender.txt"
if not exist "%WP_RUN%" mkdir "%WP_RUN%" >nul 2>&1
call :DEF_CLEAR
if exist "%_DF%" del /f /q "%_DF%" >nul 2>&1
call "%WP_LIB%\core.cmd" :PS_RUN get-defender "%_DF%"
call :LOAD_KV "%_DF%"
if not "!DEF_AVAILABLE!"=="1" exit /b 1
exit /b 0

rem ============================================================
rem  DEF_EXCL  %1 path|proc  %2 значение  %3 add|del
rem  Присутствие проверяем по снимку с нормализацией хвостового
rem  слэша: Defender его дописывает, наивное сравнение строк
rem  давало бы вечное "добавлено" при каждом прогоне.
rem ============================================================
:DEF_EXCL
set "_K=%~1"
set "_V=%~2"
set "_A=%~3"
set "_PFX="
set "_CNTVAR="
set "_ACT="
if /i "!_K!"=="path" (set "_K=path" & set "_PFX=DEF_EXCL_PATH" & set "_CNTVAR=DEF_EXCL_PATH_COUNT")
if /i "!_K!"=="proc" (set "_K=proc" & set "_PFX=DEF_EXCL_PROC" & set "_CNTVAR=DEF_EXCL_PROC_COUNT")
if not defined _PFX (
    call "%WP_LIB%\core.cmd" :FAIL "DEF_EXCL: kind должен быть path или proc"
    exit /b 1
)
if not defined _V (
    call "%WP_LIB%\core.cmd" :FAIL "DEF_EXCL: пустое значение"
    exit /b 1
)
if /i "!_A!"=="add" (set "_A=add" & set "_ACT=addexcl!_K!")
if /i "!_A!"=="del" (set "_A=del" & set "_ACT=removeexcl!_K!")
if not defined _ACT (
    call "%WP_LIB%\core.cmd" :FAIL "DEF_EXCL: action должен быть add или del"
    exit /b 1
)
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo DEF_EXCL^|!_K!^|!_A!^|!_V!
    echo     [PLAN] defender excl !_A! !_K! !_V!
    set /a WP_OP_PLAN+=1
    exit /b 0
)
call :DEF_SNAP
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :SKIP "Defender API недоступен, исключение !_V! не тронуто"
    exit /b 0
)
if "!DEF_EXCL_PATH_TRUNCATED!"=="1" call "%WP_LIB%\core.cmd" :WARN "список путей Defender обрезан, снимок частичный"
if "!DEF_EXCL_PROC_TRUNCATED!"=="1" call "%WP_LIB%\core.cmd" :WARN "список процессов Defender обрезан, снимок частичный"
set "_TGT=!_V!"
if /i "!_K!"=="path" if "!_TGT:~-1!"=="\" set "_TGT=!_TGT:~0,-1!"
set "_HAD=0"
set "_CNT=!%_CNTVAR%!"
if not defined _CNT set "_CNT=0"
for /l %%i in (1,1,!_CNT!) do (
    set "_CUR=!%_PFX%_%%i!"
    if /i "!_K!"=="path" if "!_CUR:~-1!"=="\" set "_CUR=!_CUR:~0,-1!"
    if /i "!_CUR!"=="!_TGT!" set "_HAD=1"
)
if "!_HAD!"=="1" (
    >>"%JOURNAL%" echo DEFEXCL^|!_K!^|!_V!^|PRESENT
) else (
    >>"%JOURNAL%" echo DEFEXCL^|!_K!^|!_V!^|ABSENT
)
if "!_A!"=="add" if "!_HAD!"=="1" (
    set /a WP_OP_OK+=1
    >>"%SESSION_LOG%" echo [%TIME%] [SAME] DEFEXCL !_K! !_V!
    exit /b 0
)
if "!_A!"=="del" if "!_HAD!"=="0" (
    call "%WP_LIB%\core.cmd" :SKIP "исключение Defender уже отсутствует: !_V!"
    exit /b 0
)
call :DEF_CLEAR
if exist "%_DF%" del /f /q "%_DF%" >nul 2>&1
call "%WP_LIB%\core.cmd" :PS_RUN do-defender "%_DF%" "!_ACT!" "!_V!"
call :LOAD_KV "%_DF%"
if "!DEF_APPLIED!"=="1" (
    call "%WP_LIB%\core.cmd" :OK "Defender excl !_A! !_K! !_V!"
    exit /b 0
)
if "!DEF_TAMPER_BLOCKED!"=="1" (
    call "%WP_LIB%\core.cmd" :FAIL "исключение !_V! блокирует Tamper Protection"
    exit /b 1
)
call "%WP_LIB%\core.cmd" :FAIL "Defender excl !_V!: !DEF_ERROR!"
exit /b 1

rem ============================================================
rem  DEF_SET  %1 rt|script  %2 state (1=защита ВКЛ, 0=ВЫКЛ)
rem  Guards и подтверждения живут в tweaks_exp, обёртка тупая.
rem ============================================================
:DEF_SET
set "_W=%~1"
set "_S=%~2"
if /i "!_W!"=="rt" set "_W=rt"
if /i "!_W!"=="script" set "_W=script"
if not "!_W!"=="rt" if not "!_W!"=="script" (
    call "%WP_LIB%\core.cmd" :FAIL "DEF_SET: цель должна быть rt или script"
    exit /b 1
)
if not "!_S!"=="0" if not "!_S!"=="1" (
    call "%WP_LIB%\core.cmd" :FAIL "DEF_SET: state должен быть 0 или 1"
    exit /b 1
)
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo DEF_SET^|!_W!^|!_S!
    echo     [PLAN] defender !_W! protection = !_S!
    set /a WP_OP_PLAN+=1
    exit /b 0
)
call :DEF_SNAP
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :SKIP "Defender API недоступен, !_W! не тронут"
    exit /b 0
)
set "_OLD="
if "!_W!"=="rt" set "_OLD=!DEF_RT_ENABLED!"
if "!_W!"=="script" if defined DEF_SCRIPT_DISABLED set /a "_OLD=1-DEF_SCRIPT_DISABLED"
if not defined _OLD (
    call "%WP_LIB%\core.cmd" :WARN "состояние Defender !_W! неизвестно, откат ограничен"
    >>"%JOURNAL%" echo DEFSTATE^|!_W!^|-1
) else (
    >>"%JOURNAL%" echo DEFSTATE^|!_W!^|!_OLD!
)
if "!_OLD!"=="!_S!" (
    set /a WP_OP_OK+=1
    >>"%SESSION_LOG%" echo [%TIME%] [SAME] DEFSTATE !_W! = !_S!
    exit /b 0
)
call :DEF_CLEAR
if exist "%_DF%" del /f /q "%_DF%" >nul 2>&1
call "%WP_LIB%\core.cmd" :PS_RUN do-defender "%_DF%" "!_W!" "!_S!"
call :LOAD_KV "%_DF%"
if "!DEF_APPLIED!"=="1" (
    if "!_S!"=="0" set "WP_DEF_PROTECTION_REDUCED=1"
    call "%WP_LIB%\core.cmd" :OK "Defender !_W! protection = !_S!"
    exit /b 0
)
if "!DEF_TAMPER_BLOCKED!"=="1" (
    call "%WP_LIB%\core.cmd" :FAIL "Defender !_W! блокирует Tamper Protection, снимите вручную в Безопасности Windows"
    exit /b 1
)
call "%WP_LIB%\core.cmd" :FAIL "Defender !_W!: !DEF_ERROR!"
exit /b 1

rem ============================================================
rem  REGACL_SET  %1 key  %2 value  %3 type  %4 data
rem  Ветки под TrustedInstaller: Enum\PCI (MSI),
rem  WindowsRuntime\ActivatableClassId (GameBar).
rem  Журнал именно REGACL, не REG: обычный reg add при откате
rem  упрётся в Access Denied, replay пойдёт через do-regacl.
rem ============================================================
:REGACL_SET
set "_K=%~1"
set "_V=%~2"
set "_T=%~3"
set "_D=%~4"
if not defined _K (
    call "%WP_LIB%\core.cmd" :FAIL "REGACL_SET: пустой ключ"
    exit /b 1
)
if not defined _V (
    call "%WP_LIB%\core.cmd" :FAIL "REGACL_SET: пустое имя значения"
    exit /b 1
)
if not defined _T (
    call "%WP_LIB%\core.cmd" :FAIL "REGACL_SET: пустой тип"
    exit /b 1
)
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo REGACL_SET^|!_K!^|!_V!^|!_T!^|!_D!
    echo     [PLAN] regacl !_V! = !_D!
    set /a WP_OP_PLAN+=1
    exit /b 0
)
call "%WP_LIB%\core.cmd" :SNAP_REG "!_K!" "!_V!" "!_T!" "!_D!" REGACL
if errorlevel 1 exit /b 1
if "!_SNAP_STATE!"=="SAME" (
    set /a WP_OP_SKIP+=1
    >>"%SESSION_LOG%" echo [%TIME%] [SAME] REGACL !_K! :: !_V!
    exit /b 0
)
set "_AF=%WP_RUN%\regacl.txt"
if exist "%_AF%" del /f /q "%_AF%" >nul 2>&1
set "REGACL_WRITTEN="
set "REGACL_ERROR="
set "REGACL_OWNER_BEFORE="
set "REGACL_OWNER_RESTORED="
set "REGACL_ACL_RESTORED="
set "REGACL_RESTORE_ERROR="
set "REGACL_READBACK="
set "REGACL_CREATED_KEYS="
call "%WP_LIB%\core.cmd" :PS_RUN do-regacl "%_AF%" "!_K!" "!_V!" "!_T!" "!_D!"
call :LOAD_KV "%_AF%"
if not "!REGACL_WRITTEN!"=="1" (
    call "%WP_LIB%\core.cmd" :FAIL "regacl !_K! :: !_V! - !REGACL_ERROR!"
    exit /b 1
)
>>"%SESSION_LOG%" echo [%TIME%] [REGACL] !_K! :: !_V! readback=!REGACL_READBACK! owner=!REGACL_OWNER_BEFORE!
if not "!REGACL_OWNER_RESTORED!"=="1" call "%WP_LIB%\core.cmd" :WARN "владелец ветки не возвращён: !_K! - проверьте вручную"
if not "!REGACL_ACL_RESTORED!"=="1" call "%WP_LIB%\core.cmd" :WARN "временное правило ACL не снято: !_K! - проверьте вручную"
call "%WP_LIB%\core.cmd" :OK "regacl !_V! = !_D!"
exit /b 0

rem ============================================================
rem  APPX_REMOVE  %1 selective|full
rem  Считает РОВНО по одному результату на паттерн, поэтому
rem  BLOCK_END видит 6 или 13 операций, а не одну кашу.
rem  Удаление только для целевого SID, provisioned не трогаем.
rem ============================================================
:APPX_REMOVE
set "_AM=%~1"
set "_AN="
if /i "!_AM!"=="selective" (set "_AM=selective" & set "_AN=6")
if /i "!_AM!"=="full" (set "_AM=full" & set "_AN=13")
if not defined _AN (
    call "%WP_LIB%\core.cmd" :FAIL "APPX_REMOVE: mode должен быть selective или full"
    exit /b 1
)
if "%WP_DRYRUN%"=="1" (
    for /l %%i in (1,1,!_AN!) do call "%WP_LIB%\core.cmd" :PLAN "appx !_AM! pattern %%i"
    exit /b 0
)
if defined APPX_PATTERNS (
    for /l %%i in (1,1,%APPX_PATTERNS%) do (
        set "APPX_P%%i_PATTERN="
        set "APPX_P%%i_FOUND="
        set "APPX_P%%i_REMOVED="
        set "APPX_P%%i_FAILED="
        set "APPX_P%%i_SKIPPED="
    )
)
if defined APPX_LISTED (
    for /l %%i in (1,1,%APPX_LISTED%) do (
        set "APPX_PKG_%%i_NAME="
        set "APPX_PKG_%%i_FAMILY="
        set "APPX_PKG_%%i_LOC="
    )
)
set "APPX_PATTERNS="
set "APPX_LISTED="
set "APPX_FOUND="
set "APPX_REMOVED="
set "APPX_FAILED="
set "APPX_SKIPPED="
set "APPX_LAST_ERROR="
set "_AXF=%WP_RUN%\appx.txt"
if exist "%_AXF%" del /f /q "%_AXF%" >nul 2>&1
set "_ASID="
if defined CONSOLE_SID set "_ASID=!CONSOLE_SID!"
call "%WP_LIB%\core.cmd" :PS_RUN do-appx "%_AXF%" "!_AM!" "!_ASID!"
call :LOAD_KV "%_AXF%"
if not defined APPX_PATTERNS (
    for /l %%i in (1,1,!_AN!) do call "%WP_LIB%\core.cmd" :FAIL "appx pattern %%i: PS-движок не ответил"
    exit /b 1
)
call "%WP_LIB%\core.cmd" :IRREVERSIBLE "appx removal mode=!_AM!"
if defined APPX_LISTED if !APPX_LISTED! gtr 0 (
    >"%WP_SESSION_DIR%\appx_removed.txt" echo WinPulse appx removed %STAMP%
    >>"%WP_SESSION_DIR%\appx_removed.txt" echo Reinstall: Add-AppxPackage -Register {loc}\AppxManifest.xml -DisableDevelopmentMode
    for /l %%i in (1,1,!APPX_LISTED!) do (
        >>"%WP_SESSION_DIR%\appx_removed.txt" echo !APPX_PKG_%%i_NAME!
        >>"%WP_SESSION_DIR%\appx_removed.txt" echo   family=!APPX_PKG_%%i_FAMILY!
        >>"%WP_SESSION_DIR%\appx_removed.txt" echo   loc=!APPX_PKG_%%i_LOC!
    )
)
for /l %%i in (1,1,!APPX_PATTERNS!) do (
    set "_AP=!APPX_P%%i_PATTERN!"
    set "_APF=!APPX_P%%i_FAILED!"
    set "_APR=!APPX_P%%i_REMOVED!"
    if not defined _APF set "_APF=0"
    if not defined _APR set "_APR=0"
    if !_APF! gtr 0 (
        call "%WP_LIB%\core.cmd" :FAIL "appx !_AP!: ошибок !_APF!"
    ) else if !_APR! gtr 0 (
        call "%WP_LIB%\core.cmd" :OK "appx !_AP!: удалено !_APR!"
    ) else (
        call "%WP_LIB%\core.cmd" :SKIP "appx !_AP!: не установлен"
    )
)
if not "!APPX_PATTERNS!"=="!_AN!" call "%WP_LIB%\core.cmd" :WARN "appx: паттернов !APPX_PATTERNS!, ожидалось !_AN!"
exit /b 0

rem ============================================================
rem  HIBER_SET  %1 0|1
rem  powercfg /h меняет HibernateEnabled И удаляет hiberfil.sys.
rem  Журнал REG вернул бы только реестр, файл бы не вернулся.
rem ============================================================
:HIBER_SET
set "_HS=%~1"
if not "!_HS!"=="0" if not "!_HS!"=="1" (
    call "%WP_LIB%\core.cmd" :FAIL "HIBER_SET: state должен быть 0 или 1"
    exit /b 1
)
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo HIBER_SET^|!_HS!
    echo     [PLAN] hibernation = !_HS!
    set /a WP_OP_PLAN+=1
    exit /b 0
)
set "_HL="
set "_HD="
set "_HO=1"
for /f "tokens=* delims=" %%L in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Power" /v HibernateEnabled 2^>nul') do set "_HL=%%L"
if defined _HL (
    set "_HR=!_HL:*REG_=REG_!"
    for /f "tokens=1,*" %%a in ("!_HR!") do set "_HD=%%b"
    if defined _HD set /a "_HO=!_HD!" >nul 2>&1
)
>>"%JOURNAL%" echo HIBER^|!_HO!
if "!_HS!"=="0" (powercfg /h off >nul 2>&1) else (powercfg /h on >nul 2>&1)
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :FAIL "powercfg /h !_HS!"
    exit /b 1
)
set "WP_REBOOT_REQUIRED=1"
call "%WP_LIB%\core.cmd" :OK "гибернация = !_HS!"
exit /b 0

rem ============================================================
rem  RESERVED_SET  %1 0|1
rem  DISM, не реестр. Вывод локализован: если состояние не
rem  распознано, пишем UNKNOWN и откат пропустит честно.
rem ============================================================
:RESERVED_SET
set "_RS=%~1"
if not "!_RS!"=="0" if not "!_RS!"=="1" (
    call "%WP_LIB%\core.cmd" :FAIL "RESERVED_SET: state должен быть 0 или 1"
    exit /b 1
)
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo RESERVED_SET^|!_RS!
    echo     [PLAN] reserved storage = !_RS!
    set /a WP_OP_PLAN+=1
    exit /b 0
)
set "_RF=%WP_RUN%\reserved.txt"
if exist "%_RF%" del /f /q "%_RF%" >nul 2>&1
DISM /Online /Get-ReservedStorageState > "%_RF%" 2>&1
set "_RO=UNKNOWN"
findstr /i /c:"Disabled" "%_RF%" >nul 2>&1
if not errorlevel 1 set "_RO=0"
findstr /i /c:"Enabled" "%_RF%" >nul 2>&1
if not errorlevel 1 set "_RO=1"
findstr /i /c:"отключено" "%_RF%" >nul 2>&1
if not errorlevel 1 set "_RO=0"
findstr /i /c:"включено" "%_RF%" >nul 2>&1
if not errorlevel 1 set "_RO=1"
>>"%JOURNAL%" echo RESERVED^|!_RO!
if "!_RO!"=="UNKNOWN" call "%WP_LIB%\core.cmd" :WARN "прежнее состояние Reserved Storage не распознано, откат потребует ручной проверки"
if "!_RS!"=="0" (
    DISM /Online /Set-ReservedStorageState /State:Disabled >nul 2>&1
) else (
    DISM /Online /Set-ReservedStorageState /State:Enabled >nul 2>&1
)
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :FAIL "DISM ReservedStorageState = !_RS!"
    exit /b 1
)
set "WP_REBOOT_REQUIRED=1"
call "%WP_LIB%\core.cmd" :OK "Reserved Storage = !_RS!"
exit /b 0

rem ============================================================
rem  BCD_SUSPEND - приостановка BitLocker на одну перезагрузку.
rem  Правки BCD меняют измерения TPM, без suspend система
rem  встретит экраном ввода ключа восстановления.
rem  Это предохранитель, а не твик: счётчики не трогаем.
rem  0 = можно продолжать, 1 = пользователь отказался
rem ============================================================
:BCD_SUSPEND
if /i not "!BITLOCKER_STATUS!"=="Enabled" exit /b 0
if "%WP_BCD_SUSPENDED%"=="1" exit /b 0
if "%WP_DRYRUN%"=="1" (
    call "%WP_LIB%\core.cmd" :PLAN_NOTE "suspend BitLocker for one reboot"
    exit /b 0
)
call "%WP_LIB%\core.cmd" :WARN "BitLocker включён, правки BCD меняют измерения TPM"
call "%WP_LIB%\core.cmd" :MSG "Защита приостановится на одну перезагрузку и включится сама"
call "%WP_LIB%\core.cmd" :MSG "Ключ восстановления: manage-bde -protectors %SYS_DRIVE% -get"
call "%WP_LIB%\core.cmd" :CONFIRM "Приостановить защиту BitLocker на 1 перезагрузку" Y
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :WARN "без приостановки BitLocker может запросить ключ при загрузке"
    exit /b 1
)
manage-bde -protectors -disable %SYS_DRIVE% -RebootCount 1 >nul 2>&1
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :FAIL "manage-bde suspend %SYS_DRIVE%"
    exit /b 1
)
>>"%JOURNAL%" echo BCDSUSPEND^|%SYS_DRIVE%
set "WP_BCD_SUSPENDED=1"
call "%WP_LIB%\core.cmd" :OK "BitLocker приостановлен на одну перезагрузку"
exit /b 0

rem ============================================================
rem  POWER_ULTIMATE - 2 операции: создать схему, активировать.
rem  Если Ultimate уже есть, повторно копии не плодим.
rem  Порядок журнала: POWERNEW, потом POWERSCHEME.
rem  Reverse-replay сначала вернёт прежний план, потом удалит
rem  созданный - иначе powercfg откажется удалять активный.
rem ============================================================
:POWER_ULTIMATE
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo POWER_ULTIMATE^|create
    >>"%PLAN_LOG%" echo POWER_ULTIMATE^|activate
    echo     [PLAN] Ultimate Performance: create + activate
    set /a WP_OP_PLAN+=2
    exit /b 0
)
set "_UG=e9a42b02-d5df-448d-aa00-03f14749eb61"
set "_ULF=%WP_RUN%\powerlist.txt"
if not exist "%WP_RUN%" mkdir "%WP_RUN%" >nul 2>&1
if exist "%_ULF%" del /f /q "%_ULF%" >nul 2>&1
powercfg /list > "%_ULF%" 2>&1
set "_UNEW="
findstr /i /c:"%_UG%" "%_ULF%" >nul 2>&1
if not errorlevel 1 (
    set "_UNEW=%_UG%"
    call "%WP_LIB%\core.cmd" :SKIP "схема Ultimate Performance уже существует"
    goto :PU_ACTIVATE
)
set "_UL="
for /f "tokens=* delims=" %%L in ('powercfg -duplicatescheme %_UG% 2^>nul') do set "_UL=%%L"
if not defined _UL (
    call "%WP_LIB%\core.cmd" :FAIL "powercfg -duplicatescheme Ultimate Performance"
    set /a WP_OP_SKIP+=1
    exit /b 1
)
set "_UR=!_UL:*: =!"
for /f "tokens=1" %%g in ("!_UR!") do set "_UNEW=%%g"
if not defined _UNEW (
    call "%WP_LIB%\core.cmd" :FAIL "GUID новой схемы не распознан"
    set /a WP_OP_SKIP+=1
    exit /b 1
)
if not "!_UNEW:~8,1!"=="-" (
    call "%WP_LIB%\core.cmd" :FAIL "результат не похож на GUID: !_UNEW!"
    set /a WP_OP_SKIP+=1
    exit /b 1
)
>>"%JOURNAL%" echo POWERNEW^|!_UNEW!
call "%WP_LIB%\core.cmd" :OK "схема Ultimate Performance создана: !_UNEW!"
:PU_ACTIVATE
set "_UOL="
set "_UOG="
for /f "tokens=* delims=" %%L in ('powercfg /getactivescheme 2^>nul') do set "_UOL=%%L"
if defined _UOL (
    set "_UOR=!_UOL:*: =!"
    for /f "tokens=1" %%g in ("!_UOR!") do set "_UOG=%%g"
)
if defined _UOG (
    if "!_UOG:~8,1!"=="-" >>"%JOURNAL%" echo POWERSCHEME^|!_UOG!
)
if not defined _UOG call "%WP_LIB%\core.cmd" :WARN "прежний активный план не распознан, откат схемы будет ограничен"
powercfg /setactive !_UNEW! >nul 2>&1
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :FAIL "powercfg /setactive Ultimate Performance"
    exit /b 1
)
set "_UCL="
for /f "tokens=* delims=" %%L in ('powercfg /getactivescheme 2^>nul') do set "_UCL=%%L"
echo %_UCL%| findstr /i /c:"%_UNEW%" >nul 2>&1
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :FAIL "Ultimate Performance не стал активным планом"
    exit /b 1
)
call "%WP_LIB%\core.cmd" :OK "Ultimate Performance активирован"
exit /b 0


rem ============================================================
rem  ЧАСТЬ 3/4. Интерфейс и оркестрация отката.
rem
rem  Дополнительно к контракту:
rem    RB_OK RB_FAIL RB_SKIP RB_IRREV   счётчики отката
rem    RB_LOG                           лог конкретного отката
rem
rem  Внутреннее состояние:
rem    _RB_STAMP _RB_JOURNAL _RB_SRC _RB_FILTER _RB_N _RB_L_n
rem
rem  Требует из части 4/4: :CLASSIFY  :REPLAY_LINE
rem  Откат НИКОГДА не пишет в журнал сессии - иначе каждый
rem  откат плодил бы записи для следующего отката.
rem ============================================================

rem ============================================================
rem  ROLLBACK_MENU - вход из главного меню
rem ============================================================
:ROLLBACK_MENU
call "%WP_LIB%\core.cmd" :HEAD "Откат изменений"
call :RB_PICK_SESSION
if errorlevel 1 exit /b 0
goto :RB_GROUPS

rem ============================================================
rem  RB_PICK_SESSION - 0 = текущая сессия, N = архивная.
rem  Валидация обязательна: в 6.4 при пустом списке печаталось
rem  "[OK] Restored" и предлагалась перезагрузка.
rem ============================================================
:RB_PICK_SESSION
call :SESSION_LIST
if "!SESS_COUNT!"=="0" (
    call "%WP_LIB%\core.cmd" :WARN "Журналов отката нет, применять было нечего"
    call "%WP_LIB%\core.cmd" :PAUSE_SAFE
    exit /b 1
)
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == ВЫБОР СЕССИИ ДЛЯ ОТКАТА ==
echo.
echo   [0] Текущая сессия %STAMP%
echo.
echo   Архивные сессии, свежие первыми:
for /l %%i in (1,1,!SESS_COUNT!) do (
    if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:session^|%%i^|!SESS_%%i!) else if %%i leq 15 echo   [%%i] !SESS_%%i!
)
if !SESS_COUNT! gtr 15 echo   ... показаны первые 15
echo.
set "_RBSEL="
set "WP_QUESTION=Номер, Enter = отмена: "
call "%WP_LIB%\desktop_io.cmd" input _RBSEL
if not defined _RBSEL exit /b 1
echo %_RBSEL%| findstr /r "^[0-9][0-9]*$" >nul 2>&1
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :WARN "Нужно целое число"
    goto :RB_PICK_SESSION
)
if not "%_RBSEL:~2%"=="" (
    call "%WP_LIB%\core.cmd" :WARN "Слишком большое число"
    goto :RB_PICK_SESSION
)
if %_RBSEL% equ 0 (
    set "_RB_STAMP=%STAMP%"
    set "_RB_JOURNAL=%JOURNAL%"
    goto :RB_PICK_CHECK
)
if %_RBSEL% gtr !SESS_COUNT! (
    call "%WP_LIB%\core.cmd" :WARN "Сессии с таким номером нет"
    goto :RB_PICK_SESSION
)
set "_RB_STAMP=!SESS_%_RBSEL%!"
set "_RB_JOURNAL=%WP_BACKUPS%\!_RB_STAMP!\journal.txt"
:RB_PICK_CHECK
if not exist "!_RB_JOURNAL!" (
    call "%WP_LIB%\core.cmd" :WARN "Журнал не найден: !_RB_JOURNAL!"
    goto :RB_PICK_SESSION
)
exit /b 0

rem ============================================================
rem  RB_GROUPS - меню групп.
rem  Диспетчер на карте "клавиша:метка", НЕ каскад if errorlevel.
rem  Порядок пар не важен, сдвиг индекса невозможен by design.
rem ============================================================
:RB_GROUPS
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == ОТКАТ ГРУПП ==
echo.
echo   Сессия: !_RB_STAMP!
echo   Журнал: !_RB_JOURNAL!
echo.
echo   [V] Визуал          [N] Сеть           [P] Питание
echo   [B] BCD             [S] Безопасность   [G] Игры и GPU
echo   [M] Память и NTFS   [U] Службы         [W] UX и телеметрия
echo   [A] Автозагрузка и IFEO
echo.
echo   [F] ВСЁ из этой сессии
echo   [L] Показать журнал
echo   [0] Назад
echo.
echo   Одна запись может входить в несколько групп: ключ службы
echo   Tcpip - это и сеть, и службы. Откат по любой из них его вернёт.
echo.
set "_RBKEYS=VNPBSGMUWAFL0"
set "_RBMAP=V:RB_VISUAL N:RB_NETWORK P:RB_POWER B:RB_BCD S:RB_SECURITY G:RB_GAMING M:RB_MEMORY U:RB_SERVICES W:RB_UX A:RB_AUTORUN F:RB_FULL L:RB_SHOWLOG 0:RB_BACK"
set "WP_QUESTION=Ваш выбор: "
call "%WP_LIB%\desktop_io.cmd" choice %_RBKEYS%
set /a "_RBI=%errorlevel%-1"
set "_RBK=!_RBKEYS:~%_RBI%,1!"
set "_RBT="
for %%p in (%_RBMAP%) do (
    for /f "tokens=1,2 delims=:" %%a in ("%%p") do (
        if /i "%%a"=="!_RBK!" set "_RBT=%%b"
    )
)
if not defined _RBT goto :RB_GROUPS
goto :!_RBT!

:RB_VISUAL
call :ROLLBACK_GROUP "V" "!_RB_JOURNAL!"
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :RB_GROUPS


:RB_NETWORK
call :ROLLBACK_GROUP "N" "!_RB_JOURNAL!"
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :RB_GROUPS

:RB_POWER
call :ROLLBACK_GROUP "P" "!_RB_JOURNAL!"
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :RB_GROUPS

:RB_BCD
call :ROLLBACK_GROUP "B" "!_RB_JOURNAL!"
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :RB_GROUPS

:RB_SECURITY
call :ROLLBACK_GROUP "S" "!_RB_JOURNAL!"
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :RB_GROUPS

:RB_GAMING
call :ROLLBACK_GROUP "G" "!_RB_JOURNAL!"
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :RB_GROUPS

:RB_MEMORY
call :ROLLBACK_GROUP "M" "!_RB_JOURNAL!"
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :RB_GROUPS

:RB_SERVICES
call :ROLLBACK_GROUP "U" "!_RB_JOURNAL!"
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :RB_GROUPS

:RB_UX
call :ROLLBACK_GROUP "W" "!_RB_JOURNAL!"
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :RB_GROUPS

:RB_FULL
call :ROLLBACK_FULL "!_RB_JOURNAL!"
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :RB_GROUPS

:RB_SHOWLOG
if defined WP_DESKTOP_TOKEN (echo !WP_DESKTOP_TOKEN!:screen) else cls
echo.
echo == ЖУРНАЛ !_RB_STAMP! ==
echo.
echo   Формат: ТИП^|ключ^|значение^|прежнее состояние
echo   ABSENT значит значения не было, откат его удалит.
echo.
findstr /n "^" "!_RB_JOURNAL!"
echo.
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :RB_GROUPS

:RB_BACK
exit /b 0

rem ============================================================
rem  RB_INIT - счётчики и лог этого отката
rem ============================================================
:RB_INIT
set /a RB_OK=0
set /a RB_FAIL=0
set /a RB_SKIP=0
set /a RB_IRREV=0
if not exist "%WP_LOGS%" mkdir "%WP_LOGS%" >nul 2>&1
set "RB_LOG=%WP_LOGS%\rollback_%STAMP%_%RANDOM%.txt"
>"%RB_LOG%" echo WinPulse %WP_VERSION% rollback log
>>"%RB_LOG%" echo Source: %_RB_SRC%
>>"%RB_LOG%" echo Filter: %_RB_FILTER%
>>"%RB_LOG%" echo Started: %DATE% %TIME%
exit /b 0

rem ============================================================
rem  ROLLBACK_FULL  %1 путь к журналу
rem ============================================================
:ROLLBACK_FULL
set "_RB_SRC=%~1"
if not defined _RB_SRC set "_RB_SRC=%JOURNAL%"
if not exist "%_RB_SRC%" (
    call "%WP_LIB%\core.cmd" :FAIL "Журнал не найден: %_RB_SRC%"
    exit /b 1
)
set "_RB_FILTER="
call :RB_INIT
call "%WP_LIB%\core.cmd" :HEAD "Полный откат сессии"
echo   Все значения из журнала будут возвращены в обратном порядке.
echo   Необратимые операции вернуть нельзя, они будут показаны списком.
echo.
call "%WP_LIB%\core.cmd" :CONFIRM "Начать полный откат" N
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :MSG "Отменено пользователем"
    exit /b 2
)
call :RB_RUN
call :RB_SUMMARY
if !RB_FAIL! gtr 0 exit /b 1
exit /b 0

rem ============================================================
rem  ROLLBACK_GROUP  %1 буква группы  %2 путь к журналу
rem ============================================================
:ROLLBACK_GROUP
set "_RB_GRP=%~1"
set "_RB_SRC=%~2"
if not defined _RB_GRP (
    call "%WP_LIB%\core.cmd" :FAIL "ROLLBACK_GROUP: группа не задана"
    exit /b 1
)
if not defined _RB_SRC set "_RB_SRC=%JOURNAL%"
if not exist "%_RB_SRC%" (
    call "%WP_LIB%\core.cmd" :FAIL "Журнал не найден: %_RB_SRC%"
    exit /b 1
)
set "_RB_FILTER=!_RB_GRP!"
call :RB_INIT
call "%WP_LIB%\core.cmd" :HEAD "Откат группы !_RB_GRP!"
echo   Будут возвращены только записи этой группы, в обратном порядке.
echo.
call "%WP_LIB%\core.cmd" :CONFIRM "Откатить группу !_RB_GRP!" N
if errorlevel 1 (
    call "%WP_LIB%\core.cmd" :MSG "Отменено пользователем"
    exit /b 2
)
call :RB_RUN
call :RB_SUMMARY
if !RB_FAIL! gtr 0 exit /b 1
exit /b 0

rem ============================================================
rem  RB_RUN - загрузка журнала в массив и обход в ОБРАТНОМ порядке.
rem  Reverse принципиален: если одно значение менялось дважды,
rem  последним восстановится самое первое, то есть исходное.
rem
rem  CLASSIFY и REPLAY_LINE вызываются БЕЗ аргументов и читают
rem  _RB_LINE: call повторно раскрывает проценты в аргументе,
rem  и данные REG_EXPAND_SZ вроде %SystemRoot% превратились бы
rem  в реальный путь ещё до обработчика.
rem ============================================================
:RB_RUN
set "_RB_N=0"
for /f "usebackq tokens=* delims=" %%L in ("%_RB_SRC%") do (
    set /a _RB_N+=1
    set "_RB_L_!_RB_N!=%%L"
)
if !_RB_N! equ 0 (
    call "%WP_LIB%\core.cmd" :WARN "Журнал пуст, откатывать нечего"
    exit /b 0
)
>>"%RB_LOG%" echo Entries: !_RB_N!
for /l %%i in (!_RB_N!,-1,1) do (
    set "_RB_LINE=!_RB_L_%%i!"
    set "_RB_DO=1"
    if defined _RB_FILTER (
        call :CLASSIFY
        set "_RB_DO=0"
        if not "!_RB_GRPS!"=="!_RB_GRPS:%_RB_FILTER%=!" set "_RB_DO=1"
    )
    if /i "!_RB_LINE:~0,13!"=="IRREVERSIBLE|" set "_RB_DO=1"
    if "!_RB_DO!"=="1" call :REPLAY_LINE
)
exit /b 0

rem ============================================================
rem  RB_SUMMARY - итог и честный список необратимого
rem ============================================================
:RB_SUMMARY
if defined WP_DESKTOP_TOKEN echo !WP_DESKTOP_TOKEN!:rollback^|!RB_OK!^|!RB_FAIL!^|!RB_SKIP!^|!RB_IRREV!
echo.
echo == ИТОГ ОТКАТА ==
echo.
echo   Возвращено значений: !RB_OK!
echo   Ошибок:              !RB_FAIL!
echo   Пропущено:           !RB_SKIP!
echo   Необратимо:          !RB_IRREV!
echo.
echo   Лог отката: %RB_LOG%
if !RB_IRREV! gtr 0 (
    echo.
    echo   Эти операции вернуть невозможно:
    findstr /b /c:"IRREV" "%RB_LOG%"
    echo.
    echo   Appx переустанавливается через Add-AppxPackage -Register,
    echo   удалённые файлы - только из ваших собственных бэкапов.
)
if !RB_FAIL! gtr 0 call "%WP_LIB%\core.cmd" :WARN "Часть значений вернуть не удалось, смотрите лог отката"
if !RB_SKIP! gtr 0 call "%WP_LIB%\core.cmd" :MSG "Пропущенные записи требуют ручной проверки, они помечены в логе"
if !RB_OK! gtr 0 (
    set "WP_REBOOT_REQUIRED=1"
    call "%WP_LIB%\core.cmd" :MSG "Часть значений применится после перезагрузки или выхода из учётной записи"
)
>>"%SESSION_LOG%" echo [%TIME%] [ROLLBACK] filter=!_RB_FILTER! ok=!RB_OK! fail=!RB_FAIL! skip=!RB_SKIP! irrev=!RB_IRREV!
exit /b 0


rem ============================================================
rem  ЧАСТЬ 4/4. Движок отката.
rem  CLASSIFY и REPLAY_LINE читают _RB_LINE, аргументов не берут:
rem  call повторно раскрывает проценты, и данные REG_EXPAND_SZ
rem  вроде %SystemRoot% превратились бы в путь до обработчика.
rem  Откат пишет ТОЛЬКО в RB_LOG, журнал сессии не трогает.
rem ============================================================

rem ============================================================
rem  Логгеры отката. Ровно один инкремент на запись.
rem ============================================================
:RB_LOG_OK
set "_M=%~1"
set /a RB_OK+=1
echo   [OK] !_M!
>>"%RB_LOG%" echo OK ^| !_M!
exit /b 0

:RB_LOG_FAIL
set "_M=%~1"
set /a RB_FAIL+=1
echo   [FAIL] !_M!
>>"%RB_LOG%" echo FAIL ^| !_M!
exit /b 0

:RB_LOG_SKIP
set "_M=%~1"
set /a RB_SKIP+=1
echo   [SKIP] !_M!
>>"%RB_LOG%" echo SKIP ^| !_M!
exit /b 0

:RB_LOG_IRREV
set "_M=%~1"
set /a RB_IRREV+=1
echo   [IRREV] !_M!
>>"%RB_LOG%" echo IRREV ^| !_M!
exit /b 0

rem ============================================================
rem  RB_HEX2DEC  %1 имя переменной с hex  %2 имя приёмника
rem  powercfg ждёт десятичный индекс, журнал хранит hex.
rem  0xffffffff отдельно: set /a на нём даёт -1.
rem ============================================================
:RB_HEX2DEC
set "_H=!%~1!"
set "%~2="
if not defined _H exit /b 1
if /i "!_H!"=="0xffffffff" (
    set "%~2=4294967295"
    exit /b 0
)
if "!_H!"=="4294967295" (
    set "%~2=4294967295"
    exit /b 0
)
set /a "%~2=!_H!" >nul 2>&1
exit /b 0

rem ============================================================
rem  CLASSIFY - какие группы затрагивает запись журнала.
rem  Одна запись может входить в несколько групп: ключ службы
rem  Tcpip - это и N (сеть), и U (службы). Это правильно.
rem  Подстановка подстрок в cmd регистронезависима.
rem ============================================================
:CLASSIFY
set "_RB_GRPS="
set "_CL=!_RB_LINE!"
if not defined _CL exit /b 0
rem --- V: визуал ---
if not "!_CL:\Themes\Personalize=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!V"
if not "!_CL:\Control Panel\Desktop=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!V"
if not "!_CL:\Explorer\VisualEffects=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!V"
if not "!_CL:\WindowMetrics=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!V"
if not "!_CL:\Windows\DWM=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!V"
if not "!_CL:DisableAcrylicBackgroundOnLogon=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!V"
rem --- N: сеть ---
if not "!_CL:\Services\Tcpip=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!N"
if not "!_CL:\Services\AFD=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!N"
if not "!_CL:\Services\Dnscache=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!N"
if not "!_CL:\Services\Ndu=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!N"
if not "!_CL:\Services\WebClient=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!N"
if not "!_CL:NETSH|=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!N"
if not "!_CL:NetworkThrottlingIndex=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!N"
if not "!_CL:{4d36e972=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!N"
if not "!_CL:\DeliveryOptimization=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!N"
rem --- P: питание ---
if not "!_CL:POWER|=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!P"
if not "!_CL:POWERSCHEME|=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!P"
if not "!_CL:POWERNEW|=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!P"
if not "!_CL:HIBER|=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!P"
if not "!_CL:\Control\Power=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!P"
rem --- B: загрузчик ---
if not "!_CL:BCD|=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!B"
if not "!_CL:BCDSUSPEND|=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!B"
rem --- S: безопасность ---
if not "!_CL:\DeviceGuard=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!S"
if not "!_CL:\Control\Lsa=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!S"
if not "!_CL:FeatureSettingsOverride=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!S"
if not "!_CL:\Windows Defender=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!S"
if not "!_CL:DisableExceptionChainValidation=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!S"
if not "!_CL:DEFEXCL|=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!S"
if not "!_CL:DEFSTATE|=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!S"
if not "!_CL:EncryptPagingFile=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!S"
if not "!_CL:BCD|nx|=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!S"
rem --- A: автозагрузка ---
if not "!_CL:\CurrentVersion\Run=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!A"
if not "!_CL:LNKMOVE|=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!A"
if not "!_CL:\Image File Execution Options=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!A"
if not "!_CL:TASK|=!"=="!_CL!" if "!_CL:\Microsoft\Windows\=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!A"
rem --- G: игры и GPU ---
if not "!_CL:\GameBar=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!G"
if not "!_CL:\GameDVR=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!G"
if not "!_CL:\GameConfigStore=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!G"
if not "!_CL:\Tasks\Games=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!G"
if not "!_CL:\Control Panel\Mouse=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!G"
if not "!_CL:\GraphicsDrivers=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!G"
if not "!_CL:\Multimedia\Audio=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!G"
if not "!_CL:SystemResponsiveness=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!G"
if not "!_CL:\Enum\PCI=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!G"
if not "!_CL:\Class\{4d36e968=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!G"
if not "!_CL:\WindowsRuntime=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!G"
rem --- M: память и хранилище ---
if not "!_CL:\Memory Management=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!M"
if not "!_CL:SvcHostSplitThresholdInKB=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!M"
if not "!_CL:MMAGENT|=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!M"
if not "!_CL:\Control\FileSystem=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!M"
if not "!_CL:FSUTIL|=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!M"
if not "!_CL:\Services\storport=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!M"
if not "!_CL:\PrefetchParameters=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!M"
if not "!_CL:RESERVED|=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!M"
rem --- U: службы ---
if not "!_CL:\CurrentControlSet\Services\=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!U"
if not "!_CL:SVC|=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!U"
rem --- W: UX, телеметрия, приватность, ввод ---
if not "!_CL:\DataCollection=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!W"
if not "!_CL:\AdvertisingInfo=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!W"
if not "!_CL:\ContentDeliveryManager=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!W"
if not "!_CL:\CloudContent=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!W"
if not "!_CL:\AppCompat=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!W"
if not "!_CL:\Windows Error Reporting=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!W"
if not "!_CL:\Explorer\Advanced=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!W"
if not "!_CL:WindowsCopilot=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!W"
if not "!_CL:\Windows Search=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!W"
if not "!_CL:\Policies\Microsoft\Windows\Explorer=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!W"
if not "!_CL:\Siuf=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!W"
if not "!_CL:\LocationAndSensors=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!W"
if not "!_CL:CapabilityAccessManager=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!W"
if not "!_CL:BackgroundAccessApplications=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!W"
if not "!_CL:\Control Panel\Keyboard=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!W"
if not "!_CL:\Control Panel\Accessibility=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!W"
if not "!_CL:TASK|=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!W"
if not "!_CL:Image File Execution Options=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!W"
if not "!_CL:\Class\{4d36e968=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!G"
if not "!_CL:\WindowsRuntime=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!G"
rem --- M: память и хранилище ---
if not "!_CL:\PrefetchParameters=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!M"
if not "!_CL:RESERVED|=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!M"
rem --- U: службы ---
if not "!_CL:\CurrentControlSet\Services\=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!U"
if not "!_CL:SVC|=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!U"
rem --- W: UX, телеметрия, приватность, ввод ---
if not "!_CL:TASK|=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!W"
if not "!_CL:Image File Execution Options=!"=="!_CL!" set "_RB_GRPS=!_RB_GRPS!W"
exit /b 0

rem ============================================================
rem  REPLAY_LINE - разбор одной записи и диспетчер по типу.
rem  Первый проход всегда tokens=1,2,* : звёздотокен присутствует
rem  даже когда пуст, поэтому короткие строки не теряются.
rem ============================================================
:REPLAY_LINE
set "_RL=!_RB_LINE!"
if not defined _RL exit /b 0
if "%WP_DRYRUN%"=="1" (
    echo   [PLAN] !_RL!
    >>"%RB_LOG%" echo PLAN ^| !_RL!
    set /a RB_SKIP+=1
    exit /b 0
)
set "_TYPE="
set "_F2="
set "_REST="
for /f "tokens=1,2,* delims=|" %%a in ("!_RL!") do (
    set "_TYPE=%%a"
    set "_F2=%%b"
    set "_REST=%%c"
)
if not defined _TYPE exit /b 0
if /i "!_TYPE!"=="REG"          goto :RP_REG
if /i "!_TYPE!"=="REGACL"       goto :RP_REGACL
if /i "!_TYPE!"=="KEY"          goto :RP_KEY
if /i "!_TYPE!"=="SVC"          goto :RP_SVC
if /i "!_TYPE!"=="BCD"          goto :RP_BCD
if /i "!_TYPE!"=="POWER"        goto :RP_POWER
if /i "!_TYPE!"=="POWERSCHEME"  goto :RP_POWERSCHEME
if /i "!_TYPE!"=="POWERNEW"     goto :RP_POWERNEW
if /i "!_TYPE!"=="NETSH"        goto :RP_NETSH
if /i "!_TYPE!"=="NETSHSUPP"    goto :RP_NETSHSUPP
if /i "!_TYPE!"=="FSUTIL"       goto :RP_FSUTIL
if /i "!_TYPE!"=="TASK"         goto :RP_TASK
if /i "!_TYPE!"=="HIBER"        goto :RP_HIBER
if /i "!_TYPE!"=="RESERVED"     goto :RP_RESERVED
if /i "!_TYPE!"=="BCDSUSPEND"   goto :RP_BCDSUSPEND
if /i "!_TYPE!"=="MMAGENT"      goto :RP_MMAGENT
if /i "!_TYPE!"=="DEFEXCL"      goto :RP_DEFEXCL
if /i "!_TYPE!"=="DEFSTATE"     goto :RP_DEFSTATE
if /i "!_TYPE!"=="LNKMOVE"      goto :RP_LNKMOVE
if /i "!_TYPE!"=="IRREVERSIBLE" goto :RP_IRREV
call :RB_LOG_SKIP "неизвестный тип журнала !_TYPE!"
exit /b 0

rem ============================================================
rem  RP_REG - возврат значения реестра или его удаление
rem ============================================================
:RP_REG
set "_V="
set "_T="
set "_D="
for /f "tokens=1,2,* delims=|" %%a in ("!_REST!") do (
    set "_V=%%a"
    set "_T=%%b"
    set "_D=%%c"
)
if not defined _V (
    call :RB_LOG_SKIP "REG без имени значения: !_F2!"
    exit /b 0
)
if /i "!_T!"=="ABSENT" (
    reg query "!_F2!" /v "!_V!" >nul 2>&1
    if errorlevel 1 (
        call :RB_LOG_SKIP "уже отсутствует !_F2! :: !_V!"
        exit /b 0
    )
    reg delete "!_F2!" /v "!_V!" /f >nul 2>&1
    if errorlevel 1 (
        call :RB_LOG_FAIL "del !_F2! :: !_V!"
    ) else (
        call :RB_LOG_OK "del !_F2! :: !_V!"
    )
    exit /b 0
)
if not defined _T (
    call :RB_LOG_SKIP "REG без типа: !_F2! :: !_V!"
    exit /b 0
)
set "_DQ=!_D:"=\"!"
if "!_DQ:~-1!"=="\" set "_DQ=!_DQ!\"
reg add "!_F2!" /v "!_V!" /t !_T! /d "!_DQ!" /f >nul 2>&1
if errorlevel 1 (
    call :RB_LOG_FAIL "set !_F2! :: !_V!"
) else (
    call :RB_LOG_OK "set !_F2! :: !_V! = !_D!"
)
exit /b 0

rem ============================================================
rem  RP_REGACL - то же, но через do-regacl: ветка под
rem  TrustedInstaller обычным reg add не пишется.
rem  ABSENT -> тип DELETE, иначе значение не удалить.
rem ============================================================
:RP_REGACL
set "_V="
set "_T="
set "_D="
for /f "tokens=1,2,* delims=|" %%a in ("!_REST!") do (
    set "_V=%%a"
    set "_T=%%b"
    set "_D=%%c"
)
if not defined _V (
    call :RB_LOG_SKIP "REGACL без имени значения: !_F2!"
    exit /b 0
)
set "_AF=%WP_RUN%\rb_regacl.txt"
if exist "%_AF%" del /f /q "%_AF%" >nul 2>&1
set "REGACL_WRITTEN="
set "REGACL_ERROR="
set "REGACL_OWNER_RESTORED="
set "REGACL_ACL_RESTORED="
if /i "!_T!"=="ABSENT" (
    reg query "!_F2!" >nul 2>&1
    if not errorlevel 1 (
        reg query "!_F2!" /v "!_V!" >nul 2>&1
        if errorlevel 1 (
            call :RB_LOG_SKIP "уже отсутствует !_F2! :: !_V!"
            exit /b 0
        )
    )
    call "%WP_LIB%\core.cmd" :PS_RUN do-regacl "%_AF%" "!_F2!" "!_V!" "DELETE"
) else (
    call "%WP_LIB%\core.cmd" :PS_RUN do-regacl "%_AF%" "!_F2!" "!_V!" "!_T!" "!_D!"
)
call :LOAD_KV "%_AF%"
if not "!REGACL_WRITTEN!"=="1" (
    call :RB_LOG_FAIL "regacl !_F2! :: !_V! - !REGACL_ERROR!"
    exit /b 0
)
if not "!REGACL_OWNER_RESTORED!"=="1" call "%WP_LIB%\core.cmd" :WARN "владелец не возвращён: !_F2!"
if not "!REGACL_ACL_RESTORED!"=="1" call "%WP_LIB%\core.cmd" :WARN "правило ACL не снято: !_F2!"
set "WP_REBOOT_REQUIRED=1"
call :RB_LOG_OK "regacl !_F2! :: !_V! восстановлено"
exit /b 0

rem ============================================================
rem  RP_KEY - ключа не было, значит удаляем созданный
rem ============================================================
:RP_KEY
if /i not "!_REST!"=="ABSENT" (
    call :RB_LOG_SKIP "нет исходного состояния ключа !_F2!"
    exit /b 0
)
set "WP_KEY_PATH=!_F2!"
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WP_LIB%\wp.ps1" session-key undo
set "_KEY_RC=!errorlevel!"
if "!_KEY_RC!"=="10" (
    call :RB_LOG_SKIP "ключ уже отсутствует: !_F2!"
) else if "!_KEY_RC!"=="11" (
    call :RB_LOG_SKIP "в ключе остались значения или подразделы: !_F2!"
) else if "!_KEY_RC!"=="0" (
    call :RB_LOG_OK "delete empty key !_F2!"
) else (
    call :RB_LOG_FAIL "delete empty key !_F2!"
)
exit /b 0

rem ============================================================
rem  RP_SVC - служба работала до остановки.
rem  Если её успели отключить, старт не пройдёт: временно
rem  ставим demand, а исходный Start вернёт запись REG выше
rem  по обратному порядку обхода.
rem ============================================================
:RP_SVC
sc query "!_F2!" >nul 2>&1
if errorlevel 1 (
    call :RB_LOG_SKIP "служба отсутствует: !_F2!"
    exit /b 0
)
sc start "!_F2!" >nul 2>&1
if not errorlevel 1 (
    call :RB_LOG_OK "start service !_F2!"
    exit /b 0
)
sc config "!_F2!" start= demand >nul 2>&1
sc start "!_F2!" >nul 2>&1
if errorlevel 1 (
    call :RB_LOG_FAIL "start service !_F2!"
) else (
    call :RB_LOG_OK "start service !_F2! (forced demand)"
)
exit /b 0

rem ============================================================
rem  RP_BCD - ABSENT = элемента не было, удаляем; иначе возврат
rem ============================================================
:RP_BCD
if /i "!_REST!"=="ABSENT" (
    bcdedit /deletevalue {current} !_F2! >nul 2>&1
    if errorlevel 1 (
        call :RB_LOG_FAIL "bcd delete !_F2!"
    ) else (
        set "WP_REBOOT_REQUIRED=1"
        call :RB_LOG_OK "bcd delete !_F2!"
    )
    exit /b 0
)
if not defined _REST (
    call :RB_LOG_SKIP "bcd без значения: !_F2!"
    exit /b 0
)
bcdedit /set {current} !_F2! !_REST! >nul 2>&1
if errorlevel 1 (
    call :RB_LOG_FAIL "bcd set !_F2! = !_REST!"
) else (
    set "WP_REBOOT_REQUIRED=1"
    call :RB_LOG_OK "bcd set !_F2! = !_REST!"
)
exit /b 0

rem ============================================================
rem  RP_POWER - индексы AC/DC из журнала, hex переводим в dec
rem ============================================================
:RP_POWER
set "_PS="
set "_PAC="
set "_PDC="
set "_DAC="
set "_DDC="
for /f "tokens=1,2,* delims=|" %%a in ("!_REST!") do (
    set "_PS=%%a"
    set "_PAC=%%b"
    set "_PDC=%%c"
)
if not defined _PS (
    call :RB_LOG_SKIP "POWER без имени параметра"
    exit /b 0
)
if /i "!_PAC!"=="UNKNOWN" (
    call :RB_LOG_SKIP "POWER !_PS! прежнее состояние неизвестно, верните вручную"
    exit /b 0
)
call :RB_HEX2DEC _PAC _DAC
call :RB_HEX2DEC _PDC _DDC
if not defined _DAC (
    call :RB_LOG_SKIP "POWER !_PS! индекс AC не разобран"
    exit /b 0
)
powercfg /setacvalueindex SCHEME_CURRENT !_F2! !_PS! !_DAC! >nul 2>&1
if errorlevel 1 (
    call :RB_LOG_FAIL "power AC !_PS!"
    exit /b 0
)
if defined _DDC powercfg /setdcvalueindex SCHEME_CURRENT !_F2! !_PS! !_DDC! >nul 2>&1
powercfg /setactive SCHEME_CURRENT >nul 2>&1
call :RB_LOG_OK "power !_PS! AC=!_DAC! DC=!_DDC!"
exit /b 0

rem ============================================================
rem  RP_POWERSCHEME / RP_POWERNEW
rem  Порядок в журнале: POWERNEW затем POWERSCHEME, поэтому
rem  при обратном обходе сначала вернётся прежний план, и только
rem  потом удалится созданный. Иначе powercfg откажется удалять
rem  активную схему.
rem ============================================================
:RP_POWERSCHEME
powercfg /setactive !_F2! >nul 2>&1
if errorlevel 1 (
    call :RB_LOG_FAIL "power scheme !_F2!"
) else (
    call :RB_LOG_OK "power scheme !_F2!"
)
exit /b 0

:RP_POWERNEW
powercfg /delete !_F2! >nul 2>&1
if errorlevel 1 (
    call :RB_LOG_SKIP "схема !_F2! не удалена: активна или отсутствует"
) else (
    call :RB_LOG_OK "схема !_F2! удалена"
)
exit /b 0

rem ============================================================
rem  RP_NETSH / RP_NETSHSUPP - возврат к дефолту Windows.
rem  Прежнее состояние netsh не читается locale-независимо,
rem  это документированный дефолт, а не персональный.
rem ============================================================
:RP_NETSH
netsh int tcp set global !_F2!=!_REST! >nul 2>&1
if errorlevel 1 (
    call :RB_LOG_SKIP "netsh !_F2! не поддерживается этой сборкой"
) else (
    call :RB_LOG_OK "netsh !_F2! = !_REST!"
)
exit /b 0

:RP_NETSHSUPP
netsh int tcp set supplemental template=!_F2! congestionprovider=!_REST! >nul 2>&1
if errorlevel 1 (
    call :RB_LOG_SKIP "netsh supplemental !_F2! отклонён"
) else (
    call :RB_LOG_OK "netsh supplemental !_F2! = !_REST!"
)
exit /b 0

rem ============================================================
rem  RP_FSUTIL / RP_TASK
rem ============================================================
:RP_FSUTIL
fsutil behavior set !_F2! !_REST! >nul 2>&1
if errorlevel 1 (
    call :RB_LOG_FAIL "fsutil !_F2! = !_REST!"
) else (
    call :RB_LOG_OK "fsutil !_F2! = !_REST!"
)
exit /b 0

:RP_TASK
if /i not "!_REST!"=="ENABLED" if /i not "!_REST!"=="DEFAULT_ENABLED" (
    call :RB_LOG_SKIP "неизвестное исходное состояние задачи !_F2!"
    exit /b 0
)
schtasks /query /tn "!_F2!" >nul 2>&1
if errorlevel 1 (
    call :RB_LOG_SKIP "задача отсутствует: !_F2!"
    exit /b 0
)
schtasks /change /tn "!_F2!" /enable >nul 2>&1
if errorlevel 1 (
    call :RB_LOG_FAIL "task enable !_F2!"
) else (
    call :RB_LOG_OK "task enable !_F2!"
)
exit /b 0

rem ============================================================ rem  RP_LNKMOVE - возврат ярлыка из подпапки Disabled на место. rem  Пропуск, если приёмник пропал или место уже занято. rem ============================================================ :RP_LNKMOVE if not defined _F2 (     call :RB_LOG_SKIP "LNKMOVE без исходного пути"     exit /b 0 ) if not defined _REST (     call :RB_LOG_SKIP "LNKMOVE без пути приёмника"     exit /b 0 ) if not exist "!_REST!" (     call :RB_LOG_SKIP "LNKMOVE: приёмник отсутствует !_REST!"     exit /b 0 ) if exist "!_F2!" (     call :RB_LOG_SKIP "LNKMOVE: место занято !_F2!"     exit /b 0 ) move /y "!_REST!" "!_F2!" >nul 2>&1 if errorlevel 1 (     call :RB_LOG_FAIL "lnkmove back !_F2!" ) else (     call :RB_LOG_OK "lnkmove back !_F2!" ) exit /b 0

rem ============================================================
rem  RP_HIBER - возвращает и реестр, и hiberfil.sys
rem ============================================================
:RP_HIBER
if "!_REST!"=="1" (powercfg /h on >nul 2>&1) else (powercfg /h off >nul 2>&1)
if errorlevel 1 (
    call :RB_LOG_FAIL "hibernation = !_REST!"
) else (
    set "WP_REBOOT_REQUIRED=1"
    call :RB_LOG_OK "hibernation = !_REST!"
)
exit /b 0

rem ============================================================
rem  RP_RESERVED - UNKNOWN не угадываем
rem ============================================================
:RP_RESERVED
if /i "!_REST!"=="UNKNOWN" (
    call :RB_LOG_SKIP "Reserved Storage прежнее состояние неизвестно, верните через DISM вручную"
    exit /b 0
)
if "!_REST!"=="1" (
    DISM /Online /Set-ReservedStorageState /State:Enabled >nul 2>&1
) else (
    DISM /Online /Set-ReservedStorageState /State:Disabled >nul 2>&1
)
if errorlevel 1 (
    call :RB_LOG_FAIL "Reserved Storage = !_REST!"
) else (
    set "WP_REBOOT_REQUIRED=1"
    call :RB_LOG_OK "Reserved Storage = !_REST!"
)
exit /b 0

rem ============================================================
rem  RP_BCDSUSPEND - включаем защиту BitLocker обратно.
rem  Она и так включилась бы после ребута, но откат не должен
rem  оставлять систему с приостановленной защитой.
rem ============================================================
:RP_BCDSUSPEND
manage-bde -protectors -enable !_F2! >nul 2>&1
if errorlevel 1 (
    call :RB_LOG_FAIL "BitLocker enable !_F2!"
) else (
    set "WP_BCD_SUSPENDED=0"
    call :RB_LOG_OK "BitLocker защита включена на !_F2!"
)
exit /b 0

rem ============================================================
rem  RP_MMAGENT - -1 значит прежнее состояние неизвестно
rem ============================================================
:RP_MMAGENT
if "!_REST!"=="-1" (
    call :RB_LOG_SKIP "MMAgent !_F2! прежнее состояние неизвестно, верните вручную"
    exit /b 0
)
set "_MF=%WP_RUN%\rb_mmagent.txt"
call :MM_CLEAR
if exist "%_MF%" del /f /q "%_MF%" >nul 2>&1
call "%WP_LIB%\core.cmd" :PS_RUN do-mmagent "%_MF%" "!_F2!" "!_REST!"
call :LOAD_KV "%_MF%"
if "!MM_APPLIED!"=="1" (
    call :RB_LOG_OK "mmagent !_F2! = !_REST!"
    exit /b 0
)
if "!MM_NEED_REBOOT!"=="1" (
    set "WP_REBOOT_REQUIRED=1"
    call :RB_LOG_OK "mmagent !_F2! = !_REST! ожидает перезагрузки"
    exit /b 0
)
call :RB_LOG_FAIL "mmagent !_F2! - !MM_ERROR!"
exit /b 0

rem ============================================================
rem  RP_DEFEXCL - ABSENT = мы добавили, значит убираем;
rem  PRESENT = мы могли удалить, значит возвращаем.
rem ============================================================
:RP_DEFEXCL
set "_DV="
set "_DST="
for /f "tokens=1,* delims=|" %%a in ("!_REST!") do (
    set "_DV=%%a"
    set "_DST=%%b"
)
if not defined _DV (
    call :RB_LOG_SKIP "DEFEXCL без значения"
    exit /b 0
)
set "_DACT="
if /i "!_DST!"=="ABSENT" (
    if /i "!_F2!"=="path" set "_DACT=removeexclpath"
    if /i "!_F2!"=="proc" set "_DACT=removeexclproc"
) else (
    if /i "!_F2!"=="path" set "_DACT=addexclpath"
    if /i "!_F2!"=="proc" set "_DACT=addexclproc"
)
if not defined _DACT (
    call :RB_LOG_SKIP "DEFEXCL неизвестный kind !_F2!"
    exit /b 0
)
set "_DF=%WP_RUN%\rb_defender.txt"
call :DEF_CLEAR
if exist "%_DF%" del /f /q "%_DF%" >nul 2>&1
call "%WP_LIB%\core.cmd" :PS_RUN do-defender "%_DF%" "!_DACT!" "!_DV!"
call :LOAD_KV "%_DF%"
if "!DEF_APPLIED!"=="1" (
    call :RB_LOG_OK "defender excl !_DACT! !_DV!"
    exit /b 0
)
if "!DEF_TAMPER_BLOCKED!"=="1" (
    call :RB_LOG_FAIL "defender excl !_DV! блокирует Tamper Protection"
    exit /b 0
)
call :RB_LOG_FAIL "defender excl !_DV! - !DEF_ERROR!"
exit /b 0

rem ============================================================
rem  RP_DEFSTATE - возврат Realtime / ScriptScanning
rem ============================================================
:RP_DEFSTATE
if "!_REST!"=="-1" (
    call :RB_LOG_SKIP "Defender !_F2! прежнее состояние неизвестно, верните вручную"
    exit /b 0
)
set "_DF=%WP_RUN%\rb_defender.txt"
call :DEF_CLEAR
if exist "%_DF%" del /f /q "%_DF%" >nul 2>&1
call "%WP_LIB%\core.cmd" :PS_RUN do-defender "%_DF%" "!_F2!" "!_REST!"
call :LOAD_KV "%_DF%"
if "!DEF_APPLIED!"=="1" (
    call :RB_LOG_OK "defender !_F2! = !_REST!"
    exit /b 0
)
if "!DEF_TAMPER_BLOCKED!"=="1" (
    call :RB_LOG_FAIL "defender !_F2! блокирует Tamper Protection"
    exit /b 0
)
call :RB_LOG_FAIL "defender !_F2! - !DEF_ERROR!"
exit /b 0

rem ============================================================
rem  RP_IRREV - необратимое. Не делаем вид, что вернули.
rem ============================================================
:RP_IRREV
if defined _REST (
    call :RB_LOG_IRREV "!_F2! !_REST!"
) else (
    call :RB_LOG_IRREV "!_F2!"
)
exit /b 0


rem ============================================================
rem  RP_LNKMOVE - возврат ярлыка из подпапки Disabled на место.
rem  Пропуск, если приёмник пропал или место уже занято.
rem ============================================================
:RP_LNKMOVE
if not defined _F2 (
    call :RB_LOG_SKIP "LNKMOVE без исходного пути"
    exit /b 0
)
if not defined _REST (
    call :RB_LOG_SKIP "LNKMOVE без пути приёмника"
    exit /b 0
)
if not exist "!_REST!" (
    call :RB_LOG_SKIP "LNKMOVE: приёмник отсутствует !_REST!"
    exit /b 0
)
if exist "!_F2!" (
    call :RB_LOG_SKIP "LNKMOVE: место занято !_F2!"
    exit /b 0
)
move /y "!_REST!" "!_F2!" >nul 2>&1
if errorlevel 1 (
    call :RB_LOG_FAIL "lnkmove back !_F2!"
) else (
    call :RB_LOG_OK "lnkmove back !_F2!"
)
exit /b 0

rem ============================================================
rem  RB_AUTORUN - откат группы A: автозагрузка.
rem ============================================================
:RB_AUTORUN
call :ROLLBACK_GROUP "A" "!_RB_JOURNAL!"
call "%WP_LIB%\core.cmd" :PAUSE_SAFE
goto :RB_GROUPS

rem ============================================================
rem  PROVISIONED_REMOVE  %1 core|extra
rem  Схема APPX_REMOVE: ровно один результат на семейство.
rem  Песочница обрабатывается здесь, до PS_RUN, без задвоения.
rem ============================================================
:PROVISIONED_REMOVE
set "_PM=%~1"
set "_PN="
if /i "!_PM!"=="core" (set "_PM=core" & set "_PN=17")
if /i "!_PM!"=="extra" (set "_PM=extra" & set "_PN=13")
if not defined _PN (
    call "%WP_LIB%\core.cmd" :FAIL "PROVISIONED_REMOVE: tier должен быть core или extra"
    exit /b 1
)
if "%WP_DRYRUN%"=="1" (
    for /l %%i in (1,1,!_PN!) do call "%WP_LIB%\core.cmd" :PLAN "provisioned !_PM! family %%i"
    exit /b 0
)
if defined PV_FAMILIES (
    for /l %%i in (1,1,%PV_FAMILIES%) do (
        set "PV_P%%i_FAMILY="
        set "PV_P%%i_FOUND="
        set "PV_P%%i_REMOVED="
        set "PV_P%%i_FAILED="
        set "PV_P%%i_SKIPPED="
        set "PV_P%%i_PROTECTED="
    )
)
if defined PV_LISTED (
    for /l %%i in (1,1,%PV_LISTED%) do set "PV_PKG_%%i_NAME="
)
set "PV_FAMILIES="
set "PV_LISTED="
set "PV_REMOVED="
set "PV_FAILED="
set "_PVF=%WP_RUN%\prov.txt"
if exist "%_PVF%" del /f /q "%_PVF%" >nul 2>&1
call "%WP_LIB%\core.cmd" :PS_RUN do-provisioned "%_PVF%" "!_PM!"
call :LOAD_KV "%_PVF%"
if not defined PV_FAMILIES (
    for /l %%i in (1,1,!_PN!) do call "%WP_LIB%\core.cmd" :FAIL "provisioned family %%i: PS-движок не ответил"
    exit /b 1
)
call "%WP_LIB%\core.cmd" :IRREVERSIBLE "provisioned removal tier=!_PM!"
if defined PV_LISTED if !PV_LISTED! gtr 0 (
    >"%WP_SESSION_DIR%\provisioned_removed.txt" echo WinPulse provisioned removed %STAMP%
    >>"%WP_SESSION_DIR%\provisioned_removed.txt" echo Tier: !_PM!
    >>"%WP_SESSION_DIR%\provisioned_removed.txt" echo Reinstall: Microsoft Store, либо Add-AppxProvisionedPackage -Online -PackagePath из образа
    for /l %%i in (1,1,!PV_LISTED!) do >>"%WP_SESSION_DIR%\provisioned_removed.txt" echo !PV_PKG_%%i_NAME!
)
for /l %%i in (1,1,!PV_FAMILIES!) do (
    set "_PF=!PV_P%%i_FAMILY!"
    set "_PFL=!PV_P%%i_FAILED!"
    set "_PRV=!PV_P%%i_REMOVED!"
    set "_PPR=!PV_P%%i_PROTECTED!"
    if not defined _PFL set "_PFL=0"
    if not defined _PRV set "_PRV=0"
    if !_PFL! gtr 0 (
        call "%WP_LIB%\core.cmd" :FAIL "provisioned !_PF!: ошибок !_PFL!"
    ) else if !_PRV! gtr 0 (
        call "%WP_LIB%\core.cmd" :OK "provisioned !_PF!: удалено !_PRV!"
    ) else if "!_PPR!"=="1" (
        call "%WP_LIB%\core.cmd" :SKIP "provisioned !_PF!: защищён whitelist"
    ) else (
        call "%WP_LIB%\core.cmd" :SKIP "provisioned !_PF!: не provisioned"
    )
)
if not "!PV_FAMILIES!"=="!_PN!" call "%WP_LIB%\core.cmd" :WARN "provisioned: семейств !PV_FAMILIES!, ожидалось !_PN!"
exit /b 0
:: END OF FILE | Всего твиков в файле: 0

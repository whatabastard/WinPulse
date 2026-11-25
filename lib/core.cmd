@echo off
rem ============================================================
rem  WinPulse 7.1 "Rebuild"  |  lib\core.cmd
rem  Ядро записи: сообщения, счётчики, журнал отката, обёртки.
rem
rem  Кодировка: UTF-8 БЕЗ BOM, CRLF. Символ "!" в echo запрещён.
rem  Вызов:  call "%WP_LIB%\core.cmd" :LABEL "arg1" "arg2" ...
rem  Свой setlocal ЗАПРЕЩЁН - окружение общее с winpulse.bat.
rem
rem  Контракт от winpulse.bat:
rem    WP_LIB WP_ROOT WP_RUN WP_SESSION_DIR WP_DRYRUN WP_HKCU
rem    SESSION_LOG ERROR_LOG PLAN_LOG JOURNAL
rem    WP_OP_OK WP_OP_FAIL WP_OP_SKIP WP_OP_PLAN
rem    WP_REBOOT_REQUIRED WP_UNATTENDED WP_IRREVERSIBLE
rem    WP_APPLIED_BLOCKS WP_SKIPPED_BLOCKS WP_FAILED_BLOCKS
rem
rem  ПРАВИЛО: внутри pipe и FOR /F только %VAR%, никогда !VAR! -
rem  дочерний cmd.exe не наследует delayed expansion.
rem
rem  Счётчики: OK FAIL SKIP PLAN инкрементят сами. Второй раз
rem  рядом инкрементить нельзя, статистика соврёт вдвое.
rem ============================================================
if "%~1"=="" exit /b 9009
if not defined WP_LIB exit /b 9009
if not defined JOURNAL exit /b 9009
set "__EP=%~1"
shift
goto %__EP%

rem ============================================================
rem  СООБЩЕНИЯ И СЧЁТЧИКИ
rem ============================================================
:MSG
if "%WP_GUARD_PROBE%"=="1" exit /b 0
set "_M=%~1"
echo   !_M!
>>"%SESSION_LOG%" echo [%TIME%] !_M!
exit /b 0

:OK
set "_M=%~1"
echo   [OK]   !_M!
>>"%SESSION_LOG%" echo [%TIME%] [OK] !_M!
set /a WP_OP_OK+=1
exit /b 0

:FAIL
set "_M=%~1"
echo   [FAIL] !_M!
>>"%SESSION_LOG%" echo [%TIME%] [FAIL] !_M!
>>"%ERROR_LOG%" echo [%TIME%] !_M!
set /a WP_OP_FAIL+=1
exit /b 1

:SKIP
set "_M=%~1"
echo   [SKIP] !_M!
>>"%SESSION_LOG%" echo [%TIME%] [SKIP] !_M!
set /a WP_OP_SKIP+=1
exit /b 0

:WARN
if "%WP_GUARD_PROBE%"=="1" exit /b 0
set "_M=%~1"
echo   [WARN] !_M!
>>"%SESSION_LOG%" echo [%TIME%] [WARN] !_M!
exit /b 0

:HEAD
set "_M=%~1"
echo.
echo == !_M! ==
>>"%SESSION_LOG%" echo [%TIME%] ===== !_M! =====
exit /b 0

:PLAN
set "_M=%~1"
echo   [PLAN] !_M!
>>"%PLAN_LOG%" echo !_M!
set /a WP_OP_PLAN+=1
exit /b 0

rem ============================================================
rem  CONFIRM  %1 вопрос  %2 дефолт для dry-run (Y/N)
rem  0 = да, 1 = нет. В песочнице берёт дефолт, не спрашивает.
rem ============================================================
:CONFIRM
if "%WP_GUARD_PROBE%"=="1" exit /b 1
set "_Q=%~1"
set "_D=%~2"
if "%WP_DRYRUN%"=="1" (
    echo   [PLAN] !_Q! - песочница считает ДА
    exit /b 0
)
set "WP_QUESTION=  !_Q! (Y/N): "
call "%WP_LIB%\desktop_io.cmd" choice YN
if errorlevel 2 exit /b 1
exit /b 0

rem ============================================================
rem  SNAP_REG - снимок текущего значения в журнал отката
rem  %1 ключ  %2 имя значения  %3 тип  %4 целевые данные
rem  Выставляет _SNAP_STATE = ABSENT / SAME / DIFF
rem ============================================================
:SNAP_REG
set "_SK=%~1"
set "_SV=%~2"
set "_ST=%~3"
set "_SD=%~4"
set "_SNAP_STATE=ERROR"
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WP_LIB%\wp.ps1" snapshot-reg "%~5"
set "_SNAP_RC=!errorlevel!"
if "!_SNAP_RC!"=="10" set "_SNAP_STATE=ABSENT"
if "!_SNAP_RC!"=="11" set "_SNAP_STATE=SAME"
if "!_SNAP_RC!"=="12" set "_SNAP_STATE=DIFF"
if "!_SNAP_STATE!"=="ERROR" (
    call :FAIL "Не удалось сохранить исходное состояние !_SK! :: !_SV!"
    exit /b 1
)
exit /b 0

rem ============================================================
rem  REG_SET  %1 ключ  %2 значение  %3 тип  %4 данные
rem  Идемпотентно: если уже равно цели, запись не выполняется.
rem ============================================================
:REG_SET
set "_K=%~1"
set "_V=%~2"
set "_T=%~3"
set "_D=%~4"
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo REG_SET^|!_K!^|!_V!^|!_T!^|!_D!
    echo     [PLAN] !_V! = !_D!
    set /a WP_OP_PLAN+=1
    exit /b 0
)
call :SNAP_REG "!_K!" "!_V!" "!_T!" "!_D!" REG_SET
if errorlevel 1 exit /b 1
if "!_SNAP_STATE!"=="SAME" (
    set /a WP_OP_SKIP+=1
    >>"%SESSION_LOG%" echo [%TIME%] [SAME] !_K! :: !_V!
    exit /b 0
)
reg add "!_K!" /v "!_V!" /t !_T! /d "!_D!" /f >nul 2>&1
if errorlevel 1 (
    call :FAIL "reg add !_K! :: !_V!"
    exit /b 1
)
set /a WP_OP_OK+=1
>>"%SESSION_LOG%" echo [%TIME%] [SET] !_K! :: !_V! = !_D!
exit /b 0

rem ============================================================
rem  REG_DEL  %1 ключ  %2 имя значения
rem ============================================================
:REG_DEL
set "_K=%~1"
set "_V=%~2"
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo REG_DEL^|!_K!^|!_V!
    echo     [PLAN] delete !_V!
    set /a WP_OP_PLAN+=1
    exit /b 0
)
call :SNAP_REG "!_K!" "!_V!" "REG_NONE" ""
if errorlevel 1 exit /b 1
if "!_SNAP_STATE!"=="ABSENT" (
    set /a WP_OP_SKIP+=1
    exit /b 0
)
reg delete "!_K!" /v "!_V!" /f >nul 2>&1
if errorlevel 1 (
    call :FAIL "reg delete !_K! :: !_V!"
    exit /b 1
)
set /a WP_OP_OK+=1
>>"%SESSION_LOG%" echo [%TIME%] [DEL] !_K! :: !_V!
exit /b 0

rem ============================================================
rem  REG_KEY - создать ключ, если его нет, с журналом на удаление.
rem  COUNT включает учёт операции создания ключа.
rem ============================================================
:REG_KEY
set "_K=%~1"
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo REG_KEY^|!_K!
    exit /b 0
)
set "WP_KEY_PATH=!_K!"
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WP_LIB%\wp.ps1" session-key create
set "_KEY_RC=!errorlevel!"
if "!_KEY_RC!"=="11" (
    if /i "%~2"=="COUNT" call :SKIP "ключ уже есть: !_K!"
    exit /b 0
)
if not "!_KEY_RC!"=="0" (
    call :FAIL "create key !_K!"
    exit /b 1
)
if /i "%~2"=="COUNT" set /a WP_OP_OK+=1
>>"%SESSION_LOG%" echo [%TIME%] [KEY] !_K!
exit /b 0

rem ============================================================
rem  SC_SET  %1 служба  %2 auto|delayed|demand|disabled
rem  Пишет через SCM мгновенно, в журнал кладёт реестровый Start,
rem  поэтому откат идёт тем же реестровым replay.
rem ============================================================
:SC_SET
set "_S=%~1"
set "_A=%~2"
set "_N="
set "_C=!_A!"
if /i "!_A!"=="auto"     set "_N=2"
if /i "!_A!"=="delayed"  set "_N=2"
if /i "!_A!"=="demand"   set "_N=3"
if /i "!_A!"=="disabled" set "_N=4"
if /i "!_A!"=="delayed"  set "_C=delayed-auto"
if not defined _N (
    call :FAIL "SC_SET: неизвестный тип запуска !_A!"
    exit /b 1
)
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo SC_SET^|!_S!^|!_A!
    echo     [PLAN] service !_S! = !_A!
    set /a WP_OP_PLAN+=1
    exit /b 0
)
sc query "!_S!" >nul 2>&1
if errorlevel 1 (
    call :SKIP "служба !_S! не установлена"
    exit /b 0
)
call :SNAP_REG "HKLM\SYSTEM\CurrentControlSet\Services\!_S!" "Start" "REG_DWORD" "!_N!"
if errorlevel 1 exit /b 1
set "_ND=0"
if /i "!_A!"=="delayed" set "_ND=1"
if /i "!_A!"=="auto"    set "_ND=1"
if "!_SNAP_STATE!"=="SAME" if "!_ND!"=="0" (
    set /a WP_OP_OK+=1
    >>"%SESSION_LOG%" echo [%TIME%] [SAME] SVC !_S! = !_A!
    exit /b 0
)
set "_DELAY=0"
if /i "!_A!"=="delayed" set "_DELAY=1"
if "!_ND!"=="1" (
    call :SNAP_REG "HKLM\SYSTEM\CurrentControlSet\Services\!_S!" "DelayedAutostart" "REG_DWORD" "!_DELAY!"
    if errorlevel 1 exit /b 1
)
sc config "!_S!" start= !_C! >nul 2>&1
if errorlevel 1 (
    call :FAIL "sc config !_S! start= !_C!"
    exit /b 1
)
if /i "!_A!"=="delayed" reg add "HKLM\SYSTEM\CurrentControlSet\Services\!_S!" /v DelayedAutostart /t REG_DWORD /d 1 /f >nul 2>&1
if /i "!_A!"=="auto"    reg add "HKLM\SYSTEM\CurrentControlSet\Services\!_S!" /v DelayedAutostart /t REG_DWORD /d 0 /f >nul 2>&1
call :OK "служба !_S! = !_A!"
exit /b 0

rem ============================================================
rem  SC_STOP  %1 служба  %2 NOCOUNT для служебных остановок
rem  Считается операцией, кроме вызовов с NOCOUNT: остановка
rem  FontCache перед чисткой кэша - не твик из списка.
rem ============================================================
:SC_STOP
set "_S=%~1"
set "_SCNT=%~2"
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo SC_STOP^|!_S!
    echo     [PLAN] stop !_S!
    if /i not "!_SCNT!"=="NOCOUNT" set /a WP_OP_PLAN+=1
    exit /b 0
)
sc query "!_S!" >nul 2>&1
if errorlevel 1 goto :SC_STOP_ABSENT
sc query "%_S%" | findstr /i "RUNNING" >nul 2>&1
if errorlevel 1 goto :SC_STOP_NOTRUN
>>"%JOURNAL%" echo SVC^|%_S%^|RUNNING
sc stop "!_S!" >nul 2>&1
if errorlevel 1 goto :SC_STOP_FAIL
>>"%SESSION_LOG%" echo [%TIME%] [STOP] !_S!
if /i not "!_SCNT!"=="NOCOUNT" call :OK "служба !_S! остановлена"
exit /b 0
:SC_STOP_ABSENT
if /i not "!_SCNT!"=="NOCOUNT" call :SKIP "служба !_S! не установлена"
exit /b 0
:SC_STOP_NOTRUN
if /i not "!_SCNT!"=="NOCOUNT" call :SKIP "служба !_S! не запущена"
exit /b 0
:SC_STOP_FAIL
>>"%SESSION_LOG%" echo [%TIME%] [STOP-FAIL] !_S!
if /i not "!_SCNT!"=="NOCOUNT" call :FAIL "sc stop !_S!"
exit /b 1

rem ============================================================
rem  SC_START - для отката и сервисных нужд, счётчик не трогает
rem ============================================================
:SC_START
set "_S=%~1"
sc query "!_S!" >nul 2>&1
if errorlevel 1 exit /b 0
sc start "!_S!" >nul 2>&1
>>"%SESSION_LOG%" echo [%TIME%] [START] !_S!
exit /b 0

rem ============================================================
rem  BCD_SNAP  %1 элемент. Выставляет _BSTATE и _BV.
rem  Полный enum дампится один раз за сессию для ручного отката.
rem ============================================================
:BCD_SNAP
set "_BE=%~1"
set "_BL="
set "_BV="
set "_BSTATE=ABSENT"
if not exist "%WP_SESSION_DIR%\bcd_before.txt" (
    bcdedit /enum {current} > "%WP_SESSION_DIR%\bcd_before.txt" 2>nul
)
for /f "tokens=* delims=" %%L in ('bcdedit /enum {current} 2^>nul ^| findstr /i /b /c:"%_BE%"') do set "_BL=%%L"
if not defined _BL (
    >>"%JOURNAL%" echo BCD^|%_BE%^|ABSENT
    exit /b 0
)
for /f "tokens=1,*" %%a in ("!_BL!") do set "_BV=%%b"
rem Имена элементов BCD не локализуются, булевы значения - да.
if /i "!_BV!"=="Yes" set "_BV=yes"
if /i "!_BV!"=="No"  set "_BV=no"
if /i "!_BV!"=="Да"  set "_BV=yes"
if /i "!_BV!"=="Нет" set "_BV=no"
>>"%JOURNAL%" echo BCD^|!_BE!^|!_BV!
set "_BSTATE=PRESENT"
exit /b 0

rem ============================================================
rem  BCD_SET  %1 элемент  %2 значение
rem ============================================================
:BCD_SET
set "_BE=%~1"
set "_BT=%~2"
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo BCD_SET^|!_BE!^|!_BT!
    echo     [PLAN] bcd !_BE! = !_BT!
    set /a WP_OP_PLAN+=1
    exit /b 0
)
call :BCD_SNAP "!_BE!"
if /i "!_BV!"=="!_BT!" (
    set /a WP_OP_OK+=1
    >>"%SESSION_LOG%" echo [%TIME%] [SAME] BCD !_BE!
    exit /b 0
)
bcdedit /set {current} !_BE! !_BT! >nul 2>&1
if errorlevel 1 (
    call :FAIL "bcdedit /set !_BE! !_BT! - блокирует Secure Boot или политика"
    exit /b 1
)
set "WP_REBOOT_REQUIRED=1"
call :OK "BCD !_BE! = !_BT!"
exit /b 0

rem ============================================================
rem  BCD_DEL  %1 элемент
rem ============================================================
:BCD_DEL
set "_BE=%~1"
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo BCD_DEL^|!_BE!
    echo     [PLAN] bcd delete !_BE!
    set /a WP_OP_PLAN+=1
    exit /b 0
)
call :BCD_SNAP "!_BE!"
if "!_BSTATE!"=="ABSENT" (
    set /a WP_OP_SKIP+=1
    exit /b 0
)
bcdedit /deletevalue {current} !_BE! >nul 2>&1
if errorlevel 1 (
    call :FAIL "bcdedit /deletevalue !_BE!"
    exit /b 1
)
set "WP_REBOOT_REQUIRED=1"
call :OK "BCD !_BE! удалён"
exit /b 0

rem ============================================================
rem  POWER_SCHEME  %1 GUID или алиас
rem  GUID активной схемы берётся по ": ", локаль не важна.
rem ============================================================
:POWER_SCHEME
set "_PS=%~1"
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo POWER_SCHEME^|!_PS!
    echo     [PLAN] scheme = !_PS!
    set /a WP_OP_PLAN+=1
    exit /b 0
)
set "_PL="
set "_PR="
set "_PG="
for /f "tokens=* delims=" %%L in ('powercfg /getactivescheme 2^>nul') do set "_PL=%%L"
if defined _PL (
    set "_PR=!_PL:*: =!"
    for /f "tokens=1" %%g in ("!_PR!") do set "_PG=%%g"
)
if defined _PG (
    if "!_PG:~8,1!"=="-" (
        >>"%JOURNAL%" echo POWERSCHEME^|!_PG!
    ) else (
        set "_PG="
    )
)
if not defined _PG call :WARN "GUID активной схемы не распознан, откат плана ограничен"
powercfg /setactive !_PS! >nul 2>&1
if errorlevel 1 (
    call :FAIL "powercfg /setactive !_PS!"
    exit /b 1
)
call :OK "план питания = !_PS!"
exit /b 0

rem ============================================================
rem  POWER_SET  %1 subgroup  %2 setting  %3 AC  %4 DC или KEEP
rem  powercfg /q печатает ещё Possible/Min/Max индексы, поэтому
rem  берём ДВЕ ПОСЛЕДНИЕ строки с 0x - это Current AC и Current DC.
rem ============================================================
:POWER_SET
set "_QS=%~1"
set "_QT=%~2"
set "_QA=%~3"
set "_QD=%~4"
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo POWER_SET^|!_QS!^|!_QT!^|AC=!_QA!^|DC=!_QD!
    echo     [PLAN] !_QT! AC=!_QA! DC=!_QD!
    set /a WP_OP_PLAN+=1
    exit /b 0
)
set "_PPREV="
set "_PLAST="
set "_PX="
for /f "tokens=* delims=" %%L in ('powercfg /q SCHEME_CURRENT %_QS% %_QT% 2^>nul ^| findstr /i "0x"') do (
    set "_PX=%%L"
    set "_PX=!_PX:*0x=0x!"
    for /f "tokens=1" %%v in ("!_PX!") do (
        set "_PPREV=!_PLAST!"
        set "_PLAST=%%v"
    )
)
if defined _PPREV (
    >>"%JOURNAL%" echo POWER^|!_QS!^|!_QT!^|!_PPREV!^|!_PLAST!
) else (
    >>"%JOURNAL%" echo POWER^|!_QS!^|!_QT!^|UNKNOWN^|UNKNOWN
    call :WARN "параметр !_QT! не читается, откат его пропустит"
)
set "_PSAME=0"
set "_NA="
set "_NB="
if defined _PPREV if defined _PLAST (
    set /a "_NA=!_PPREV!" >nul 2>&1
    set /a "_NB=!_QA!" >nul 2>&1
    if defined _NA if defined _NB if "!_NA!"=="!_NB!" set "_PSAME=1"
)
if /i not "!_QD!"=="KEEP" (
    set "_NC="
    set "_ND="
    set /a "_NC=!_PLAST!" >nul 2>&1
    set /a "_ND=!_QD!" >nul 2>&1
    if defined _NC if defined _ND (
        if not "!_NC!"=="!_ND!" set "_PSAME=0"
    ) else (
        set "_PSAME=0"
    )
)
if "!_PSAME!"=="1" (
    set /a WP_OP_OK+=1
    >>"%SESSION_LOG%" echo [%TIME%] [SAME] POWER !_QT!
    exit /b 0
)
powercfg /setacvalueindex SCHEME_CURRENT !_QS! !_QT! !_QA! >nul 2>&1
if errorlevel 1 (
    call :FAIL "powercfg AC !_QT! = !_QA!"
    exit /b 1
)
if /i not "!_QD!"=="KEEP" (
    powercfg /setdcvalueindex SCHEME_CURRENT !_QS! !_QT! !_QD! >nul 2>&1
    if errorlevel 1 call :WARN "powercfg DC !_QT! не применился, только AC"
)
powercfg /setactive SCHEME_CURRENT >nul 2>&1
call :OK "питание !_QT! AC=!_QA! DC=!_QD!"
exit /b 0

rem ============================================================
rem  NETSH_TCP  %1 param  %2 value  %3 дефолт Windows  %4 SOFT
rem  Прежнее состояние netsh не читается locale-независимо,
rem  в журнал идёт документированный дефолт.
rem  SOFT = отказ ожидаем (chimney на Win10+), считаем SKIP.
rem ============================================================
:NETSH_TCP
set "_NP=%~1"
set "_NV=%~2"
set "_ND=%~3"
set "_NS=%~4"
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo NETSH_TCP^|!_NP!^|!_NV!
    echo     [PLAN] tcp !_NP! = !_NV!
    set /a WP_OP_PLAN+=1
    exit /b 0
)
>>"%JOURNAL%" echo NETSH^|!_NP!^|!_ND!
netsh int tcp set global !_NP!=!_NV! >nul 2>&1
if errorlevel 1 (
    if /i "!_NS!"=="SOFT" (
        call :SKIP "tcp !_NP! не поддерживается этой сборкой"
        exit /b 0
    )
    call :FAIL "netsh tcp !_NP!=!_NV!"
    exit /b 1
)
call :OK "tcp !_NP! = !_NV!"
exit /b 0

rem ============================================================
rem  NETSH_SUPP  %1 template  %2 provider  %3 дефолт
rem ============================================================
:NETSH_SUPP
set "_NT=%~1"
set "_NC=%~2"
set "_ND=%~3"
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo NETSH_SUPP^|!_NT!^|!_NC!
    echo     [PLAN] supplemental !_NT! = !_NC!
    set /a WP_OP_PLAN+=1
    exit /b 0
)
>>"%JOURNAL%" echo NETSHSUPP^|!_NT!^|!_ND!
netsh int tcp set supplemental template=!_NT! congestionprovider=!_NC! >nul 2>&1
if errorlevel 1 (
    call :SKIP "supplemental !_NT! отклонён стеком"
    exit /b 0
)
call :OK "tcp supplemental !_NT! = !_NC!"
exit /b 0

rem ============================================================
rem  NET_FLUSH  %1 dns|arp - транзиентная операция, откат не нужен
rem ============================================================
:NET_FLUSH
set "_NF=%~1"
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo NET_FLUSH^|!_NF!
    echo     [PLAN] flush !_NF!
    set /a WP_OP_PLAN+=1
    exit /b 0
)
if /i "!_NF!"=="dns" goto :NET_FLUSH_DNS
if /i "!_NF!"=="arp" goto :NET_FLUSH_ARP
call :FAIL "NET_FLUSH: неизвестная цель !_NF!"
exit /b 1
:NET_FLUSH_DNS
ipconfig /flushdns >nul 2>&1
goto :NET_FLUSH_DONE
:NET_FLUSH_ARP
netsh int ip delete arpcache >nul 2>&1
:NET_FLUSH_DONE
if errorlevel 1 (
    call :WARN "flush !_NF! не удался"
    exit /b 0
)
call :OK "кэш !_NF! очищен"
exit /b 0

rem ============================================================
rem  FSUTIL_SET  %1 behavior  %2 value  %3 имя в FileSystem  %4 дефолт
rem  %3 = NONE для того, что не лежит в реестре (TRIM).
rem    disable8dot3        NtfsDisable8dot3NameCreation
rem    disablelastaccess   NtfsDisableLastAccessUpdate
rem    memoryusage         NtfsMemoryUsage
rem    encryptpagingfile   NtfsEncryptPagingFile
rem    disabledeletenotify NONE, дефолт 0
rem ============================================================
:FSUTIL_SET
set "_FB=%~1"
set "_FV=%~2"
set "_FR=%~3"
set "_FD=%~4"
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo FSUTIL^|!_FB!^|!_FV!
    echo     [PLAN] fsutil !_FB! = !_FV!
    set /a WP_OP_PLAN+=1
    exit /b 0
)
if /i not "!_FR!"=="NONE" (
    call :SNAP_REG "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" "!_FR!" "REG_DWORD" "!_FV!"
    if errorlevel 1 exit /b 1
    if "!_SNAP_STATE!"=="SAME" (
        set /a WP_OP_OK+=1
        exit /b 0
    )
) else (
    >>"%JOURNAL%" echo FSUTIL^|!_FB!^|!_FD!
)
fsutil behavior set !_FB! !_FV! >nul 2>&1
if errorlevel 1 (
    call :FAIL "fsutil behavior set !_FB! !_FV!"
    exit /b 1
)
call :OK "fsutil !_FB! = !_FV!"
exit /b 0

rem ============================================================
rem  TASK_DISABLE  %1 полный путь задачи
rem  Сохраняем исходный Enabled перед отключением задачи.
rem ============================================================
:TASK_DISABLE
set "_TP=%~1"
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo TASK_DISABLE^|!_TP!
    echo     [PLAN] task off !_TP!
    set /a WP_OP_PLAN+=1
    exit /b 0
)
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%WP_LIB%\wp.ps1" snapshot-task
set "_TASK_RC=!errorlevel!"
if "!_TASK_RC!"=="10" (
    call :SKIP "задача отсутствует: !_TP!"
    exit /b 0
)
if "!_TASK_RC!"=="11" (
    call :SKIP "задача уже отключена: !_TP!"
    exit /b 0
)
if not "!_TASK_RC!"=="12" (
    call :FAIL "Не удалось сохранить состояние задачи: !_TP!"
    exit /b 1
)
schtasks /change /tn "!_TP!" /disable >nul 2>&1
if errorlevel 1 (
    call :FAIL "schtasks disable !_TP!"
    exit /b 1
)
call :OK "задача отключена: !_TP!"
exit /b 0

rem ============================================================
rem  TASK_ENABLE - для отката, счётчик не трогает
rem ============================================================
:TASK_ENABLE
set "_TP=%~1"
schtasks /query /tn "!_TP!" >nul 2>&1
if errorlevel 1 exit /b 0
schtasks /change /tn "!_TP!" /enable >nul 2>&1
>>"%SESSION_LOG%" echo [%TIME%] [TASK] on !_TP!
exit /b 0

rem ============================================================
rem  PS_RUN  %1 verb  %2..%9 аргументы, любое количество
rem  Единственная точка входа в PowerShell. Возвращает реальный
rem  exit code из wp.ps1, а не всегдашний ноль.
rem  do-* в песочнице не выполняется, get-* выполняется всегда.
rem ============================================================
:PS_RUN
set "_PV=%~1"
set "_PA="
set "_DRYPS=0"
shift
if "%WP_DRYRUN%"=="1" (
    echo %_PV%| findstr /b /i /c:"do-" >nul 2>&1
    if not errorlevel 1 set "_DRYPS=1"
)
:PS_RUN_ARGS
if "%~1"=="" goto :PS_RUN_GO
set "_PARG=%~1"
set "_PARG=!_PARG:"=\"!"
if "!_PARG:~-1!"=="\" set "_PARG=!_PARG!\"
set "_PA=!_PA! "!_PARG!""
shift
goto :PS_RUN_ARGS
:PS_RUN_GO
if "!_DRYPS!"=="1" (
    >>"%PLAN_LOG%" echo PS_RUN^|%_PV%^|!_PA!
    echo     [PLAN] ps %_PV%
    set /a WP_OP_PLAN+=1
    exit /b 0
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%WP_LIB%\wp.ps1" %_PV% !_PA!
set "_PRC=!errorlevel!"
if not "!_PRC!"=="0" >>"%ERROR_LOG%" echo [%TIME%] wp.ps1 %_PV% exit=!_PRC! args=!_PA!
exit /b !_PRC!

rem ============================================================
rem  BLOCK_BEGIN  %1 ID блока  %2 ожидаемое число операций
rem  Вложенность блоков запрещена: базовые счётчики одни.
rem  Guard вызывается ДО BLOCK_BEGIN, иначе аудит соврёт.
rem ============================================================
:BLOCK_BEGIN
set "WP_BLOCK=%~1"
set "WP_BLOCK_OPS=%~2"
if not defined WP_OP_EXPECTED set /a WP_OP_EXPECTED=0
set /a WP_OP_EXPECTED+=%~2
set /a "_B_OK0=WP_OP_OK"
set /a "_B_FAIL0=WP_OP_FAIL"
set /a "_B_SKIP0=WP_OP_SKIP"
set /a "_B_PLAN0=WP_OP_PLAN"
echo.
if defined WP_DESKTOP_TOKEN echo !WP_DESKTOP_TOKEN!:begin^|!WP_BLOCK!
echo -- %WP_BLOCK% --
>>"%SESSION_LOG%" echo [%TIME%] BEGIN %WP_BLOCK% expected=%WP_BLOCK_OPS%
exit /b 0

rem ============================================================
rem  BLOCK_END - дельта счётчиков и самоаудит количества.
rem  Расхождение с ожиданием = потерянный твик, видно сразу.
rem ============================================================
:BLOCK_END
set /a "_DOK=WP_OP_OK-_B_OK0"
set /a "_DFAIL=WP_OP_FAIL-_B_FAIL0"
set /a "_DSKIP=WP_OP_SKIP-_B_SKIP0"
set /a "_DPLAN=WP_OP_PLAN-_B_PLAN0"
set /a "WP_MODE_OK+=_DOK"
set /a "WP_MODE_FAIL+=_DFAIL"
set /a "WP_MODE_SKIP+=_DSKIP"
set /a "WP_MODE_PLAN+=_DPLAN"
set /a "_DTOT=_DOK+_DFAIL+_DSKIP+_DPLAN"
if !_DOK!   gtr 0 set "WP_APPLIED_BLOCKS=!WP_APPLIED_BLOCKS! %WP_BLOCK%"
if !_DPLAN! gtr 0 set "WP_APPLIED_BLOCKS=!WP_APPLIED_BLOCKS! %WP_BLOCK%"
if !_DSKIP! gtr 0 set "WP_SKIPPED_BLOCKS=!WP_SKIPPED_BLOCKS! %WP_BLOCK%"
if !_DFAIL! gtr 0 set "WP_FAILED_BLOCKS=!WP_FAILED_BLOCKS! %WP_BLOCK%"
if defined WP_BLOCK_OPS (
    if not "!_DTOT!"=="%WP_BLOCK_OPS%" call :WARN "блок %WP_BLOCK%: операций !_DTOT!, ожидалось %WP_BLOCK_OPS%"
)
if defined WP_DESKTOP_TOKEN echo !WP_DESKTOP_TOKEN!:done^|!WP_BLOCK!^|!_DOK!^|!_DFAIL!^|!_DSKIP!^|!_DPLAN!
echo   -- %WP_BLOCK%: ok=!_DOK! fail=!_DFAIL! skip=!_DSKIP! plan=!_DPLAN!
>>"%SESSION_LOG%" echo [%TIME%] END %WP_BLOCK% ok=!_DOK! fail=!_DFAIL! skip=!_DSKIP! plan=!_DPLAN! total=!_DTOT!
exit /b 0

rem ============================================================
rem  AGG_BEGIN / AGG_END  %1 описание
rem  Группа записей считается ОДНОЙ операцией по списку твиков,
rem  но в журнал попадает каждая. Нужно для Nagle по адаптерам,
rem  IFEO по приложениям, ULPS по экземплярам GPU, C-states.
rem ============================================================
:AGG_BEGIN
set /a "_AG_OK=WP_OP_OK"
set /a "_AG_FAIL=WP_OP_FAIL"
set /a "_AG_SKIP=WP_OP_SKIP"
set /a "_AG_PLAN=WP_OP_PLAN"
exit /b 0

:AGG_END
set /a "_AD_OK=WP_OP_OK-_AG_OK"
set /a "_AD_FAIL=WP_OP_FAIL-_AG_FAIL"
set /a "_AD_SKIP=WP_OP_SKIP-_AG_SKIP"
set /a "_AD_PLAN=WP_OP_PLAN-_AG_PLAN"
set /a "WP_OP_OK=_AG_OK"
set /a "WP_OP_FAIL=_AG_FAIL"
set /a "WP_OP_SKIP=_AG_SKIP"
set /a "WP_OP_PLAN=_AG_PLAN"
if !_AD_FAIL! gtr 0 (
    call :FAIL "%~1: отказов !_AD_FAIL!"
    exit /b 1
)
if !_AD_PLAN! gtr 0 (
    call :PLAN "%~1"
    exit /b 0
)
if !_AD_OK! equ 0 (
    call :SKIP "%~1: нечего менять"
    exit /b 0
)
call :OK "%~1: записей !_AD_OK!"
exit /b 0

rem ============================================================
rem  IRREVERSIBLE  %1 описание. Откат пропустит и покажет списком.
rem ============================================================
:IRREVERSIBLE
set "_M=%~1"
set "WP_IRREVERSIBLE=1"
>>"%JOURNAL%" echo IRREVERSIBLE^|!_M!
>>"%SESSION_LOG%" echo [%TIME%] [IRREV] !_M!
exit /b 0

rem ============================================================
rem  PURGE_FILES  %1 полная маска  %2 S рекурсивно / N нет
rem  Признаёт частичный провал: залоченные Explorer-ом файлы
rem  остаются, и рапортовать OK как ни в чём не бывало - вранье.
rem ============================================================
:PURGE_FILES
set "_PF=%~1"
set "_PR=%~2"
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo PURGE^|!_PF!
    echo     [PLAN] purge !_PF!
    set /a WP_OP_PLAN+=1
    exit /b 0
)
if not exist "!_PF!" (
    set /a WP_OP_SKIP+=1
    exit /b 0
)
if /i "!_PR!"=="S" (
    del /f /s /q "!_PF!" >nul 2>&1
) else (
    del /f /q "!_PF!" >nul 2>&1
)
if exist "!_PF!" (
    >>"%SESSION_LOG%" echo [%TIME%] [PURGE-PARTIAL] !_PF!
    call :WARN "часть файлов занята процессом: !_PF!"
)
call :IRREVERSIBLE "purge !_PF!"
set /a WP_OP_OK+=1
>>"%SESSION_LOG%" echo [%TIME%] [PURGE] !_PF!
exit /b 0

rem ============================================================
rem  PAUSE_SAFE - пауза, уважающая песочницу и unattended
rem ============================================================

:PAUSE_SAFE
if "%WP_UNATTENDED%"=="1" exit /b 0
echo.
echo   Нажмите любую клавишу для возврата в меню...
call "%WP_LIB%\desktop_io.cmd" wait
exit /b 0

rem ============================================================
rem  PLAN_NOTE  пояснение к плану: экран и лог сессии.
rem  БЕЗ записи в plan.txt и БЕЗ инкремента счётчика.
rem ============================================================
:PLAN_NOTE
echo   [PLAN] %~1
>>"%SESSION_LOG%" echo [%TIME%] [PLAN-NOTE] %~1
exit /b 0

rem ============================================================
rem  LNK_MOVE  %1 полный путь к ярлыку. Перенос в подпапку Disabled.
rem  Журнал LNKMOVE|src|dst, откат возвращает файл на место.
rem ============================================================
:LNK_MOVE
set "_LM=%~1"
if not exist "!_LM!" (
    call :SKIP "LNK_MOVE: файл не найден"
    exit /b 0
)
set "_LD=%~dp1Disabled"
set "_LF=%~nx1"
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo LNK_MOVE^|!_LM!^|!_LD!\!_LF!
    echo   [PLAN] LNK_MOVE !_LF!
    set /a WP_OP_PLAN+=1
    exit /b 0
)
if not exist "!_LD!" mkdir "!_LD!" >nul 2>&1
move /y "!_LM!" "!_LD!\!_LF!" >nul 2>&1
if errorlevel 1 (
    call :FAIL "LNK_MOVE !_LF!"
    exit /b 1
)
>>"%JOURNAL%" echo LNKMOVE^|!_LM!^|!_LD!\!_LF!
call :OK "LNK_MOVE !_LF! в Disabled"
exit /b 0
rem ============================================================
rem  PURGE_DIR  %1 полный путь к каталогу. Удаление дерева.
rem  del не берёт каталоги, поэтому отдельный примитив.
rem ============================================================
:PURGE_DIR
set "_PD=%~1"
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo PURGEDIR^|!_PD!
    echo   [PLAN] purge dir !_PD!
    set /a WP_OP_PLAN+=1
    exit /b 0
)
if not exist "!_PD!\" (
    set /a WP_OP_SKIP+=1
    exit /b 0
)
rd /s /q "!_PD!" >nul 2>&1
if exist "!_PD!\" (
    >>"%SESSION_LOG%" echo [%TIME%] [PURGEDIR-PARTIAL] !_PD!
    call :WARN "часть дерева занята процессом: !_PD!"
)
call :IRREVERSIBLE "purge dir !_PD!"
set /a WP_OP_OK+=1
>>"%SESSION_LOG%" echo [%TIME%] [PURGEDIR] !_PD!
exit /b 0

rem ============================================================
rem  DISM_RUN  %1 аргументы Cleanup-Image  %2 подпись для лога
rem  Код 3010 - успех с требованием перезагрузки, не отказ.
rem ============================================================
:DISM_RUN
set "_DR=%~1"
set "_DL=%~2"
if "%WP_DRYRUN%"=="1" (
    >>"%PLAN_LOG%" echo DISM^|!_DR!
    echo   [PLAN] DISM !_DL!
    set /a WP_OP_PLAN+=1
    exit /b 0
)
call :MSG "DISM !_DL!: от 5 до 20 минут, окно не закрывать"
Dism /Online /Cleanup-Image !_DR! >nul 2>&1
set "_DE=!errorlevel!"
if !_DE! equ 3010 set "WP_REBOOT_REQUIRED=1"
if not !_DE! equ 0 if not !_DE! equ 3010 (
    call :FAIL "DISM !_DL! код !_DE!"
    exit /b 1
)
call :IRREVERSIBLE "DISM !_DL!"
set /a WP_OP_OK+=1
>>"%SESSION_LOG%" echo [%TIME%] [DISM] !_DL! rc=!_DE!
call :MSG "DISM !_DL! завершён"
exit /b 0
:: END OF FILE | Всего твиков в файле: 0
@echo off
rem Native batch prompts and the WPF stream share the same return values.
if "%~1"=="choice" goto :choice
if "%~1"=="input" goto :input
if "%~1"=="wait" goto :wait
exit /b 2

:choice
if defined WP_DESKTOP_TOKEN goto :desktop_choice
choice /c %~2 /n /m "!WP_QUESTION!"
exit /b %errorlevel%

:desktop_choice
echo !WP_DESKTOP_TOKEN!:choice^|%~2^|!WP_QUESTION!
call :receive
set "_ui_keys=%~2"
set /a _ui_index=0
:next_key
set /a _ui_index+=1
if not defined _ui_keys goto :desktop_choice
if /i "!_ui_keys:~0,1!"=="!_ui_reply!" exit /b !_ui_index!
set "_ui_keys=!_ui_keys:~1!"
goto :next_key

:input
if defined WP_DESKTOP_TOKEN goto :desktop_input
set /p "%~2=!WP_QUESTION!"
exit /b %errorlevel%

:desktop_input
echo !WP_DESKTOP_TOKEN!:input^|%~2^|!WP_QUESTION!
call :receive
if defined _ui_reply set "%~2=!_ui_reply!"
exit /b 0

:wait
if not defined WP_DESKTOP_TOKEN (
    if "%~2"=="visible" (pause) else pause >nul
    exit /b 0
)
echo !WP_DESKTOP_TOKEN!:wait
call :receive
exit /b 0

:receive
set "_ui_reply="
set /p "_ui_reply="
rem A closed pipe or an invalid frame terminates this private interpreter.
if not "!_ui_reply:~0,1!"==":" exit 1223
set "_ui_reply=!_ui_reply:~1!"
exit /b 0

:: END OF FILE | Всего твиков в файле: 0

@echo off
setlocal
chcp 65001 >nul
title Reactor Relay Incremental Evaluation
set "ROOT=%~dp0"
set "GAME=%ROOT%candidate\ReactorRelayCandidate_SourceBuilt.rbxlx"
set "SOURCE=%ROOT%candidate\ReactorRelayCandidate_Source.zip"
echo Reactor Relay incremental supplemental evaluation
echo Completed checks are retained; only missing retry segments are executed.
echo Do not use the keyboard or mouse until the run completes.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%run-incremental.ps1" -Game "%GAME%" -SourceZip "%SOURCE%"
set "EXITCODE=%ERRORLEVEL%"
if "%EXITCODE%"=="0" echo [DONE] Report: "%ROOT%evaluation-report.json"
if not "%EXITCODE%"=="0" echo [INCOMPLETE OR FAILED] Exit code: %EXITCODE%
pause
exit /b %EXITCODE%

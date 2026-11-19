@echo off
setlocal
chcp 65001 >nul
title Reactor Relay Yue2 Evaluation
set "ROOT=%~dp0"
set "GAME=%ROOT%candidate\ReactorRelayCandidate_SourceBuilt.rbxlx"
set "SOURCE=%ROOT%candidate\ReactorRelayCandidate_Source.zip"
echo Reactor Relay Protocol hard-variant real-input evaluation
echo Uses the frozen D1-D6 criteria and the 18-second/Arm/8-symbol trajectory.
echo Do not use the keyboard or mouse until the run completes.
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%run-evaluation.ps1" -Game "%GAME%" -SourceZip "%SOURCE%"
set "EXITCODE=%ERRORLEVEL%"
echo.
if not "%EXITCODE%"=="0" echo [INCOMPLETE OR FAILED] Exit code: %EXITCODE%
if "%EXITCODE%"=="0" echo [DONE] Evaluation report: "%ROOT%evaluation-report.json"
pause
exit /b %EXITCODE%

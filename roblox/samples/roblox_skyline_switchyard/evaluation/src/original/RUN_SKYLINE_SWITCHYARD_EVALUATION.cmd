@echo off
setlocal
title Skyline Switchyard Full Package 20261026 Evaluator
pushd "%~dp0"
echo Verifying the supplied Place and archived source and compiling candidate scripts first.
echo A compile error stops the run before Studio, with no gameplay score.
echo If preflight passes, close Studio windows; tests use the published HUD buttons and real keyboard input.
set "PYTHONUTF8=1"
set "SY_PYTHON="
if exist "E:\python\python.exe" set "SY_PYTHON=E:\python\python.exe"
if defined SY_PYTHON goto run_direct
where py.exe >nul 2>nul
if not errorlevel 1 goto run_py
where python.exe >nul 2>nul
if not errorlevel 1 goto run_python
echo ERROR: Python 3 was not found.
set "SY_EXIT=9009"
goto finish
:run_direct
"%SY_PYTHON%" "%~dp0run.py" %*
set "SY_EXIT=%errorlevel%"
goto finish
:run_py
py.exe -3 "%~dp0run.py" %*
set "SY_EXIT=%errorlevel%"
goto finish
:run_python
python.exe "%~dp0run.py" %*
set "SY_EXIT=%errorlevel%"
:finish
echo Exit code: %SY_EXIT%
if not "%SY_EXIT%"=="0" echo Check the latest evidence directory for incomplete checks or errors.
if /I "%~1"=="--self-test" goto exit_now
if /I "%~1"=="--preflight-only" goto exit_now
pause
:exit_now
popd
exit /b %SY_EXIT%

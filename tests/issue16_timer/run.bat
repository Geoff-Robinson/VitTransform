@echo off
cd /d "%~dp0"
if not exist TimerHarness.exe (
  echo TimerHarness.exe not found - build TimerHarness.sln with Clarion first.
  exit /b 2
)
TimerHarness.exe
set RC=%ERRORLEVEL%
echo ---- result.txt ----
type result.txt
exit /b %RC%

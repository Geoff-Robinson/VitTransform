@echo off
cd /d "%~dp0"
if not exist MoveToksHarness.exe (
  echo MoveToksHarness.exe not found - build MoveToksHarness.sln with Clarion first.
  exit /b 2
)
MoveToksHarness.exe
set RC=%ERRORLEVEL%
echo ---- result.txt ----
type result.txt
exit /b %RC%

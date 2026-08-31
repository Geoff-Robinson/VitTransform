@echo off
cd /d "%~dp0"
if not exist ConfigDefaultHarness.exe (
  echo ConfigDefaultHarness.exe not found - build ConfigDefaultHarness.sln with Clarion first.
  exit /b 2
)
ConfigDefaultHarness.exe
set RC=%ERRORLEVEL%
echo ---- result.txt ----
type result.txt
exit /b %RC%

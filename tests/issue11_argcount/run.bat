@echo off
cd /d "%~dp0"
if not exist ArgCountHarness.exe (
  echo ArgCountHarness.exe not found - build ArgCountHarness.sln with Clarion first.
  exit /b 2
)
ArgCountHarness.exe
set RC=%ERRORLEVEL%
echo ---- result.txt ----
type result.txt
exit /b %RC%

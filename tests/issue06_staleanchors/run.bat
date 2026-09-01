@echo off
cd /d "%~dp0"
if not exist StaleAnchorHarness.exe (
  echo StaleAnchorHarness.exe not found - build StaleAnchorHarness.sln with Clarion first.
  exit /b 2
)
StaleAnchorHarness.exe
set RC=%ERRORLEVEL%
echo ---- result.txt ----
type result.txt
exit /b %RC%

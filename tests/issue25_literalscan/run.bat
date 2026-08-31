@echo off
cd /d "%~dp0"
if not exist LiteralScanHarness.exe (
  echo LiteralScanHarness.exe not found - build LiteralScanHarness.sln with Clarion first.
  exit /b 2
)
LiteralScanHarness.exe
set RC=%ERRORLEVEL%
echo ---- result.txt ----
type result.txt
exit /b %RC%

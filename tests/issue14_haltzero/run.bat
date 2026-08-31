@echo off
cd /d "%~dp0"
if not exist HaltZero.exe (
  echo HaltZero.exe not found - build HaltZero.sln with Clarion first.
  exit /b 2
)
HaltZero.exe
echo bare halt() returned exit code %ERRORLEVEL% - VitStyle uses this on both fatal startup paths (VitStyle.clw:343, :555)

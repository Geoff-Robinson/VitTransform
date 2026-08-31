@echo off
rem Builds every CompileCheck.cwproj under tests\ - proves the test
rem inputs are valid Clarion before they are used against the tool.
rem Requires Clarion 12 + StringTheory, like the main apps.
setlocal enabledelayedexpansion
set MSB=%WINDIR%\Microsoft.NET\Framework4.0.30319\MSBuild.exe
set CLB=C:\Clarion\Clarion12-12.0.14204in
set FAILED=
for /d %%d in (issue*) do (
  if exist "%%d\CompileCheck.cwproj" (
    pushd "%%d"
    "%MSB%" CompileCheck.cwproj "-p:ClarionBinPath=%CLB%" -nologo -v:q >nul 2>&1
    if exist CompileCheck.exe (echo PASS %%d) else (echo FAIL %%d& set FAILED=1)
    popd
  )
)
if defined FAILED (exit /b 1) else (echo all test inputs compile& exit /b 0)

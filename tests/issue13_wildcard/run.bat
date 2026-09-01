@echo off
cd /d "%~dp0"
if exist out rmdir /s /q out
mkdir out
echo -- run 1: src\* (subfolder present; processed cleanly on build 253) --
..\..\VitTransform.exe ..\..\vitrules.txt src\* out --batch
echo exit %ERRORLEVEL%
echo -- run 2: src\*.xyz (matches NOTHING - should not report success) --
..\..\VitTransform.exe ..\..\vitrules.txt src\*.xyz out --batch
echo exit %ERRORLEVEL% (bug: 0 despite transforming nothing)

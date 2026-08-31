@echo off
cd /d "%~dp0"
if exist out rmdir /s /q out
mkdir out
del /q "rules.txt on *" 2>nul
..\..\VitTransform.exe rules.txt in.clw out --batch
echo.
echo ---- transformed output ----
type out\in.clw

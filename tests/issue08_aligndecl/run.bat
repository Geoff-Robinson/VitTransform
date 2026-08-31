@echo off
cd /d "%~dp0"
if exist out rmdir /s /q out
mkdir out
..\..\VitTransform.exe ..\..itrules.txt in.clw out --width=40 --only=1201 --batch
echo.
echo ---- transformed output (out\in.clw) ----
type out\in.clw

@echo off
cd /d "%~dp0"
if exist out rmdir /s /q out
mkdir out
..\..\VitTransform.exe ..\..itrules.txt in.clw out --group=deadchoose --batch
echo.
echo ---- transformed output ----
type out\in.clw

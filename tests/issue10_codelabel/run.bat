@echo off
cd /d "%~dp0"
if exist out rmdir /s /q out
mkdir out
..\..\VitTransform.exe ..\..\vitrules.txt in.clw out --only=1187 --batch
echo.
echo ---- transformed output (out\in.clw) ----
type out\in.clw

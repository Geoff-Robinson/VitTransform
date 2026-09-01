@echo off
cd /d "%~dp0"
if exist out rmdir /s /q out
mkdir out
..\..\VitTransform.exe ..\..\vitrules.txt main.clw out --thorough --batch
echo exit %ERRORLEVEL%
for %%f in ("..\..\vitrules.txt on *.report.txt") do findstr /c:"INCLUDE not found" "%%f"

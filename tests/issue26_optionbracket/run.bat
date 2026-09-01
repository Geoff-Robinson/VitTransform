@echo off
cd /d "%~dp0"
del /q "rules.txt on *" 2>nul
..\..\VitTransform.exe rules.txt --batch
echo exit %ERRORLEVEL%
for %%f in ("rules.txt on *.ir.txt") do findstr /c:"rule" /c:"skip" /c:"SKIP" "%%f"

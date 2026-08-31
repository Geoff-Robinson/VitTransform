@echo off
cd /d "%~dp0"
del /q "rules.txt on *" 2>nul
echo A modal summary box will appear even though --batch is given - that IS the bug.
echo Click OK to let it exit.
..\..\VitTransform.exe rules.txt --summary --batch
echo exit code %ERRORLEVEL%

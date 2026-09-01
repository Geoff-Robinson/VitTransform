@echo off
cd /d "%~dp0"
del /q "rules.txt on *" 2>nul
..\..\VitTransform.exe rules.txt --batch
echo exit code %ERRORLEVEL% (release: clean error below; a DEBUG build traps before any report)
type "rules.txt on "*.ir.txt 2>nul
type vt-batch.log 2>nul

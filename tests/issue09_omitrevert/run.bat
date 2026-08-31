@echo off
cd /d "%~dp0"
if exist out rmdir /s /q out
mkdir out
del /q in.clw.tokens.txt 2>nul
..\..\VitTransform.exe ..\..itrules.txt in.clw out --only=1185 --dumptokens --thorough --batch
echo.
echo ---- token dump, the two call lines (Omit has a hole, OmitX does not) ----
findstr /n "." in.clw.tokens.txt | findstr "38- 39-"

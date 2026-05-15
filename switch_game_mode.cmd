@echo off
chcp 65001 >nul
:: 65001 - UTF-8
setlocal enabledelayedexpansion

cd /d "%~dp0"
set BIN=%~dp0bin\
set GMODE_FLAG_FILE=%BIN%gmode.flag

if exist "%GMODE_FLAG_FILE%" (
    del "%GMODE_FLAG_FILE%"
	echo Игровой режим ❌ ВЫКЛЮЧЕН!
) else (
    type nul > "%GMODE_FLAG_FILE%"
    echo Игровой режим ✅ ВКЛЮЧЕН!
)

echo.
echo Нажмите Enter для выхода ...

pause >nul
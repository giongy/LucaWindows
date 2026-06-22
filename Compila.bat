@echo off
setlocal
title Compila VolumePowerTray

rem --- Percorsi ---
set "DIR=%~dp0"
set "AHK2EXE=C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe"
set "BASE=C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
set "IN=%DIR%VolumePowerTray.ahk"
set "OUT=%DIR%VolumePowerTray.exe"
set "ICON=%DIR%VolumePowerTray.ico"

rem --- Controlli preliminari ---
if not exist "%AHK2EXE%" (
    echo [ERRORE] Ahk2Exe non trovato in:
    echo    %AHK2EXE%
    pause & exit /b 1
)
if not exist "%IN%" (
    echo [ERRORE] Sorgente non trovato in:
    echo    %IN%
    pause & exit /b 1
)

rem --- Chiude l'eventuale istanza in esecuzione (altrimenti l'exe e' bloccato) ---
echo Chiudo eventuali istanze in esecuzione...
taskkill /IM VolumePowerTray.exe /F >nul 2>&1

rem --- Compilazione ---
echo Compilazione in corso...
"%AHK2EXE%" /in "%IN%" /out "%OUT%" /icon "%ICON%" /base "%BASE%" /silent

if errorlevel 1 (
    echo.
    echo [ERRORE] Compilazione fallita.
    pause & exit /b 1
)

echo.
echo [OK] Creato: "%OUT%"
echo.

choice /c SN /n /m "Avviare ora il programma? [S/N] "
if errorlevel 2 goto :fine
start "" "%OUT%"

:fine
endlocal

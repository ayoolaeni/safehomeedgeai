@echo off
REM -----------------------------------------------------------------------
REM DEVELOPER USE ONLY. Run this after changing any firmware file.
REM It builds the lamp software and copies it into docs\flash\, which is the
REM page the client uses to install it. Then commit and push as usual.
REM The client never needs to run this file.
REM -----------------------------------------------------------------------

set ARDUINO_CLI="C:\Program Files\Arduino CLI\arduino-cli.exe"
set ROOT=%~dp0..
set SKETCH=%~dp0safehome_esp32
set OUT=%~dp0build
set FLASH=%ROOT%\docs\flash
set BOOT_APP0=%LOCALAPPDATA%\Arduino15\packages\esp32\hardware\esp32\3.3.11\tools\partitions\boot_app0.bin

echo Building the firmware...
%ARDUINO_CLI% compile --fqbn esp32:esp32:esp32 --output-dir "%OUT%" "%SKETCH%"
if errorlevel 1 (
  echo.
  echo BUILD FAILED. Nothing was copied. Fix the error above and try again.
  pause
  exit /b 1
)

echo Copying the files for the install page...
copy /Y "%OUT%\safehome_esp32.ino.bootloader.bin" "%FLASH%\bootloader.bin" >nul
copy /Y "%OUT%\safehome_esp32.ino.partitions.bin" "%FLASH%\partitions.bin" >nul
copy /Y "%OUT%\safehome_esp32.ino.bin" "%FLASH%\app.bin" >nul
copy /Y "%BOOT_APP0%" "%FLASH%\boot_app0.bin" >nul

echo.
echo DONE. The install page now has the new firmware.
echo Commit and push docs\flash\ to GitHub so the client gets it.
pause

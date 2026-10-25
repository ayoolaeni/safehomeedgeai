@echo off
REM Starts the SafeHome home server from source (needs Python 3.11+).
REM The client uses safehome-server.exe instead and does not need this file.
cd /d %~dp0
python -m pip install --quiet -r requirements.txt
python -m thdt
pause

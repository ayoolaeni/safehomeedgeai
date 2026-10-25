@echo off
REM -----------------------------------------------------------------------
REM DEVELOPER USE ONLY. Builds dist\safehome-server.exe, a single file the
REM client can run without installing Python. Run the tests first.
REM -----------------------------------------------------------------------
cd /d %~dp0

echo Running the tests...
python -W ignore -m unittest discover -s tests
if errorlevel 1 (
  echo TESTS FAILED. Nothing was built.
  pause
  exit /b 1
)

echo Installing the build tools...
python -m pip install --quiet -r requirements.txt pyinstaller==6.11.1
if errorlevel 1 goto :fail

echo Building safehome-server.exe...
python -m PyInstaller --noconfirm --onefile --console --name safehome-server run_server.py
if errorlevel 1 goto :fail

echo.
echo DONE: %~dp0dist\safehome-server.exe
pause
exit /b 0

:fail
echo BUILD FAILED. See the messages above.
pause
exit /b 1

@echo off
setlocal
cd /d "%~dp0\.."
python tool\bootstrap_platforms.py
endlocal

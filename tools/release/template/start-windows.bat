@echo off
rem BlockMash - start locally (Windows). Needs Node.js >= 18 or Python 3.
cd /d "%~dp0"
where node >nul 2>nul && (node serve.mjs %* & goto :eof)
where py >nul 2>nul && (py -3 serve.py %* & goto :eof)
where python >nul 2>nul && (python serve.py %* & goto :eof)
echo Please install Node.js (https://nodejs.org) or Python 3 (https://python.org).
pause

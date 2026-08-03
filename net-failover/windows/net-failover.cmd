@echo off
rem CLI shim so 'net-failover -Status' works from any shell once
rem C:\Program Files\net-failover is on PATH. powershell.exe (5.1) is used
rem because it exists on every Windows box; the script itself also runs on 7+.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0net-failover.ps1" %*
exit /b %ERRORLEVEL%

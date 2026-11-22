@echo off
REM OpenVPN route-up 钩子（Windows）：让隧道接口流量穿过防火墙
setlocal
set DEV=%3
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\ProgramData\openvpn-wm\killswitch.ps1" -Action enable -Dev "%DEV%"
endlocal

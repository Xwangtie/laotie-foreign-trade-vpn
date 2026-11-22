@echo off
REM OpenVPN route-pre-down 钩子（Windows）
REM close-* 保留防火墙断网保护（仅撤隧道放行）；open 模式恢复全放行
set DEV=%3
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\ProgramData\openvpn-wm\killswitch.ps1" -Action vpn-down -Dev "%DEV%"
endlocal

@echo off
REM unlock-network.bat — Windows 紧急逃生门（不依赖网络）
echo 正在恢复 Windows 防火墙默认策略与 DNS...
netsh advfirewall reset
schtasks /End /TN openvpnwm-failwatch 2>NUL
echo 已解除封锁。如需继续使用 VPN，请重新连接。

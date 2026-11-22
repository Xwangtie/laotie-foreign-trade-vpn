param(
    [ValidateSet("open", "close-all", "close-foreign")][string]$Mode = ""
)
# fail-watch.ps1 — Windows 看门狗（计划任务每 1 分钟调用一次）
$ErrorActionPreference = "SilentlyContinue"
$destDir = Join-Path $env:ProgramData "openvpn-wm"
$logFile = Join-Path $env:ProgramData "openvpn-wm\fail-watch.log"

if (-not $Mode -and (Test-Path (Join-Path $destDir "profile.env"))) {
    $line = Get-Content (Join-Path $destDir "profile.env") | Where-Object { $_ -match '^FAILMODE=' } | Select-Object -First 1
    if ($line) { $Mode = ($line -split "=", 2)[1] }
}

$alive = Get-Process | Where-Object { $_.ProcessName -like "openvpn*" }
$ok = $false
if ($alive) {
    $ok = Test-Connection -ComputerName 10.8.0.1 -Count 1 -Quiet -ErrorAction SilentlyContinue
}

if (-not $ok) {
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content $logFile "$stamp VPN 不可达 mode=$Mode"
    if ($Mode -eq "open") {
        # 回落本地：OpenVPN 退出时系统已自动删除路由；此处仅补日志
        Add-Content $logFile "$stamp fail-open：请确认流量已回落到本地网络"
    } else {
        Add-Content $logFile "$stamp fail-close：当前处于断网保护，请运行 unlock-network.bat 紧急恢复"
    }
}

param()
$ErrorActionPreference = "Stop"
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw "请以管理员身份运行。" }

$destDir = Join-Path $env:ProgramData "openvpn-wm"
& (Join-Path $destDir "killswitch.ps1") -Action disable 2>$null
Unregister-ScheduledTask -TaskName "openvpnwm-failwatch" -Confirm:$false 2>$null
netsh advfirewall reset | Out-Null
$openvpnConfig = Join-Path $env:ProgramData "OpenVPN\config"
if (Test-Path $openvpnConfig) {
    Get-ChildItem $openvpnConfig -Filter "*.ovpn" | ForEach-Object {
        if (Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue -match "block-outside-dns") {
            Remove-Item -Force $_.FullName -ErrorAction SilentlyContinue
        }
    }
}
Remove-Item -Recurse -Force $destDir -ErrorAction SilentlyContinue
Write-Host "✅ 已卸载并恢复 Windows 防火墙默认策略。"

param(
    [Parameter(Mandatory = $true)][string]$OvpnPath,
    [string]$CnListPath = ""
)
# install-client.ps1 — Windows 安装器（须以管理员运行）
# 用法: .\install-client.ps1 -OvpnPath C:\path\xxx.ovpn
$ErrorActionPreference = "Stop"

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    throw "请以管理员身份运行 PowerShell。"
}
if (-not (Test-Path $OvpnPath)) {
    throw "找不到 .ovpn 文件: $OvpnPath"
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$destDir = Join-Path $env:ProgramData "openvpn-wm"
New-Item -ItemType Directory -Force -Path $destDir | Out-Null

$header = @{}
Get-Content $OvpnPath | ForEach-Object {
    if ($_ -match '^#\s*([A-Z]+)=(.*)$') {
        $key = $matches[1]
        if (-not $header.ContainsKey($key)) {
            $header[$key] = $matches[2].Trim()
        }
    }
}
foreach ($k in @("PROFILE", "FAILMODE", "SPLIT", "SERVER", "PORT")) {
    if (-not $header.ContainsKey($k)) {
        throw ".ovpn 文件头缺少 # $k= 行（S1 契约），拒绝安装。"
    }
}
if ($header["FAILMODE"] -notin @("close-all", "close-foreign", "open")) {
    throw "未知 FAILMODE: $($header['FAILMODE'])"
}

# 安装配置文件（供 OpenVPN GUI/服务使用）
$ovpnDest = Join-Path $destDir "client.ovpn"
Copy-Item -Force $OvpnPath $ovpnDest
$extra = @(
    "",
    "block-outside-dns",
    "register-dns",
    "script-security 2",
    'route-up "C:\ProgramData\openvpn-wm\route-up.cmd"',
    'route-pre-down "C:\ProgramData\openvpn-wm\route-down.cmd"'
)
Add-Content -Path $ovpnDest -Value $extra

# 写入元数据
$profileContent = @(
    "PROFILE=$($header['PROFILE'])",
    "FAILMODE=$($header['FAILMODE'])",
    "SPLIT=$($header['SPLIT'])",
    "SERVER=$($header['SERVER'])",
    "PORT=$($header['PORT'])",
    "SOURCE_OVPN=$OvpnPath"
)
Set-Content -Path (Join-Path $destDir "profile.env") -Value $profileContent -Encoding ASCII

# CN 表
if ($header["SPLIT"] -eq "cn-bypass") {
    if (-not $CnListPath) {
        $CnListPath = Join-Path $scriptDir "..\..\shared\data\cn-ipv4.txt"
    }
    if (Test-Path $CnListPath) {
        Copy-Item -Force $CnListPath (Join-Path $destDir "cn-ipv4.txt")
    } else {
        Set-Content -Path (Join-Path $destDir "cn-ipv4.txt") -Value "" -Encoding ASCII
        Write-Warning "未找到 CN 数据文件，cn-ipv4.txt 为空；close-foreign 将退化为 close-all。"
    }
}

# 复制辅助脚本
foreach ($f in @("killswitch.ps1", "fail-watch.ps1", "route-up.cmd", "route-down.cmd")) {
    Copy-Item -Force (Join-Path $scriptDir $f) (Join-Path $destDir $f)
}

# 放到 OpenVPN 自动加载目录（若安装了 OpenVPN 服务）
$openvpnConfig = Join-Path $env:ProgramData "OpenVPN\config"
if (Test-Path $openvpnConfig) {
    Copy-Item -Force $ovpnDest (Join-Path $openvpnConfig "$($header['PROFILE']).ovpn")
    Write-Host "已放入 OpenVPN 自动加载目录: $openvpnConfig"
}

# fail-open 看门狗计划任务
if ($header["FAILMODE"] -eq "open") {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $destDir 'fail-watch.ps1')`" -Mode open"
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName "openvpnwm-failwatch" -Action $action -Trigger $trigger -Force | Out-Null
}

Write-Host "✅ 安装完成"
Write-Host "   方案: $($header['PROFILE'])  断线策略: $($header['FAILMODE'])"
Write-Host "   OpenVPN 配置: $ovpnDest"
Write-Host "   紧急解除（断网自救）: 双击 $destDir\unlock-network.bat 或运行 netsh advfirewall reset"
Write-Host "⚠️  Windows 代码尚未实机验证，正式发放前必须在真实 Windows 机器上验收。"

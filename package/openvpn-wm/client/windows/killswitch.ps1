param(
    [Parameter(Mandatory = $true)][ValidateSet("enable", "disable", "vpn-down", "status")][string]$Action,
    [ValidateSet("close-all", "close-foreign", "open")][string]$Mode = "",
    [string]$Dev = ""
)
# killswitch.ps1 — Windows 防火墙断线策略
# close-all: 默认阻止出站，仅放行 openvpn.exe/VPN服务器/局域网/隧道接口
# close-foreign: 额外放行国内 CN 网段（分批建规则）
$ErrorActionPreference = "Stop"
$prefix = "openvpnwm"
$destDir = Join-Path $env:ProgramData "openvpn-wm"
$profileFile = Join-Path $destDir "profile.env"

function Read-Meta {
    param([string]$Key)
    if (Test-Path $profileFile) {
        $line = Get-Content $profileFile | Where-Object { $_ -match "^$Key=(.*)$" } | Select-Object -First 1
        if ($line) { return ($line -split "=", 2)[1] }
    }
    return ""
}

function Remove-OldRules {
    Get-NetFirewallRule -DisplayName "$prefix*" -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue
}

function Remove-TunnelRule {
    Get-NetFirewallRule -DisplayName "$prefix allow-tunnel" -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue
}

function Enable-CloseAll {
    Set-NetFirewallProfile -Profile Domain,Public,Private -DefaultOutboundAction Block -DefaultInboundAction Block
    $ovpnPath = "$env:ProgramFiles\OpenVPN\bin\openvpn.exe"
    if (-not (Test-Path $ovpnPath)) { $ovpnPath = "$env:ProgramFiles\OpenVPN\bin\openvpnserv.exe" }
    New-NetFirewallRule -DisplayName "$prefix allow openvpn" -Direction Outbound -Program $ovpnPath -Action Allow | Out-Null

    $server = Read-Meta "SERVER"
    $port = Read-Meta "PORT"
    if ($server) {
        foreach ($proto in @("UDP", "TCP")) {
            New-NetFirewallRule -DisplayName "$prefix allow vpn-$proto" -Direction Outbound `
                -RemoteAddress $server -RemotePort $port -Protocol $proto -Action Allow | Out-Null
        }
    }
    # 本地/私网仍可访问（打印机、路由器等）
    foreach ($cidr in @("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")) {
        New-NetFirewallRule -DisplayName "$prefix allow private-$cidr" -Direction Outbound `
            -RemoteAddress $cidr -Action Allow | Out-Null
    }
}

function Enable-CloseForeign {
    Enable-CloseAll
    $cnFile = Join-Path $destDir "cn-ipv4.txt"
    if (-not (Test-Path $cnFile)) { Write-Warning "缺少 cn-ipv4.txt"; return }
    $nets = @(Get-Content $cnFile | Where-Object { $_ -and $_ -notmatch '^\s*#' } | ForEach-Object { $_.Trim() })
    $batchSize = 500
    for ($i = 0; $i -lt $nets.Count; $i += $batchSize) {
        $chunk = @($nets[$i..([Math]::Min($i + $batchSize - 1, $nets.Count - 1))])
        $n = [Math]::Floor($i / $batchSize) + 1
        New-NetFirewallRule -DisplayName "$prefix allow-cn-$n" -Direction Outbound `
            -RemoteAddress $chunk -Action Allow | Out-Null
    }
}

function Enable-Open {
    Set-NetFirewallProfile -Profile Domain,Public,Private -DefaultOutboundAction Allow -DefaultInboundAction Block
}

function Add-TunnelAllow {
    param([string]$Alias)
    if (-not $Alias) {
        $Alias = (Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
            $_.Status -eq "Up" -and ($_.InterfaceDescription -match "Wintun|TAP-Windows|OpenVPN Data Channel")
        } | Select-Object -First 1 -ExpandProperty Name)
    }
    if ($Alias) {
        New-NetFirewallRule -DisplayName "$prefix allow-tunnel" -Direction Outbound `
            -InterfaceAlias $Alias -Action Allow | Out-Null
    }
}

if ($Action -eq "status") {
    $rules = @(Get-NetFirewallRule -DisplayName "$prefix*" -ErrorAction SilentlyContinue)
    $profile = Get-NetFirewallProfile -Profile Domain,Public,Private
    Write-Host "kill-switch 规则数: $($rules.Count)"
    Write-Host "出站默认策略: $($profile | Select-Object -ExpandProperty DefaultOutboundAction | Select-Object -Unique)"
    return
}

if ($Action -eq "disable") {
    Remove-OldRules
    Set-NetFirewallProfile -Profile Domain,Public,Private -DefaultOutboundAction Allow -DefaultInboundAction Block
    Write-Host "kill-switch 已解除"
    return
}

if (-not $Mode) { $Mode = Read-Meta "FAILMODE" }
if ($Action -eq "vpn-down") {
    if ($Mode -eq "open") {
        Remove-OldRules
        Enable-Open
    } else {
        # 保持封锁，仅撤掉隧道放行，避免断线后经隧道接口泄漏
        Remove-TunnelRule
    }
    Write-Host "vpn-down 处理完成 mode=$Mode"
    return
}

Remove-OldRules
switch ($Mode) {
    "close-all" { Enable-CloseAll; Add-TunnelAllow $Dev }
    "close-foreign" { Enable-CloseForeign; Add-TunnelAllow $Dev }
    "open" { Enable-Open }
}
Write-Host "kill-switch 已启用: $Mode"

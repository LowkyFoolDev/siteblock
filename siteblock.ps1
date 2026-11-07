# siteblock for Windows: system-wide site blocker (works in every browser).
# Layer 1: hosts file -> crypto, scam, gambling lists + custom.txt (TeraBox, DiskWala, ...)
# Layer 2: encrypted DNS (DoH) to Cloudflare for Families -> adult + malware/phishing sites
# Usage (PowerShell as Administrator):
#   powershell -ExecutionPolicy Bypass -File .\siteblock.ps1 install | update | uninstall
param(
    [Parameter(Mandatory)][ValidateSet('install', 'update', 'uninstall')][string]$Action,
    [string]$HostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"   # override only for testing
)
$ErrorActionPreference = 'Stop'

$HomeDir  = Join-Path $env:ProgramData 'siteblock'
$TaskName = 'siteblock-update'
$Begin    = '# >>> siteblock BEGIN'
$End      = '# <<< siteblock END'
$Lists    = @(
    'https://blocklistproject.github.io/Lists/crypto.txt',
    'https://blocklistproject.github.io/Lists/scam.txt',
    'https://raw.githubusercontent.com/StevenBlack/hosts/master/alternates/gambling-only/hosts'
)
$Dns4     = @('1.1.1.3', '1.0.0.3')
$Dns6     = @('2606:4700:4700::1113', '2606:4700:4700::1003')
$DohUrl   = 'https://family.cloudflare-dns.com/dns-query'
$RealHosts = $HostsPath -eq "$env:SystemRoot\System32\drivers\etc\hosts"

function Assert-Admin {
    if (-not $RealHosts) { return }
    $id = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $id.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run PowerShell as Administrator.'
    }
}

function Get-HostsWithoutBlock {
    $inBlock = $false
    foreach ($line in (Get-Content -LiteralPath $HostsPath)) {
        if ($line -eq $Begin) { $inBlock = $true; continue }
        if ($line -eq $End)   { $inBlock = $false; continue }
        if (-not $inBlock) { $line }
    }
}

function Write-Hosts([string[]]$Lines) {
    # ASCII, no BOM: the Windows DNS client cannot read a hosts file with a BOM
    [IO.File]::WriteAllLines($HostsPath, $Lines, [Text.Encoding]::ASCII)
}

function Update-Hosts([string]$CustomFile) {
    $domains = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($url in $Lists) {
        # a failed download throws, so the hosts file is never half-written
        $text = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 60).Content
        foreach ($line in ($text -split "`n")) {
            $parts = $line.Trim() -split '\s+'
            if ($parts.Count -ge 2 -and $parts[0] -eq '0.0.0.0' -and $parts[1] -ne '0.0.0.0' -and $parts[1] -match '^[A-Za-z0-9.-]+$') {
                [void]$domains.Add($parts[1])
            }
        }
    }
    foreach ($line in (Get-Content -LiteralPath $CustomFile)) {
        $d = $line.Trim()
        if (-not $d -or $d.StartsWith('#')) { continue }
        if ($d.StartsWith('www.')) { $d = $d.Substring(4) }
        [void]$domains.Add($d); [void]$domains.Add("www.$d")
    }
    if ($domains.Count -eq 0) { throw 'Block list empty, hosts not changed.' }
    $block = $domains | Sort-Object | ForEach-Object { "0.0.0.0 $_" }
    Write-Hosts (@(Get-HostsWithoutBlock) + $Begin + $block + $End)
    Write-Host "Blocked $($domains.Count) domains in $HostsPath"
    if ($RealHosts) { Clear-DnsClientCache }
}

function Set-FamilyDns {
    # register the DoH template for each family DNS server, then turn on automatic DoH
    foreach ($ip in $Dns4 + $Dns6) {
        if (Get-DnsClientDohServerAddress -ServerAddress $ip -ErrorAction SilentlyContinue) {
            Set-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $DohUrl -AllowFallbackToUdp $false -AutoUpgrade $true | Out-Null
        } else {
            Add-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $DohUrl -AllowFallbackToUdp $false -AutoUpgrade $true | Out-Null
        }
    }
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' -Name EnableAutoDoh -Value 2 -Type DWord
    foreach ($nic in (Get-NetAdapter | Where-Object Status -eq 'Up')) {
        Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses ($Dns4 + $Dns6)
        Write-Host "DNS for '$($nic.Name)': family DNS (encrypted)"
    }
    Clear-DnsClientCache
}

function Reset-Dns {
    foreach ($nic in (Get-NetAdapter)) {
        Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue
    }
    foreach ($ip in $Dns4 + $Dns6) {
        Remove-DnsClientDohServerAddress -ServerAddress $ip -ErrorAction SilentlyContinue
    }
    Clear-DnsClientCache
}

Assert-Admin
switch ($Action) {
    'install' {
        New-Item -ItemType Directory -Force -Path $HomeDir | Out-Null
        Copy-Item -Force (Join-Path $PSScriptRoot 'siteblock.ps1'), (Join-Path $PSScriptRoot 'custom.txt') $HomeDir
        Update-Hosts (Join-Path $HomeDir 'custom.txt')
        Set-FamilyDns
        $run = New-ScheduledTaskAction -Execute 'powershell.exe' `
            -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$HomeDir\siteblock.ps1`" update"
        $when = @((New-ScheduledTaskTrigger -Daily -At 9am), (New-ScheduledTaskTrigger -AtStartup))
        $opts = New-ScheduledTaskSettingsSet -StartWhenAvailable
        Register-ScheduledTask -TaskName $TaskName -Action $run -Trigger $when -Settings $opts `
            -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
        Write-Host 'Installed. Lists refresh daily and DNS is re-applied.'
    }
    'update' {
        $custom = Join-Path $HomeDir 'custom.txt'
        if (-not (Test-Path $custom)) { $custom = Join-Path $PSScriptRoot 'custom.txt' }
        Update-Hosts $custom
        if ($RealHosts) { Set-FamilyDns }
    }
    'uninstall' {
        Write-Hosts @(Get-HostsWithoutBlock)
        if ($RealHosts) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
            Reset-Dns
            Remove-Item -Recurse -Force $HomeDir -ErrorAction SilentlyContinue
        }
        Write-Host 'Removed.'
    }
}

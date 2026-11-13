<#
.SYNOPSIS
    Read-only Windows workstation & WireGuard client diagnostic tool for CR8808 Ver.B remote access.
.DESCRIPTION
    Performs zero modifications to Windows network configuration, routes, services, DNS, or firewall.
    1. Audits WireGuard installation and WireGuardTunnel$* service state.
    2. Detects competing active VPNs (e.g., NordLynx lowest-metric default route hijack).
    3. Checks endpoint DNS resolution comparing bare host vs trailing-dot FQDN (detects search-suffix hijacks).
    4. Validates a WireGuard .conf file offline without ever printing private/preshared keys.
    5. Runs staged path checks (tunnel gateway -> LAN route -> 192.168.31.1 -> optional pinned-key SSH).
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = "",
    [string]$EndpointHost = "",
    [string]$TunnelName = "",
    [string]$TunnelGatewayIp = "10.99.0.1",
    [string]$RouterLanIp = "192.168.31.1",
    [int]$SshPort = 56789,
    [string]$HostKeyFile = "",
    [switch]$CheckExternalDns,
    [switch]$CheckSsh,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $HostKeyFile) {
    $CandidateKey = Join-Path (Split-Path -Parent $ScriptDir) "config\cr8818_host_key.pub"
    if (Test-Path $CandidateKey) { $HostKeyFile = $CandidateKey }
}

$findings = [System.Collections.Generic.List[object]]::new()
function Add-Finding {
    param([string]$Category, [string]$Severity, [string]$Message, [hashtable]$Data = @{})
    $findings.Add([pscustomobject]@{
        category = $Category
        severity = $Severity
        message  = $Message
        data     = $Data
    })
}

function Invoke-NativeCapture {
    param([scriptblock]$Script)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $lines = @(& $Script 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" }
        })
        return ($lines -join "`n")
    } finally {
        $ErrorActionPreference = $prev
    }
}

# --- Step 1: Parse WireGuard .conf offline (NEVER store or echo PrivateKey/PresharedKey values) ---
$parsedConf = [ordered]@{
    provided               = $false
    path                   = $ConfigPath
    has_private_key        = $false
    private_key_valid_fmt  = $false
    has_preshared_key      = $false
    address                = @()
    dns                    = @()
    mtu                    = $null
    peer_public_key_set    = $false
    endpoint               = ""
    endpoint_host          = ""
    endpoint_port          = $null
    allowed_ips            = @()
    persistent_keepalive   = $null
}

if ($ConfigPath) {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        Add-Finding "CONFIG" "FAIL" "Config file not found: $ConfigPath"
    } else {
        $parsedConf.provided = $true
        $b64KeyPattern = '^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=$'
        foreach ($rawLine in (Get-Content -LiteralPath $ConfigPath)) {
            $line = ($rawLine -split '#', 2)[0].Trim()
            if (-not $line -or $line.StartsWith("[")) { continue }
            $kv = $line -split '=', 2
            if ($kv.Count -ne 2) { continue }
            $k = $kv[0].Trim().ToLowerInvariant()
            $v = $kv[1].Trim()
            switch ($k) {
                "privatekey" {
                    $parsedConf.has_private_key = $true
                    $parsedConf.private_key_valid_fmt = ($v -match $b64KeyPattern)
                }
                "presharedkey" { $parsedConf.has_preshared_key = $true }
                "address"      { $parsedConf.address += ($v -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
                "dns"          { $parsedConf.dns += ($v -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
                "mtu"          { [int]$parsedMtu = 0; if ([int]::TryParse($v, [ref]$parsedMtu)) { $parsedConf.mtu = $parsedMtu } }
                "publickey"    { $parsedConf.peer_public_key_set = ($v -match $b64KeyPattern) }
                "endpoint"     {
                    $parsedConf.endpoint = $v
                    $lastColon = $v.LastIndexOf(':')
                    if ($lastColon -gt 0) {
                        $parsedConf.endpoint_host = $v.Substring(0, $lastColon).Trim('[', ']')
                        [int]$epPort = 0
                        if ([int]::TryParse($v.Substring($lastColon + 1), [ref]$epPort)) {
                            $parsedConf.endpoint_port = $epPort
                        }
                    }
                }
                "allowedips"   { $parsedConf.allowed_ips += ($v -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
                "persistentkeepalive" {
                    [int]$ka = 0; if ([int]::TryParse($v, [ref]$ka)) { $parsedConf.persistent_keepalive = $ka }
                }
            }
        }

        if (-not $EndpointHost -and $parsedConf.endpoint_host) {
            $EndpointHost = $parsedConf.endpoint_host
        }
        if (-not $TunnelName -and $parsedConf.provided) {
            $TunnelName = [System.IO.Path]::GetFileNameWithoutExtension($ConfigPath)
        }

        if (-not $parsedConf.has_private_key -or -not $parsedConf.private_key_valid_fmt) {
            Add-Finding "CONFIG" "FAIL" "Missing or malformed [Interface] PrivateKey (not echoed for safety)."
        }
        if (-not $parsedConf.peer_public_key_set) {
            Add-Finding "CONFIG" "FAIL" "Missing or malformed [Peer] PublicKey."
        }
        if (($parsedConf.allowed_ips -contains "::/0") -and -not ($parsedConf.address | Where-Object { $_ -match ':' })) {
            Add-Finding "CONFIG" "FAIL" "AllowedIPs contains '::/0' without an IPv6 Address; RA82 wg0 has no IPv6 tunnel, causing IPv6 blackhole."
        }
        if ($parsedConf.dns | Where-Object { $_ -in @("1.1.1.1", "8.8.8.8", "8.8.4.4", "1.0.0.1") }) {
            Add-Finding "CONFIG" "WARN" "Config overrides DNS with public resolver ($($parsedConf.dns -join ', ')); blocked UDP/53 on campus/VPN or failed handshake causes DNS deadlock."
        }
        if ($null -eq $parsedConf.mtu -or $parsedConf.mtu -gt 1380) {
            $curMtu = if ($null -eq $parsedConf.mtu) { "unset (1420 default)" } else { "$($parsedConf.mtu)" }
            Add-Finding "CONFIG" "WARN" "MTU=$curMtu risks fragmentation blackholes over PPPoE (1492) + NAT + campus Wi-Fi; recommend 1280 (split) or 1360 (full)."
        }
        if ($null -eq $parsedConf.persistent_keepalive -or $parsedConf.persistent_keepalive -lt 15 -or $parsedConf.persistent_keepalive -gt 30) {
            Add-Finding "CONFIG" "WARN" "PersistentKeepalive should be ~25s for NAT/campus keepalive stability."
        }
    }
}

# --- Step 2: Check WireGuard installation, services & active NordLynx / VPN conflicts ---
$wgExe = "C:\Program Files\WireGuard\wg.exe"
$wgUiExe = "C:\Program Files\WireGuard\wireguard.exe"
$wgInstalled = (Test-Path $wgExe) -and (Test-Path $wgUiExe)
$wgServices = @(Get-Service -Name "WireGuard*" -ErrorAction SilentlyContinue | Select-Object Name, Status)

if (-not $wgInstalled) {
    Add-Finding "WORKSTATION" "FAIL" "WireGuard for Windows not found under C:\Program Files\WireGuard."
} elseif ($wgServices.Count -eq 0) {
    Add-Finding "WORKSTATION" "FAIL" "No WireGuardTunnel$* or WireGuardManager Windows service is active/installed."
} else {
    $runningWg = @($wgServices | Where-Object { $_.Status -eq 'Running' })
    if ($runningWg.Count -eq 0) {
        Add-Finding "WORKSTATION" "WARN" "WireGuard services exist but none are Running."
    } else {
        Add-Finding "WORKSTATION" "PASS" "Running WireGuard service(s): $($runningWg.Name -join ', ')"
    }
}

$defaultRoutes = @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
    ForEach-Object {
        $ifObj = Get-NetIPInterface -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
        $effMetric = $_.RouteMetric + $(if ($ifObj) { $ifObj.InterfaceMetric } else { 0 })
        [pscustomobject]@{
            InterfaceAlias = $_.InterfaceAlias
            InterfaceIndex = $_.InterfaceIndex
            NextHop        = $_.NextHop
            EffectiveMetric = $effMetric
        }
    } | Sort-Object EffectiveMetric)

$bestDefault = $defaultRoutes | Select-Object -First 1
$competingVpns = @($defaultRoutes | Where-Object { $_.InterfaceAlias -match 'Nord|Surfshark|OpenVPN|Proton|Mullvad' })
if ($competingVpns.Count -gt 0) {
    Add-Finding "ROUTING" "WARN" "Competing VPN adapter active ($($competingVpns.InterfaceAlias -join ', ')) with lowest metric $($bestDefault.EffectiveMetric) via $($bestDefault.InterfaceAlias); outer WireGuard UDP packets route inside that VPN unless disconnected or split-excluded." @{
        best_default = $bestDefault
    }
}
if ($parsedConf.provided -and ($parsedConf.allowed_ips -contains "0.0.0.0/0") -and $competingVpns.Count -gt 0) {
    Add-Finding "ROUTING" "FAIL" "Full-tunnel AllowedIPs=0.0.0.0/0 directly conflicts with active $($competingVpns[0].InterfaceAlias) default route."
}

# Check local interface IPv4 prefix overlaps against AllowedIPs
$localAddrs = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
    Select-Object InterfaceAlias, IPAddress, PrefixLength)

# --- Step 3: DNS Verification (Bare vs Trailing Dot + Optional 1.1.1.1 check) ---
$dnsInfo = [ordered]@{
    endpoint_host        = $EndpointHost
    resolved_os_ips      = @()
    nslookup_bare_ips    = @()
    nslookup_fqdn_ips    = @()
    external_1111_ok     = $null
    suffix_hijack_risk   = $false
}

if ($EndpointHost) {
    try {
        $dnsInfo.resolved_os_ips = @((Resolve-DnsName -Name $EndpointHost -Type A -ErrorAction Stop |
            Where-Object { $_.QueryType -eq 'A' }).IPAddress)
    } catch {
        Add-Finding "DNS" "FAIL" "Resolve-DnsName failed for ${EndpointHost}: $($_.Exception.Message)"
    }

    $nsBare = Invoke-NativeCapture { & nslookup $EndpointHost }
    $nsFqdn = Invoke-NativeCapture { & nslookup "${EndpointHost}." }
    $bareMatches = [regex]::Matches($nsBare, '(?ms)Name:\s+([^\r\n]+).*?Address(?:es)?:\s*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)')
    foreach ($matchObj in $bareMatches) {
        $qName = $matchObj.Groups[1].Value.Trim()
        $dnsInfo.nslookup_bare_ips += "$qName=$($matchObj.Groups[2].Value.Trim())"
        if ($qName -ne $EndpointHost -and $qName.StartsWith($EndpointHost + ".")) {
            $dnsInfo.suffix_hijack_risk = $true
        }
    }
    $fqdnMatches = [regex]::Matches($nsFqdn, '(?ms)Name:\s+([^\r\n]+).*?Address(?:es)?:\s*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)')
    foreach ($matchObj in $fqdnMatches) {
        $dnsInfo.nslookup_fqdn_ips += "$($matchObj.Groups[1].Value.Trim())=$($matchObj.Groups[2].Value.Trim())"
    }

    if ($dnsInfo.suffix_hijack_risk) {
        Add-Finding "DNS" "WARN" "nslookup without trailing dot appended local search suffix ($($dnsInfo.nslookup_bare_ips -join '; ')) vs FQDN ($($dnsInfo.nslookup_fqdn_ips -join '; ')); use trailing dot in nslookup checks."
    }

    if ($CheckExternalDns) {
        try {
            $ext = Resolve-DnsName -Name $EndpointHost -Type A -Server 1.1.1.1 -ErrorAction Stop
            $dnsInfo.external_1111_ok = $true
            Add-Finding "DNS" "PASS" "Direct UDP/53 query to 1.1.1.1 succeeded ($((@($ext | Where-Object { $_.QueryType -eq 'A' }).IPAddress) -join ', '))."
        } catch {
            $dnsInfo.external_1111_ok = $false
            Add-Finding "DNS" "WARN" "Direct UDP/53 query to 1.1.1.1 timed out/failed; do not hardcode DNS=1.1.1.1 in split-tunnel configs."
        }
    }
}

# --- Step 4: Staged WireGuard Path Verification (Read-only) ---
$pathChecks = [ordered]@{
    wg_show_status     = "SKIPPED"
    tunnel_gw_ping     = "SKIPPED"
    lan_route_interface = ""
    router_lan_ping    = "SKIPPED"
    ssh_port_open      = "SKIPPED"
    ssh_batch_ok       = "SKIPPED"
}

if ($wgInstalled) {
    if ($TunnelName) {
        $wgOut = (Invoke-NativeCapture { & $wgExe show $TunnelName }).Trim()
        if ($LASTEXITCODE -eq 0) {
            $pathChecks.wg_show_status = "OK"
            if ($wgOut -notmatch 'latest handshake:') {
                Add-Finding "TUNNEL" "FAIL" "Tunnel '$TunnelName' exists but has NO WireGuard handshake yet (likely home FPT NAT/firewall/DDNS or campus UDP block)."
            } else {
                Add-Finding "TUNNEL" "PASS" "Tunnel '$TunnelName' has active WireGuard handshake metadata."
            }
        } elseif ($wgOut -match 'Access is denied|Permission denied') {
            $pathChecks.wg_show_status = "NEEDS_ADMIN"
            Add-Finding "TUNNEL" "INFO" "wg.exe requires elevated Administrator terminal on Windows to query kernel tunnel adapters."
        } else {
            $pathChecks.wg_show_status = "NOT_ACTIVE"
        }
    }
}

$lanRoute = Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
        $_.DestinationPrefix -eq "$RouterLanIp/32" -or
        $_.DestinationPrefix -eq "192.168.31.0/24" -or
        $_.DestinationPrefix -eq "0.0.0.0/0"
    } | Sort-Object { [int]($_.DestinationPrefix -split '/')[1] } -Descending | Select-Object -First 1

if ($lanRoute) {
    $pathChecks.lan_route_interface = "$($lanRoute.InterfaceAlias) ($($lanRoute.DestinationPrefix))"
    if ($lanRoute.DestinationPrefix -eq "0.0.0.0/0") {
        Add-Finding "PATH" "FAIL" "No specific WireGuard route to 192.168.31.0/24 exists; traffic falls back to default gateway via $($lanRoute.InterfaceAlias)."
    } else {
        Add-Finding "PATH" "PASS" "Specific route present for $($lanRoute.DestinationPrefix) via $($lanRoute.InterfaceAlias)."
        $gwUp = Test-Connection -ComputerName $TunnelGatewayIp -Count 1 -Quiet -ErrorAction SilentlyContinue
        $pathChecks.tunnel_gw_ping = $(if ($gwUp) { "PASS" } else { "FAIL" })
        $lanUp = Test-Connection -ComputerName $RouterLanIp -Count 1 -Quiet -ErrorAction SilentlyContinue
        $pathChecks.router_lan_ping = $(if ($lanUp) { "PASS" } else { "FAIL" })
        if ($CheckSsh -and $lanUp) {
            $tcpOk = (Test-NetConnection -ComputerName $RouterLanIp -Port $SshPort -WarningAction SilentlyContinue).TcpTestSucceeded
            $pathChecks.ssh_port_open = $(if ($tcpOk) { "PASS" } else { "FAIL" })
            if ($tcpOk -and $HostKeyFile -and (Test-Path $HostKeyFile) -and (Get-Command ssh.exe -ErrorAction SilentlyContinue)) {
                $khTmp = [System.IO.Path]::GetTempFileName()
                try {
                    $pubLine = (Get-Content -LiteralPath $HostKeyFile -TotalCount 1).Trim()
                    Set-Content -LiteralPath $khTmp -Value "${RouterLanIp} ${pubLine}`n[${RouterLanIp}]:${SshPort} ${pubLine}" -Encoding Ascii
                    $null = Invoke-NativeCapture {
                        & ssh.exe -p $SshPort -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$khTmp" -o BatchMode=yes -o ConnectTimeout=5 "root@${RouterLanIp}" "uname -a"
                    }
                    $pathChecks.ssh_batch_ok = $(if ($LASTEXITCODE -eq 0) { "PASS" } else { "FAIL_OR_AUTH" })
                } finally {
                    Remove-Item -LiteralPath $khTmp -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

$report = [ordered]@{
    timestamp          = (Get-Date -Format "o")
    read_only          = $true
    wireguard_installed = $wgInstalled
    wireguard_services = $wgServices
    default_routes     = $defaultRoutes
    local_ipv4         = $localAddrs
    config_audit       = $parsedConf
    dns_check          = $dnsInfo
    path_checks        = $pathChecks
    findings           = $findings
}

if ($Json) {
    $report | ConvertTo-Json -Depth 6
} else {
    Write-Host "=== CR8808 Windows WireGuard Diagnostic (Read-Only) ==="
    Write-Host "WireGuard Installed : $wgInstalled | Services: $(if ($wgServices.Count) { ($wgServices.Name -join ', ') } else { 'NONE' })"
    Write-Host "Primary 0.0.0.0/0   : $(if ($bestDefault) { "$($bestDefault.InterfaceAlias) gw $($bestDefault.NextHop) metric $($bestDefault.EffectiveMetric)" } else { 'NONE' })"
    if ($EndpointHost) {
        Write-Host "DNS ($EndpointHost) : OS=$($dnsInfo.resolved_os_ips -join ',') | FQDN-dot=$($dnsInfo.nslookup_fqdn_ips -join ',')"
    }
    Write-Host "LAN Route Target    : $($pathChecks.lan_route_interface)"
    Write-Host "Path Probes         : wg_show=$($pathChecks.wg_show_status) gw_ping=$($pathChecks.tunnel_gw_ping) lan_ping=$($pathChecks.router_lan_ping) ssh=$($pathChecks.ssh_port_open)/$($pathChecks.ssh_batch_ok)"
    Write-Host ""
    foreach ($f in $findings) {
        Write-Host ("[{0}] ({1}) {2}" -f $f.severity, $f.category, $f.message)
    }
}

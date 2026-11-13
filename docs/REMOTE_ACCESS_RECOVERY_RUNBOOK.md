# CR8808 Ver.B Remote Access Recovery & Fallback Runbook

## 1. Confirmed Diagnosis Summary

| Layer | Finding (`MEASURED` / `DEVICE_READBACK` / `SOURCE_VERIFIED`) | Operational Impact |
|---|---|---|
| **Windows Workstation** | No WireGuard tunnel service is active (`Get-Service WireGuard*` empty, zero `10.99.0.0/24` / `192.168.31.0/24` routes). | `192.168.31.1:56789` routes out default gateway and times out. |
| **NordVPN Conflict** | `NordLynx` (`10.5.0.2/16`, default route `Metric 6`, egress `38.132.104.228`) overrides campus Wi-Fi (`Metric 45`). | All traffic (including WireGuard UDP endpoints and `0.0.0.0/0` tunnels) enters NordVPN unless paused/excluded. |
| **DNS Behavior** | Bare `nslookup <subdomain>.duckdns.org` triggers `fus.edu.vn` wildcard suffix; `nslookup <subdomain>.duckdns.org.` & `Resolve-DnsName` return `118.68.195.158`. Direct `1.1.1.1` UDP/53 queries timed out. | Configs enforcing `DNS = 1.1.1.1` risk DNS failure or deadlock on handshake loss. |
| **Home Upstream (FPT Double NAT)** | Even via NordLynx (`38.132.104.228`), `118.68.195.158:56789` & ping failed. Prior raw audits showed `0` packets on `zone_wan_input` `Allow-WAN-WireGuard` (`udp/51820`), while CR8808 `eth0` WAN sits behind FPT AX3000CV2 ONT (`192.168.100.1`). | FPT PPPoE public IP rotated (stale DuckDNS), Xiaomi `.75` WAN lease drifted, or ONT lacks UDP `51820` forwarding / CGNAT blocks unsolicited inbound. |
| **Keypair Verification** | Router `-srvkey`/`-clientkey` and all 3 desktop profiles cryptographically match (`wg pubkey`). | Not a key mismatch defect. |

---

## 2. Primary Path Recovery Checklist (Run When Home on LAN `192.168.31.0/24`)

1. **Inspect FPT AX3000CV2 ONT (`http://192.168.100.1`):**
   - Compare FPT PPPoE WAN IPv4 against external IP (`curl -s https://api.ipify.org`) and `nslookup <subdomain>.duckdns.org.`.
   - If FPT WAN IPv4 falls inside `100.64.0.0/10` or differs from external egress IP, ISP CGNAT is active — skip straight to **Section 4 (Tailscale Home Subnet Router)**.
2. **Stabilize FPT -> Xiaomi NAT:**
   - Bind Xiaomi CR8808 WAN MAC (`eth0`) to static DHCP IP `192.168.100.75` on FPT ONT.
   - Forward **UDP `51820` -> `192.168.100.75:51820`** (prefer explicit UDP port forward over broad DMZ).
3. **Verify CR8808 DDNS & WireGuard Listeners (Read-Only first):**
   - Check `/tmp/duckdns.log` freshness and cron `/data/update_duckdns.sh` execution.
   - Confirm `wg0` (`0.0.0.0:51820`) is up without interfering with production `wg0` keys.
4. **Minimize Public Attack Surface:**
   - Once WireGuard admin split-tunnel (`config/wireguard/home-split-admin.conf.template`) passes all 7 stages in `scripts/validate_remote_wg_path.sh`, close public WAN SSH (`Allow-WAN-SSH` TCP `56789`) on CR8808 so SSH is reachable strictly via VPN or LAN.

---

## 3. Workstation Stabilization & 7-Stage Validation

1. Disconnect or pause `NordVPN` (`NordLynx`) before activating a WireGuard home tunnel.
2. Instantiate client profile from [home-split-admin.conf.template](../config/wireguard/home-split-admin.conf.template) (`MTU = 1280`, no `::/0`, no forced `1.1.1.1` DNS).
3. Audit client state (read-only):
   - Windows: `powershell -ExecutionPolicy Bypass -File scripts/diagnose_wg_client.ps1 -ConfigPath <path> -CheckExternalDns`
   - WSL2/Linux staged verification: `sh scripts/validate_remote_wg_path.sh --verify-path --tunnel <iface>`

---

## 4. Secondary Fallback (CGNAT / Upstream NAT / Campus UDP Block): Tailscale Subnet Router

- **Do NOT deploy `tailscaled` onto Xiaomi CR8808 Ver.B:** Archived ARMv7 binaries in `D:\vibecode\test_wifi` total ~40 MB (`21.5 MB` + `18.6 MB`) on a router with `186,920 kB` RAM (`~28.5 MB` available), which previously contributed to instability/outage recovery purges.
- **Recommended Deployment:** Run Tailscale on an always-on home LAN host (`192.168.31.x` desktop/SBC behind CR8808) using [setup_subnet_router.sh.example](../config/tailscale/setup_subnet_router.sh.example) (`--advertise-routes=192.168.31.0/24`), then connect via `ssh -p 56789 -o StrictHostKeyChecking=yes -o UserKnownHostsFile=config/cr8818_host_key.pub root@192.168.31.1`.

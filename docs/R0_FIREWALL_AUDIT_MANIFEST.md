# Class R0 Firewall & Dual-Stack Network Investigation Manifest

- **Document ID:** `docs/R0_FIREWALL_AUDIT_MANIFEST.md`
- **Target Device:** Xiaomi CR8808 Ver.B (Internal Codename: `CR8818`, Profile: `ap-mp03.3`)
- **Active System:** Xiaomi RA82 Global v1.4.31 (Linux 4.4.60 QSDK, 32-bit `armv7l`)
- **Authority:** Chief Architect Directive M11.1.0.2 / Lead Systems Engineer (Gemini)
- **Status:** **DRAFT SPECIFICATION — WORKSTATION ONLY — PENDING ARCHITECT APPROVAL**
- **Safety Boundary:** **PURE READ-ONLY | ZERO FIREWALL MODIFICATIONS | ZERO WRITES | ZERO DAEMON RESTART**

---

## 1. Safety Mandate & Execution Protocol

This manifest defines the comprehensive read-only interrogation commands required to rigorously establish the router's exact network topology, IPv4/IPv6 routing tables, netfilter chain hierarchy, rule precedence, and Dropbear exposure across zones.

> [!CAUTION]
> **PRE-FLIGHT HOLD:** This manifest is strictly a PC-side design document. **NO SSH COMMAND WILL BE EXECUTED ON THE ROUTER** until this specification is reviewed and formally authorized in writing by the Chief Architect.

### Cryptographic Safeguards:
1. **Out-of-Band Host Key Pinning:** Host authentication MUST verify against [`config/cr8818_host_key.pub`](file:///D:/vibecode/CR8808-CUSTOM-FIRMWARE/config/cr8818_host_key.pub) (`SHA256:BwYCFt/UPVQ+Sj6/ZcbKf7yfTK5FqPFYB9uN7isGL64`). No dynamic `ssh-keyscan` is permitted. Key is classified as `PINNED_HISTORICAL_CACHE`.
2. **Pure In-Memory Pipeline:** Commands stream directly into standard output over the SSH session; zero temporary files are written to `/tmp` or persistent storage.
3. **Mandatory Sanitization:** Output streams directly through [`scripts/sanitize_telemetry.sh`](file:///D:/vibecode/CR8808-CUSTOM-FIRMWARE/scripts/sanitize_telemetry.sh) before any data is written to disk on the workstation.

---

## 2. Itemized Read-Only Command Matrix

| ID | Exact Remote Command | Architectural Target | Safety Class | Prerequisite Check |
|---|---|---|---|---|
| **FW-01** | `ip -4 addr show; ip -4 route show table all` | Complete IPv4 interface addresses, subnets, and routing tables | Read-Only | `command -v ip >/dev/null` |
| **FW-02** | `ip -6 addr show; ip -6 route show table all; cat /proc/net/if_inet6` | Complete IPv6 interface addresses, Global Unicast, Link-Local, and default routes | Read-Only | `command -v ip >/dev/null` |
| **FW-03** | `iptables -S; iptables -t filter -nvL` | Exhaustive IPv4 filter rules in export format and packet/byte match counters | Read-Only | `command -v iptables >/dev/null` |
| **FW-04** | `ip6tables -S 2>/dev/null \|\| echo "ip6tables -S not supported"; ip6tables -t filter -nvL 2>/dev/null \|\| echo "ip6tables filter not present"` | Exhaustive IPv6 filter rules and chain structures | Read-Only | `command -v ip6tables >/dev/null` |
| **FW-05** | `iptables -nvL zone_wan_input 2>/dev/null; iptables -nvL input_wan_rule 2>/dev/null` | Exact rule ordering, custom chains, and accept rules on IPv4 WAN ingress | Read-Only | `command -v iptables >/dev/null` |
| **FW-06** | `ip6tables -nvL zone_wan_input 2>/dev/null \|\| echo "IPv6 zone_wan_input not present"; ip6tables -nvL input_wan_rule 2>/dev/null \|\| echo "IPv6 input_wan_rule not present"` | Exact rule ordering and custom chains on IPv6 WAN ingress | Read-Only | `command -v ip6tables >/dev/null` |
| **FW-07** | `uci show firewall \| grep -E "zone|wan|input|dropbear"` | OpenWrt fw3 UCI configuration defining zone-to-interface bindings and default policies | Read-Only | `command -v uci >/dev/null` |
| **FW-08** | `netstat -tlpn 2>/dev/null \| grep dropbear; uci show dropbear` | Dropbear listening addresses (`0.0.0.0` vs `:::`) and UCI management settings | Read-Only | `command -v netstat >/dev/null` |
| **FW-09** | `cat /proc/net/tcp /proc/net/tcp6 2>/dev/null \| head -n 30` | Kernel-level TCP connection tables verifying active SSH sessions and remote socket IPs | Read-Only | Check `/proc` entries |

---

## 3. Analytical Objectives

Executing this manifest will empirically answer the following critical questions:
1. **IPv6 WAN Reality:** Does the upstream ISP ONT provision a valid Global Unicast IPv6 prefix (`2000::/3`) to the router's `eth0` interface, or does `eth0` possess only Link-Local (`fe80::/64`)?
2. **IPv6 Default Route:** Does an active default route `::/0` exist on WAN, making the router globally addressable from the public IPv6 Internet?
3. **Firewall Chain Symmetry:** Does `ip6tables` have an identical `zone_wan_input` delegate chain as `iptables`, or does Xiaomi's QSDK firmware handle IPv6 via a different table structure?
4. **Dropbear Zone Exposure:** Is Dropbear accessible from WAN because of an explicit ACCEPT rule in `input_wan_rule`, or because `zone_wan_input` has a default policy of ACCEPT?

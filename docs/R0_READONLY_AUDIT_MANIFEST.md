# Proposal: Class R0 Read-Only Router Audit Command Manifest

- **Document ID:** `docs/R0_READONLY_AUDIT_MANIFEST.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.1.0-dev.2)
- **Target Device:** Xiaomi CR8808 Ver.B (Stock Firmware: RA82 Global v1.4.31, QSDK Linux 4.4.60)
- **Status:** **PROPOSAL ONLY — NOT YET AUTHORIZED FOR EXECUTION**
- **Safety Class:** Class R0 (Pure Read-Only, Zero Router State Modification)
- **Revision:** Round 4 Review (Correct Port Demarcation & Bus Read Risk Levels)

---

## 1. Safety Mandate and Storage Boundary Taxonomy

In strict adherence to `AGENTS.md` and the **Architecture Directives M11.1 and M11.1.0.1**:
- **Execution Boundary:** Class R0 commands are strictly read-only interrogations of Linux procfs, sysfs, ubus, and nvram.
- **Storage Boundary Classification:**
  1. *Persistent Storage (NAND Flash / SPI MTD / NVRAM / Bootconfig):* **ABSOLUTELY ZERO WRITES.** Any modification to MTD or NVRAM is strictly prohibited under the `STRICT NO-GO FLASH` mandate.
  2. *Volatile Memory Storage (`/tmp` tmpfs in RAM):* **AVOIDED IN CLASS R0.** Prior scripts created temporary files in `/tmp` for differential calculation. Under M11.1.0.1, all differential CPU and SoftIRQ sampling is re-engineered to stream data directly into AWK process memory via standard input pipelines, ensuring **ZERO files are created in `/tmp` or on any filesystem**.
  3. *Kernel State / Network Routing / Firewall / Daemons:* **ZERO MODIFICATIONS.** No iptables rules added, no daemons killed, no network interfaces touched.
- All commands incorporate pre-flight availability checks (`command -v` or file test `-e`) to prevent shell exceptions or unexpected script failures.
- All collected outputs must pass through mandatory sanitization filters before storage or reporting.

---

## 2. Risk Level Taxonomy for Read-Only Operations

Even within read-only operations, commands carry different levels of bus interaction and kernel impact:

| Risk Level | Definition | Scope & Safeguards |
|---|---|---|
| **Low (Passive)** | Pure memory/procfs interrogation of already-buffered kernel state (e.g. `/proc/cpuinfo`, `/proc/meminfo`, `/proc/mtd`). | Zero side-effects; zero bus traffic; completely non-intrusive. |
| **Medium (Active Bus Query)** | Queries that generate live hardware bus transactions (MDIO/SMI bus reads, wireless ioctls, or reading kernel circular buffers). | Uses read-only register access (e.g. `/proc/smi`). Pre-checked for presence. Will not write or alter control registers. |
| **High (Modifying / Dangerous)** | Any command that writes to sysfs, executes an ioctl with mutation flags, modifies NVRAM, or halts processes. | **STRICTLY PROHIBITED from Class R0.** |

---

## 3. Proposed Read-Only Commands Manifest

| ID | Proposed Shell Command | Subsystem / Target Data | Risk Level | Pre-Flight Check | Redaction & Sanitization Rule |
|---|---|---|---|---|---|
| **R0-01** | `cat /proc/cpuinfo` | IPQ5018 CPU part number, revision, core count | Low | File existence `[ -e /proc/cpuinfo ]` | None (Standard hardware architecture strings). |
| **R0-02** | `cat /proc/meminfo` | Exact physical `MemTotal`, `MemFree`, slab, buffer split | Low | File existence `[ -e /proc/meminfo ]` | None. |
| **R0-03** | `cat /proc/mtd` | Exact MTD partition offsets for `0:ART`, `0:bdata`, `rootfs`, and `rootfs_1` | Low | File existence `[ -e /proc/mtd ]` | Redact any device serials if appended to partition labels. |
| **R0-04** | `dmesg \| grep -i -E "switch\|yt\|phy\|motorcomm\|qca\|nss"` | Boot dmesg log: Motorcomm switch at MDIO `0x1d` vs internal PHY ID (`0x004dd0c0` at `88000.mdio:07`) | Low | `command -v dmesg >/dev/null` | Redact any MAC addresses logged during probe. |
| **R0-05** | `[ -e /proc/smi ] && cat /proc/smi \| head -n 30 \|\| echo "smi not present"` | Live Motorcomm switch register map via Xiaomi Serial Management Interface (MDC/MDIO) | Medium | File existence check `[ -e /proc/smi ]` | None (Raw hexadecimal register offsets). |
| **R0-06** | `nvram get model; nvram get flag_boot_rootfs; nvram get flag_boot_success` | Read NVRAM model identifier (`CR8818`) and dual-boot status | Low | `command -v nvram >/dev/null` | Do NOT run `nvram show` (prevents exposing Wi-Fi passwords). |
| **R0-07** | `ubus call system board` | Board identity (`ap-mp03.3`), QSDK release version | Low | `command -v ubus >/dev/null` | Redact serial number fields if present in JSON. |
| **R0-08** | `lsmod \| grep -E "yt\|qca\|nss"` | Loaded kernel modules (`yt_switch.ko`, `qca-ssdk.ko`, `nss-dp.ko`) | Low | `command -v lsmod >/dev/null` | None. |
| **R0-09** | `uci show wireless \| grep -E "channel\|band\|htmode\|disabled"; iwconfig 2>/dev/null \| grep -E "IEEE\|Mode"` | Wi-Fi 5 GHz HE160 operating mode and channel bandwidth (Replaces OpenWrt `iwinfo` which does not exist on QSDK) | Low | `command -v uci >/dev/null` | Redact SSIDs, passwords (`key`), and BSSIDs. |
| **R0-10** | `ip addr show; ip route show` | Network interface topology (`br-lan`, `eth0`, `eth1`, `wan`) and routing table | Low | `command -v ip >/dev/null` | Redact public WAN IP address and hardware MACs. |
| **R0-11** | `for name in wg_server messagingagent trafficd cab_meshd smartcontroller; do for pid in $(pidof $name 2>/dev/null); do cat /proc/$pid/status 2>/dev/null \| grep -E "^(Name\|VmSize\|VmRSS\|RssAnon\|RssFile):"; done; done` | Process memory profiling: exact VmRSS, RssAnon, and RssFile (BusyBox pidof compatible) | Low | Check `/proc` entries | None (Standard memory integers). |
| **R0-12** | `(echo "=== T1 ==="; cat /proc/stat /proc/softirqs; sleep 10; echo "=== T2 ==="; cat /proc/stat /proc/softirqs) \| awk -v dur=10 '...'` | Time-bounded differential CPU & softirq profiling (Pure In-Memory Stream; zero `/tmp` files) | Low | Check command presence | None (Differential counters). |
| **R0-13** | `netstat -tlpn 2>/dev/null \| grep -E "56789\|51820\|53"` | Socket listening bindings (Dropbear, WireGuard, dnsmasq) | Low | `command -v netstat >/dev/null` | None (Local port numbers). |
| **R0-14** | `cat /sys/kernel/debug/qca-nss-drv/stats/ipv4 2>/dev/null \| head -n 30` | NSS hardware offload statistics and rule match counters | Low | File existence check | None (Packet and byte counters). |

---

## 4. Hardware Disambiguation & `/proc/smi` Technical Overview

### 4.1 PHY vs. Switch Hardware Demarcation
- **Switch Hardware:** The Motorcomm YT9215S/SC switch is an external IC addressed at MDIO address `0x1d` on MDIO Bus 1 (GPIO 36 MDC, GPIO 37 MDIO). Its ports are wired as:
  - `port@0`: LAN1 (internal PHY 0)
  - `port@1`: LAN2 (internal PHY 1)
  - `port@2`: LAN3 (internal PHY 2)
  - `port@3`: WAN (internal PHY 3)
  - `port@4`: CPU Conduit 2 (`dp1` / `eth0` via internal GE PHY, fixed-link 1000M)
  - `port@8`: CPU Conduit 1 (`dp2` / `eth1` via SGMII fixed-link 1000M)
  - `port@10`: Internal MCU management channel
- **Internal SoC PHY:** The Qualcomm IPQ5018 Internal Gigabit Ethernet PHY sits at `88000.mdio:07` on the SoC internal MDIO bus, reporting PHY ID `0x004dd0c0`.
- The R0 audit is designed to query these two distinct hardware components without conflating their addresses or driver interfaces.

### 4.2 The `/proc/smi` Mechanism
On Qualcomm QSDK vendor firmware, Xiaomi's `yt_switch` kernel driver creates the procfs entry `/proc/smi`.
- **Function:** Exposes the Serial Management Interface to userland for debugging.
- **Read Behavior:** Reading `/proc/smi` queries the active switch registers over MDIO, formatting the output as an ASCII hex dump of PHY and switch control registers.
- **Safeguard:** R0-05 pipes the output through `head -n 30` to prevent excessive bus polling, strictly as a passive diagnostic.

---

## 5. Redaction Filter Specification

Before any output from the commands above is saved to disk or pasted into conversation, it MUST pass through the standardized multi-pattern regex sanitizer:
1. **MAC Addresses & BSSIDs:** Regex `([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})` $\rightarrow$ `[REDACTED_MAC]`.
2. **WAN & Public IP Addresses:** Regex `192\.168\.100\.[0-9]+` (and any non-RFC1918 public IP) $\rightarrow$ `[REDACTED_WAN_IP]`.
3. **Serial Numbers:** Regex `Serial\s*:\s*[0-9a-zA-Z]+` $\rightarrow$ `Serial : [REDACTED_SERIAL]`.
4. **Wireless SSIDs:** Regex `ESSID:"[^"]*"` $\rightarrow$ `ESSID:"[REDACTED_SSID]"`, and `ssid='[^']*'` $\rightarrow$ `ssid='[REDACTED_SSID]'`.
5. **Wi-Fi PSK / Passphrases:** Regex `(key|sae_password)=['"][^'"]*['"]` $\rightarrow$ `\1='[REDACTED_WIFI_KEY]'`.
6. **WireGuard Private & Preshared Keys:** Regex `(-srvkey|-clientkey) [^ ]+` $\rightarrow$ `\1 [REDACTED_WG_KEY]`.
7. **Automation Rule:** All audit scripts must pipe remote output through these filters before saving to persistent storage. Raw files with unredacted personal identifiers must never be committed to Git.

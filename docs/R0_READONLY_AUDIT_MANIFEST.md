# Proposal: Class R0 Read-Only Router Audit Command Manifest

- **Document ID:** `docs/R0_READONLY_AUDIT_MANIFEST.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.1.0-dev.2)
- **Target Device:** Xiaomi CR8808 Ver.B (Stock Firmware: RA82 Global v1.4.31)
- **Status:** **PROPOSAL ONLY — NOT YET AUTHORIZED FOR EXECUTION**
- **Safety Class:** Class R0 (Pure Read-Only, Zero Router State Modification)

---

## 1. Safety Mandate and Execution Protocol

In strict adherence to `AGENTS.md` and the **Architecture Gate G1 Final Review**:
- **NO SSH execution will occur until this manifest is reviewed and formally approved by ChatGPT Architecture Lead and User.**
- All proposed commands are strictly read-only interrogations of Linux procfs, sysfs, ubus, and nvram.
- Zero files will be written, zero daemons will be terminated, zero services will be restarted, and zero NVRAM variables will be set.
- All collected outputs will pass through mandatory sanitization filters to strip MAC addresses, serial numbers, Wi-Fi keys, and private identifiers before inclusion in any report.

---

## 2. Proposed Read-Only Commands Manifest

| ID | Command | Subsystem / Purpose | Target Data to Inspect | Safety Risk | Redaction & Sanitization Rule |
|---|---|---|---|---|---|
| **R0-01** | `cat /proc/cpuinfo` | CPU / SoC Architecture | Confirm Qualcomm IPQ5018 CPU part, revision, and dual-core topology. | None | None (Standard hardware architecture strings). |
| **R0-02** | `cat /proc/meminfo` | Memory Budget | Exact physical `MemTotal`, `MemFree`, slab, and kernel buffer split. | None | None. |
| **R0-03** | `cat /proc/mtd` | Flash Layout | Exact MTD partition offsets for `0:ART`, `0:bdata`, `rootfs`, and `rootfs_1`. | None | Redact any device serials if appended to partition labels. |
| **R0-04** | `dmesg \| grep -i -E "switch\|yt\|phy\|motorcomm\|qca\|nss"` | Switch & PHY Hardware | Exact switch identification string, internal PHY ID (`0x004dd0c0`), and MDIO address (`0x1d`). | None | Redact any MAC addresses logged by PHY probe. |
| **R0-05** | `cat /proc/smi` | Switch SMI / MDIO Registers | Inspect live Motorcomm switch register map (chip ID register `0x0000`, `0x0001`). | None | None (Raw hexadecimal register offsets). |
| **R0-06** | `nvram get model; nvram get flag_boot_rootfs` | Boot Configuration | Read NVRAM model identifier (`CR8818`) and currently active dual-boot slot. | None | Do NOT run `nvram show` (prevents exposing Wi-Fi passwords). |
| **R0-07** | `ubus call system board` | Board Metadata | Extract board name (`ap-mp03.3`), release version, and hardware revision. | None | None. |
| **R0-08** | `lsmod` | Kernel Modules | Inspect currently loaded QSDK drivers (`yt_switch.ko`, `qca-ssdk.ko`, `nss-dp.ko`). | None | None. |
| **R0-09** | `iwinfo 2>&1 \| grep -i -E "channel\|width\|mode\|he160"` | Wi-Fi 5 GHz HE160 | Confirm current channel (40), bandwidth (160 MHz), and HT/VHT/HE mode. | None | Redact SSID and client MAC addresses. |
| **R0-10** | `ip addr show; ip route show` | Network Configuration | Verify interface topology (`br-lan`, `eth0`, `eth1`, `wan`) and routing tables. | None | Redact public WAN IP address and hardware MACs. |

---

## 3. Redaction Filter Specification

Before any output from the commands above is saved to disk or pasted into conversation:
1. **MAC Addresses:** Replaced with `[REDACTED_MAC]`.
2. **Public WAN IP:** Replaced with `[REDACTED_WAN_IP]`.
3. **Serial Numbers:** Replaced with `[REDACTED_SERIAL]`.
4. **Wi-Fi SSIDs / PSKs:** Replaced with `[REDACTED_SSID]` / `[REDACTED_PSK]`.
5. **Private Keys:** Commands are crafted to never query keys or configuration stores containing credentials.

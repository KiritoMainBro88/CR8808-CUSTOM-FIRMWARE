# CR8818 Hardware Conflict Resolution & Disambiguation (M7.1 Revision 1)

- **Document ID:** `docs/M7.1/CR8818_HARDWARE_CONFLICT_RESOLUTION.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.2.0-dev)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Board Profile `ap-mp03.3`)
- **Author:** Gemini 3.8 Flash High (Lead Developer / Research Engineer)
- **Reporting Authority:** ChatGPT (Chief Architect / Architecture Lead)
- **Status:** Complete Conflict Analysis for Gate M7.1 Revision 1
- **Evidence Classification:** Strictly categorized across `HARDWARE_VERIFIED`, `SOURCE_VERIFIED`, `REPORTED_UNVERIFIED`, `CONFLICT_UNRESOLVED`.

---

## 1. Executive Summary & Resolution Scope

Milestone M7.1 Revision 1 targets two critical P0 hardware ambiguities:
1. **P0-1: Exact Hardware Identity & Revisions:** Eliminating confusion surrounding commercial model names (CR8808 vs CR8806 vs CR8818 vs CR8816) and board markings (M79 / M81).
2. **P0-2: Switch Cold-Boot Lockup & GPIO 39 / 37 Electrical Semantics:** Maintaining the formal **`CONFLICT_UNRESOLVED`** status regarding GPIO 39 (upstream `reset-gpios` active-low vs Chinese community LAN LDO power enable) and GPIO 37 (MDIO clock burst). Adhering strictly to upstream verified DTS parameters rather than invented timings.

---

## 2. P0-1: Ground-Truth Hardware Disambiguation

### 2.1 The Inadequacy of M79 / M81 Markings
In Chinese router modding forums, devices are frequently referred to by motherboard silkscreen labels such as "M79" or "M81". Forensic audit proves that **relying on M79/M81 alone is dangerous and leads directly to bricked devices**:
- The **M79 motherboard PCB** was utilized by Xiaomi across multiple distinct router generations with completely incompatible component populations:
  - **Xiaomi CR8806 (M79):** IPQ5018 + **Qualcomm QCA8337 switch** + **QCN6122 Wi-Fi**.
  - **Xiaomi CR8808 Ver.A (M79):** **Qualcomm IPQ5000** (single-core/restricted) + legacy switch.
  - **Xiaomi CR8808 Ver.B (M79):** **Qualcomm IPQ5018** + **Motorcomm YT9215SC switch** + **QCN6102 Wi-Fi**.

### 2.2 Authoritative Hardware Ground Truth Table

| Hardware Attribute | Ground-Truth Readback Specification | Source Verification Reference | Evidence Status |
|---|---|---|:---:|
| **Commercial Product** | Xiaomi Router CR8808 Ver.B (China Mobile Custom) | Chassis label & OEM package | `HARDWARE_VERIFIED` |
| **Internal Model String** | **`CR8818`** | `ubus call system board` (`"model": "CR8818"`) | `HARDWARE_VERIFIED` |
| **Qualcomm Board Profile** | **`ap-mp03.3`** | Stock U-Boot bootargs & DT root compatible | `HARDWARE_VERIFIED` |
| **SoC Processor** | **Qualcomm IPQ5018** (Dual Cortex-A53 @ 1.0 GHz) | `/proc/cpuinfo` & SoC physical marking | `HARDWARE_VERIFIED` |
| **System RAM** | **256 MB DDR3L** (~182 MB usable by Linux kernel) | `/proc/meminfo` (`MemTotal: 186720 kB`) | `HARDWARE_VERIFIED` |
| **Ethernet Switch** | **Motorcomm YT9215SC / YT9215S** | MDIO probe @ `0x1d` on MDIO1 | `HARDWARE_VERIFIED` |
| **Internal SoC PHY** | Qualcomm IPQ5018 Integrated GE PHY (`0x004dd0c0`) | MDIO probe @ `0x00` on MDIO0 | `HARDWARE_VERIFIED` |
| **Wi-Fi 2.4 GHz Radio** | Qualcomm IPQ5018 on-die 2x2 802.11ax (574 Mbps) | `c000000.wifi` on AHB bus | `HARDWARE_VERIFIED` |
| **Wi-Fi 5 GHz Radio** | **Qualcomm QCN6102** 2x2 802.11ax (**HE160, 2402 Mbps**) | `b00a040.wifi1` on AHB bus (Hexagon Q6 WCSS) | `HARDWARE_VERIFIED` (Physical) |
| **Wi-Fi Firmware Family** | `ath11k/QCN6122/hw1.0/` (upstream driver family) | Upstream `ipq5018-xiaomi-cr8818.dts` & calibration | `SOURCE_VERIFIED` (Driver) |
| **SPI NAND Flash** | **Winbond W25N01GWZEIG** (128 MB, 2048B page) | Community teardowns & Linux `winbond.c` | `REPORTED_UNVERIFIED` (Chip marking) |

> [!CRITICAL]
> **Resolution P0-1:** Custom firmware build recipes must target `xiaomi_cr8818` exclusively. CR8806 or CR8808 Ver.A firmware images are strictly banned.

---

## 3. P0-2: The GPIO 39 / 37 Cold-Boot Conflict (`CONFLICT_UNRESOLVED`)

### 3.1 The Technical Conflict
During cold boot (power cord plugged in from an unpowered state), multiple community developers have reported that OpenWrt boots with **all Ethernet ports completely dead**. The kernel log reports:
```
yt9215-smi: probe of mdio@1:1d failed with error -5
[or] yt921x-dsa: chipid incorrect: ffffffff (or 00000000)
```
Yet, upon warm reboot (`reboot` command), the switch frequently probes successfully.

This inconsistency has led to two conflicting technical explanations:

```
+-------------------------------------------------------------------------------------------------+
|                                 THE GPIO 39 / 37 CONFLICT                                       |
+-------------------------------------------------------------------------------------------------+
| PERSPECTIVE A: Upstream Device Tree (David Yang `b230c2f`)                                      |
| - GPIO 39 is declared as: reset-gpios = <&tlmm 39 GPIO_ACTIVE_LOW>;                             |
| - Upstream timing: reset-assert-us = <10000>; (10 ms)                                           |
|                    reset-deassert-us = <50000>; (50 ms)                                         |
| - Assumption: Standard active-low hardware reset pin.                                           |
+-------------------------------------------------------------------------------------------------+
                                                VS
+-------------------------------------------------------------------------------------------------+
| PERSPECTIVE B: Chinese Community Reverse Engineering (hzyitc Issue 2026-04-04 & Enshan)         |
| - GPIO 39 is an LDO / Power Enable pin supplying 3.3V power to the YT9215 switch circuit.       |
| - Pulling GPIO 39 LOW cuts power to the switch silicon.                                         |
| - GPIO 37 is the MDIO data line. The YT9215 silicon requires clock signal traffic across GPIO 37|
|   to wake up from deep sleep / power-down state.                                                |
| - U-Boot Workaround: Executing 'mii info' in U-Boot sends clock bursts on Pin 37 while Pin 39   |
|   remains powered, waking the switch before Linux boots.                                        |
+-------------------------------------------------------------------------------------------------+
```

### 3.2 Evidence Comparison

1. **David Yang Upstream DTS (`SOURCE_VERIFIED`):**
   ```dts
   reset-gpios = <&tlmm 39 GPIO_ACTIVE_LOW>;
   reset-assert-us = <10000>;
   reset-deassert-us = <50000>;
   ```
   This represents the official upstream baseline. It treats GPIO 39 as a pure logic reset line with 10 ms assertion and 50 ms deassertion.
2. **ZCOP ImmortalWrt DTS (`SOURCE_VERIFIED` in ZCOP fork):**
   In ZCOP's tree, `reset-assert-us` was increased to 20,000 µs (20 ms) and `reset-deassert-us` to 100,000 µs (100 ms).
3. **Community Electrical Analysis (`REPORTED_UNVERIFIED`):**
   Contributors in Enshan and hzyitc argue that GPIO 39 connects to a MOSFET/LDO enable gate. When the system is cold-started, pulling GPIO 39 low cuts rail voltage to the switch. When re-enabled, the oscillator requires MDIO activity on GPIO 37 to resume.

### 3.3 Resolution & Governance Policy
- **Formal Status:** **`CONFLICT_UNRESOLVED`**.
- **Governance Rule:** Neither hypothesis has been validated by physical oscilloscope or logic analyzer capture on the CR8818 circuit board.
- **Architectural Directive:**
  - Gemini shall **NOT invent arbitrary GPIO reset timings** (such as 100 ms or custom delays) without empirical measurement.
  - The project baseline adheres strictly to David Yang's upstream verified timings (`reset-assert-us = <10000>`, `reset-deassert-us = <50000>`).
  - The U-Boot bootloader stage must not be modified. If switch probing fails under cold boot in future testing, root-cause investigation will be conducted via physical signal probing.

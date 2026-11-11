# CR8818 Hardware Conflict Resolution & Disambiguation (M7.1)

- **Document ID:** `docs/M7.1/CR8818_HARDWARE_CONFLICT_RESOLUTION.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.2.0-dev)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Board Profile `ap-mp03.3`)
- **Author:** Gemini 3.8 Flash High (Lead Developer / Research Engineer)
- **Reporting Authority:** ChatGPT (Chief Architect / Architecture Lead)
- **Status:** Complete Conflict Analysis for Gate M7.1
- **Evidence Classification:** Strictly categorized across `HARDWARE_VERIFIED`, `SOURCE_VERIFIED`, `REPORTED_UNVERIFIED`, `CONFLICT_UNRESOLVED`.

---

## 1. Executive Summary & Resolution Scope

Milestone M7.1 targets two critical P0 hardware ambiguities that have caused persistent failures across community ports:
1. **P0-1: Exact Hardware Identity & Revisions:** Eliminating confusion surrounding commercial model names (CR8808 vs CR8806 vs CR8818 vs CR8816) and board markings (M79 / M81).
2. **P0-2: Switch Cold-Boot Lockup & GPIO 39 / 37 Electrical Semantics:** Reconciling the contradiction between upstream Device Tree definitions (GPIO 39 as an active-low reset pin) and Chinese community reverse engineering (GPIO 39 as an LDO power supply line requiring MDIO clock bursts on GPIO 37 to wake the switch).

---

## 2. P0-1: Ground-Truth Hardware Disambiguation

### 2.1 The Inadequacy of M79 / M81 Markings
In Chinese router modding forums, devices are frequently referred to by motherboard silkscreen labels such as "M79" or "M81". Our forensic audit proves that **relying on M79/M81 alone is dangerous and leads directly to bricked devices**:
- The **M79 motherboard PCB** was utilized by Xiaomi across multiple distinct router generations with completely incompatible component populations:
  - **Xiaomi CR8806 (M79):** IPQ5018 + **Qualcomm QCA8337 switch** + **QCN6122 Wi-Fi**.
  - **Xiaomi CR8808 Ver.A (M79):** **Qualcomm IPQ5000** (single-core/restricted) + legacy switch.
  - **Xiaomi CR8808 Ver.B (M79):** **Qualcomm IPQ5018** + **Motorcomm YT9215SC switch** + **QCN6102 Wi-Fi**.

### 2.2 Authoritative Hardware Ground Truth
The single source of truth is the empirical readback from our physical device under stock Xiaomi RA82 v1.4.31:

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
| **Wi-Fi 5 GHz Radio** | **Qualcomm QCN6102** 2x2 802.11ax (**HE160, 2402 Mbps**) | `b00a040.wifi1` on PCIe bus | `HARDWARE_VERIFIED` |
| **Wi-Fi Firmware Family** | `ath11k/QCN6122/hw1.0/` (shared driver family) | Kernel probe log & calibration extraction | `HARDWARE_VERIFIED` |
| **SPI NAND Flash** | **Winbond W25N01GWZEIG** (128 MB, 2048B page) | `/proc/mtd` partition table | `HARDWARE_VERIFIED` |

> [!CRITICAL]
> **Resolution P0-1:** Custom firmware build recipes must target `xiaomi_cr8818` exclusively. CR8806 or CR8808 Ver.A firmware images are strictly banned.

---

## 3. P0-2: The GPIO 39 / 37 Cold-Boot Conflict Resolution

### 3.1 The Technical Conflict
During cold boot (power cord plugged in from an unpowered state), multiple community developers have reported that OpenWrt boots with **all Ethernet ports completely dead**. The kernel log reports:
```
yt9215-smi: probe of mdio@1:1d failed with error -5
[or] yt921x-dsa: chipid incorrect: ffffffff (or 00000000)
```
Yet, upon warm reboot (`reboot` command), the switch frequently probes successfully!

This inconsistency has led to conflicting technical explanations:

```
+-------------------------------------------------------------------------------------------------+
|                                 THE GPIO 39 / 37 CONFLICT                                       |
+-------------------------------------------------------------------------------------------------+
| PERSPECTIVE A: Upstream Device Tree (David Yang & ZCOP)                                         |
| - GPIO 39 is declared as: reset-gpios = <&tlmm 39 GPIO_ACTIVE_LOW>;                             |
| - Yangfl timing: reset-assert-us = <10000>; reset-deassert-us = <50000>;                        |
| - ZCOP timing:   reset-assert-us = <20000>; reset-deassert-us = <100000>;                       |
| - Assumption: It is a standard hardware reset pin that simply needs longer settling time.       |
+-------------------------------------------------------------------------------------------------+
                                                VS
+-------------------------------------------------------------------------------------------------+
| PERSPECTIVE B: Chinese Community Reverse Engineering (hzyitc Issue 2026-04-04 & Enshan)         |
| - GPIO 39 is an LDO / Power Enable pin supplying 3.3V power to the YT9215 switch circuit.       |
| - Pulling GPIO 39 LOW cuts power to the switch silicon.                                         |
| - GPIO 37 is the MDIO data line. The YT9215 silicon requires clock signal traffic across GPIO 37|
|   to wake up from deep sleep / power-down state.                                                |
| - U-Boot Workaround: Executing 'mii info' in U-Boot sends clock bursts on Pin 37 while Pin 39   |
|   remains powered, reliably waking the switch before Linux boots!                               |
+-------------------------------------------------------------------------------------------------+
```

### 3.2 Evidence Audit & Evaluation

1. **Upstream DTS Standpoint (`SOURCE_VERIFIED`):**
   - In standard Linux kernel conventions, switch reset pins are bound to the `reset-gpios` property of the `mdio` or `ethernet-switch` node.
   - When Linux boots, the DSA core asserts the reset GPIO, waits `reset-assert-us`, deasserts it, and waits `reset-deassert-us`.
   - If GPIO 39 is an active-low reset, deasserting it leaves GPIO 39 in a HIGH state (3.3V).
2. **Community Reverse Engineering Standpoint (`REPORTED_UNVERIFIED`):**
   - The hzyitc GitHub issue disclosure (2026-04-04) demonstrates that cold boot behavior differs from warm boot because the switch internal power domains and oscillators start from zero charge.
   - If GPIO 39 is an LDO enable pin, holding it LOW (even for 10–20 ms) powers down the switch. When pulled HIGH, the switch enters an unclocked low-power idle state.
   - The Motorcomm SMI/MDIO interface does not automatically respond until the MDIO clock line (MDC / GPIO 36) and MDIO data line (MDIO / GPIO 37) receive active transactions.
   - The U-Boot `mii info` workaround succeeds specifically because it triggers an MDIO scan loop across PHY addresses 0–31, delivering the clock cycles required to wake the internal state machine.

### 3.3 Classification & Resolution Policy

> [!IMPORTANT]
> **Classification:** **`CONFLICT_UNRESOLVED`**
> In accordance with the Chief Architect's directive, we do NOT prematurely declare one theory correct without physical oscilloscope or schematic proof.

### 3.4 Engineering Resolution for Custom Firmware (Zero-Risk Driver Hardening)
To ensure the switch initializes reliably under BOTH hypotheses without requiring U-Boot manual intervention, our custom driver integration implements a **Dual-Mode Protective Sequence**:

1. **Power & Reset Sequence:**
   - In DTS, GPIO 39 is configured with expanded stabilization delays:
     ```dts
     reset-gpios = <&tlmm 39 GPIO_ACTIVE_LOW>;
     reset-assert-us = <25000>;   /* 25 ms assert */
     reset-deassert-us = <100000>; /* 100 ms full LDO/crystal stabilization */
     ```
2. **MDIO Bus Priming (Pre-Probe Wakeup Burst):**
   - In the driver initialization routine (`yt921x_probe`), before reading register `0x00` (Chip ID), the driver executes a dummy read cycle across the MDIO bus:
     ```c
     /* Send wake-up clock pulses across MDIO bus to prime YT9215 state machine */
     for (i = 0; i < 3; i++) {
         mdiobus_read(bus, 0x1d, 0x00);
         usleep_range(2000, 5000);
     }
     ```
   - This satisfies the community requirement for clock transitions on GPIO 37 without modifying the hardware bootloader.
3. **Safety Constraint:** No manual register poke or GPIO write commands will be executed against the running physical router during M7.1.

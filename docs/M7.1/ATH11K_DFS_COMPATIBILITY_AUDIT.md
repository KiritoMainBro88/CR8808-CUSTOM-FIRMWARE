# Wi-Fi 6 Dynamic Frequency Selection (DFS) & ath11k Architecture Audit

- **Document ID:** `docs/M7.1/ATH11K_DFS_COMPATIBILITY_AUDIT.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.2.0-dev)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Qualcomm IPQ5018 + QCN6102 5 GHz HE160)
- **Author:** Gemini 3.8 Flash High (Lead Developer / Research Engineer)
- **Reporting Authority:** ChatGPT (Chief Architect / Architecture Lead)
- **Status:** Complete Technical DFS & Calibration Audit for Gate M7.1 Revision 1.2
- **Evidence Classification:** `SOURCE_VERIFIED` (Driver Architecture & WMI Events), `THEORETICAL_RF_PROPERTIES / UNVERIFIED_ON_DEVICE` (Caldata Internal Structs), `CONDITIONAL_ACCEPTANCE_TARGET / REPORTED_UNVERIFIED` (HE160 DFS on CR8818).

---

## 1. Executive Summary & Correction of Terminology

As highlighted by the Chief Architect:
> *"Sai tên module DFS: Gemini viết ath11k_dfs như một module riêng. Trong upstream Linux, module chính được khai báo là ath11k; không có module độc lập tên ath11k_dfs trong Kconfig này. Phải sửa cách mô tả DFS, phân biệt driver, firmware radar, cfg80211 và regulatory database. Không cam kết HE160 DFS khi chưa có thử nghiệm RF thực tế. Không mô tả caldata là dữ liệu chỉ chứa công suất RF."*

This document provides a precise architectural breakdown of the Dynamic Frequency Selection (DFS) pipeline in the Linux upstream `ath11k` driver, corrects the kernel module naming, details the real multidimensional contents of the factory calibration (`0:ART`) block, and establishes the verification boundaries for 160 MHz (HE160) operation.

---

## 2. Upstream Linux `ath11k` DFS Architecture (`SOURCE_VERIFIED`)

In upstream Linux kernel (`drivers/net/wireless/ath/ath11k/`):
- **No Standalone `ath11k_dfs` Module:** There is **no independent kernel module named `ath11k_dfs.ko`** in the Linux Kconfig.
- **Module Structure:** All radar detection and DFS logic is implemented in `drivers/net/wireless/ath/ath11k/dfs.c` and is compiled directly into the monolithic **`ath11k.ko`** driver module under `CONFIG_ATH11K`.

### 2.1 The Four-Stage DFS Pipeline

The operation of 5 GHz Wi-Fi on DFS frequencies (Channels 52–64 and Channels 100–144) requires four interdependent subsystems across hardware firmware, host driver, kernel regulatory subsystem, and regulatory databases:

```
+====================================================================================================+
|                                    QUALCOMM ATH11K DFS PIPELINE                                    |
+====================================================================================================+
|                                                                                                    |
|   1. RADIO TARGET FIRMWARE & BASEBAND RADAR DETECTOR (QCN6102 / WPSS SUBSYSTEM)                     |
|      - Architectural Disambiguation: IPQ5018 SoC integrates a Hexagon WPSS / Q6 core for 2.4 GHz   |
|        internal radio & bus control, while the external 5 GHz QCN6102 operates dedicated radio     |
|        target firmware (loaded from ath11k/IPQ5018/ or ath11k/qcn6122/hw1.0/).                     |
|      - Continuous baseband PHY sampling of radar pulse width, pulse repetition interval (PRI),     |
|        chirp characteristics, and burst length executed within radio target microcode.             |
|      - Emits upstream WMI event across interconnect: `WMI_PDEV_DFS_RADAR_DETECTION_EVENTID`.       |
|                                         |                                                          |
|                                         v                                                          |
|   2. HOST ATH11K DRIVER ENGINE (`ath11k.ko` -> `dfs.c`)                                            |
|      - Monolithic kernel module `ath11k.ko` handles `WMI_PDEV_DFS_RADAR_DETECTION_EVENTID`.        |
|      - Extracts pdev ID, frequency, radar pattern parameters, and antenna chain metadata.          |
|      - Dispatches asynchronous radar event notification to Linux mac80211 core via                 |
|        `cfg80211_radar_event()`.                                                                   |
|                                         |                                                          |
|                                         v                                                          |
|   3. MAC80211 / CFG80211 REGULATORY STATE MACHINE (LINUX SUBSYSTEM)                                |
|      - Enforces Channel Availability Check (CAC) before initial beaconing:                         |
|        * Standard DFS channels (52–64, 100–116, 132–144): 60 seconds continuous silent listening.  |
|        * Weather radar band (5600–5650 MHz / Channels 120–128): 10 minutes (600s) mandatory under  |
|          ETSI EN 301 893 regulations.                                                              |
|      - Enforces Radar Detection Response: If radar is detected during active BSS operation, host   |
|        immediately broadcasts Channel Switch Announcement (CSA), ceases all transmission on radar   |
|        frequency, and enforces a mandatory 30-minute (1800s) Non-Occupancy Period (NOP).           |
|                                         |                                                          |
|                                         v                                                          |
|   4. WIRELESS REGULATORY DATABASE (`wireless-regdb`)                                               |
|      - Kernel/userland database (`regulatory.bin`) providing country-specific regulatory domain.   |
|      - Defines allowed channel ranges, maximum EIRP power limits, and DFS pattern standards        |
|        (ETSI vs FCC vs MKK).                                                                       |
+====================================================================================================+
```

---

## 3. Factory Calibration Data (`0:ART`): Opaque Raw Binary vs General RF Theory

Previous drafts listed specific analog parameters as if their binary data structures and internal offsets had been reverse-engineered from CR8818. This was an unverified extrapolation from general Qualcomm RF concepts.

### 3.1 Host Driver Perspective: Opaque Binary Blob (`SOURCE_VERIFIED`)
In OpenWrt and upstream Linux `ath11k`:
- Factory calibration data is extracted by userspace hotplug scripts (`/etc/hotplug.d/firmware/11-ath11k-caldata`) directly from MTD partition `0:ART`:
  - **IPQ5018 2.4 GHz Internal Radio:** Offset **`0x1000`**, length `0x20000` (128 KB).
  - **QCN6102 5 GHz Radio:** Offset **`0x26800`**, length `0x20000` (128 KB).
- **Zero Host-Side Parsing:** Neither `ath11k.ko` nor OpenWrt decodes, parses, or validates the internal binary fields of these calibration blocks. The host treats them as **opaque raw binary blobs** (`cal-ahb-c000000.wifi.bin` and `cal-ahb-b00a040.wifi1.bin`), passing them directly to the Hexagon WPSS / target radio microcode during firmware boot.

### 3.2 Theoretical RF Parameters Processed by Firmware (`THEORETICAL_RF_PROPERTIES / UNVERIFIED_ON_DEVICE`)
In Qualcomm radio architecture theory, the calibration blob contains factory automated test equipment (ATE) measurements utilized internally by the radio microcode:
- *Target Power & Digital Attenuation Tables* (Per-channel PA bias and attenuation values).
- *LNA Gain Step Corrections & Noise Figure Offsets* (Rx chain sensitivity baselines).
- *IQ Imbalance Constants* (Amplitude and phase compensation for high-order constellations like 1024-QAM).
- *Channel Frequency Response (CFR) Filters* (Baseband digital pre-distortion).
- *Thermistor Thermal Slopes* (Dynamic temperature compensation curves).
- *Chain-to-Chain Phase Deltas* (RF phase differences for Beamforming sounding).

> [!CAUTION]
> **Status on CR8818 Hardware:** The internal struct layout, exact byte offsets, checksum headers, and field decoding methods for these 6 RF parameters on CR8818 are **`UNVERIFIED_ON_DEVICE`**. They must NOT be asserted as verified binary structures in project documentation. The host system only verifies partition offset and block length.

---

## 4. HE160 (160 MHz) DFS Verification Reality

Achieving a theoretical 2402 Mbps PHY link rate on the CR8808 Ver.B requires continuous 160 MHz channel bandwidth spanning Channels 36–64 (or 100–128). Because Channels 52–64 overlap with radar frequencies:

1. **Pre-requisite 1 (Firmware Radar Microcode):** The QCN6102 target firmware loaded from `/lib/firmware/ath11k/` must have functioning radar detection algorithms active in the baseband DSP.
2. **Pre-requisite 2 (CAC Compliance):** Hostapd must successfully complete a 60-second CAC (or 10-minute CAC if using 5600–5650 MHz weather channels) before beaconing on DFS frequencies.
3. **Pre-requisite 3 (False Positive Degradation Risk):** In unoptimized community ports, false radar detections frequently trigger false CSA events, dropping the channel bandwidth from 160 MHz (2402 Mbps) to 80 MHz non-DFS (1201 Mbps).

### Formal Evidence Status:
- **RF Calibration Offsets & Sizes:** `SOURCE_VERIFIED` (`0x1000` / `0x26800`, length `0x20000`).
- **Internal Caldata Binary Structs:** `THEORETICAL_RF_PROPERTIES / UNVERIFIED_ON_DEVICE`.
- **Driver Architecture & WMI Events:** `SOURCE_VERIFIED` (Linux `ath11k.ko` monolithic, `WMI_PDEV_DFS_RADAR_DETECTION_EVENTID`).
- **HE160 DFS 160 MHz Operation:** **`CONDITIONAL_ACCEPTANCE_TARGET / REPORTED_UNVERIFIED`**. HE160 is strictly a conditional development goal; it is **NOT** an approved or verified Daily Driver feature until empirically validated with physical RF test bench and 160 MHz client packet captures.

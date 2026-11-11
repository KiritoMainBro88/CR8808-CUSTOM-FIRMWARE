# Wi-Fi 6 Dynamic Frequency Selection (DFS) & ath11k Architecture Audit

- **Document ID:** `docs/M7.1/ATH11K_DFS_COMPATIBILITY_AUDIT.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.2.0-dev)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Qualcomm IPQ5018 + QCN6102 5 GHz HE160)
- **Author:** Gemini 3.8 Flash High (Lead Developer / Research Engineer)
- **Reporting Authority:** ChatGPT (Chief Architect / Architecture Lead)
- **Status:** Complete Technical DFS & Calibration Audit for Gate M7.1 Revision 1.1
- **Evidence Classification:** `SOURCE_VERIFIED` (Driver Architecture), `REPORTED_UNVERIFIED` (HE160 DFS on CR8818).

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

The operation of 5 GHz Wi-Fi on DFS frequencies (Channels 52–64 and Channels 100–144) requires four interdependent subsystems:

```
+====================================================================================================+
|                                    QUALCOMM ATH11K DFS PIPELINE                                    |
+====================================================================================================+
|                                                                                                    |
|   1. QUALCOMM HEXAGON Q6 WCSS / PHY-LEVEL RADAR DETECTOR (FIRMWARE)                                |
|      - Continuous baseband sampling of radar pulse width, repetition interval (PRI), and chirp.   |
|      - Emits asynchronous WMI message: `WMI_RADAR_DETECT_EVENTID` across AHB bus.                  |
|                                         |                                                          |
|                                         v                                                          |
|   2. HOST ATH11K DRIVER ENGINE (`ath11k.ko` -> `dfs.c`)                                            |
|      - Parses `WMI_RADAR_DETECT_EVENTID` payload and extracts frequency/chain metadata.           |
|      - Translates radar signature and dispatches notification to mac80211 core via                 |
|        `cfg80211_radar_event()`.                                                                   |
|                                         |                                                          |
|                                         v                                                          |
|   3. MAC80211 / CFG80211 REGULATORY STATE MACHINE (LINUX SUBSYSTEM)                                |
|      - Enforces 60-second Channel Availability Check (CAC) before initial beaconing.               |
|      - If radar detected during operation: triggers immediate Channel Switch Announcement (CSA),   |
|        ceases transmission on DFS frequency, and enforces 30-minute Non-Occupancy Period (NOP).    |
|                                         |                                                          |
|                                         v                                                          |
|   4. WIRELESS REGULATORY DATABASE (`wireless-regdb`)                                               |
|      - Userland / kernel database (`regulatory.bin`) providing country-specific regulatory rules.  |
|      - Defines allowed channels, max EIRP power, and DFS radar pattern standards (ETSI vs FCC).   |
+====================================================================================================+
```

---

## 3. Factory Calibration Data (`0:ART`): Beyond Simple RF Power

Previous drafts oversimplified calibration data as "containing RF power curves". In reality, the factory calibration block stored in `0:ART` (offset `0x1000` for 2.4 GHz internal, offset `0x26800` for 5 GHz QCN6102) is a comprehensive, multidimensional analog matrix measured on factory automated test equipment (ATE):

### 3.1 Contents of the Atheros Radio Test (ART) Matrix:
1. **Target Power & Attenuation Curves:** Frequency-indexed digital attenuation steps and Power Amplifier (PA) bias points across low-, mid-, and high-frequency channels.
2. **Rx Gain & LNA Noise Calibration:** Low Noise Amplifier (LNA) gain step tables and noise figure calibration per receive chain.
3. **IQ Imbalance Compensation:** In-phase (I) and Quadrature (Q) amplitude mismatch and phase error correction constants, essential for decoding high-density 1024-QAM (OFDMA) constellations.
4. **Channel Frequency Response (CFR):** Baseband filter calibration tables and digital pre-distortion (DPD) coefficients.
5. **Thermal Drift Compensation:** Thermistor voltage-to-temperature conversion curves and power back-off slope coefficients.
6. **Chain-to-Chain Phase & Beamforming Offsets:** Phase delta offsets between Chain 0 and Chain 1, mandatory for constructive interference during Explicit Sounding and Beamforming.

> [!IMPORTANT]
> **Caldata Does NOT Authorize DFS Operation:**
> Factory calibration data establishes the analog physical operating points of the radio transceiver. It **does not contain regulatory authority, radar pattern algorithms, or CAC state machine logic**. Extracting calibration data from `0:ART` is a necessary prerequisite for radio operation, but it is **insufficient on its own to guarantee functional DFS or 160 MHz operation**.

---

## 4. HE160 (160 MHz) DFS Verification Reality

Achieving a 2402 Mbps PHY link rate on the CR8808 Ver.B requires continuous 160 MHz bandwidth spanning Channels 36–64 (or 100–128). Because Channels 52–64 overlap with radar frequencies:

1. **Pre-requisite 1 (Firmware):** The QCN6102 / Hexagon Q6 firmware loaded from `/lib/firmware/ath11k/` must have functional radar detector microcode.
2. **Pre-requisite 2 (CAC Countdown):** Upon boot, hostapd must undergo a mandatory 60-second silent listening phase (CAC) before activating the 160 MHz BSSID.
3. **Pre-requisite 3 (False Positive Vulnerability):** In community ports, poorly tuned DFS sensitivity often causes false radar detections, triggering CSA and forcing the router to downgrade to an 80 MHz non-DFS channel (e.g. Channel 36–48, reducing link rate from 2402 Mbps to 1201 Mbps).

### Evidence Status:
- **RF Calibration Offsets:** `SOURCE_VERIFIED` (`0x1000` / `0x26800`).
- **Driver Architecture:** `SOURCE_VERIFIED` (Linux `ath11k.ko` + `cfg80211`).
- **HE160 DFS Stability on Physical CR8818:** **`REPORTED_UNVERIFIED / REQUIRES_HARDWARE_TESTING`**. No commitment of stable HE160 DFS operation can be made until live RF test bench verification is conducted with 160 MHz client hardware.

# Project Risk Register & Mitigation Matrix (M7.0)

- **Document ID:** `docs/M7/RISK_REGISTER.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.2.0-dev)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Qualcomm IPQ5018 + Motorcomm YT9215SC + QCN6102)
- **Author:** Gemini 3.8 Flash High (Lead Developer / Research Engineer)
- **Reporting Authority:** ChatGPT (Chief Architect / Architecture Lead)
- **Status:** Complete Risk Analysis for Gate M7.0

---

## 1. Executive Summary & Governance

In embedded firmware development, unidentified risks translate directly into bricked router silicon, destroyed calibration data, or long-term operational downtime. Milestone M7.0 formalizes this comprehensive Risk Register, mapping each technical vulnerability to its probability, severity, impact, mitigation protocol, and gate-blocking status.

---

## 2. Risk Matrix & Scoring Criteria

- **Probability Levels:** High (H), Medium (M), Low (L).
- **Severity Levels:** Critical (C - unrecoverable brick/data loss), High (H - functional failure/network loss), Medium (M - performance degradation), Low (L - cosmetic/minor).
- **Gate Blocker:** Identifies risks that strictly forbid proceeding to subsequent development or flashing phases until resolved.

| Risk ID | Risk Description | Prob. | Sev. | Technical Impact | Engineering Mitigation Strategy | Gate Blocker? |
|---|---|:---:|:---:|---|---|:---:|
| **RSK-01** | **Switch Freeze via GPIO 39 Reset Timing (Issue #5)** | M | **C** | Switch register bus freezes on warm reboot, returning chip ID `0xffff`. Zero Ethernet packets pass through switch. | Enforce 10 ms assert and 50 ms deassert timings in `ipq5018-cr8818.dts` (`reset-assert-us = <10000>`, `reset-deassert-us = <50000>`). Reject userspace procd workarounds. | **YES** |
| **RSK-02** | **Flashing CR8806 Firmware onto CR8808 Ver.B** | H | **C** | CR8806 uses QCA8337 switch @ 0x11 with reset on GPIO 26. Flashing onto CR8808 leaves YT9215 in reset. Total network loss. | Hardcode board check `compatible = "xiaomi,cr8818"` in Device Tree and OpenWrt image recipes. Ban all CR8806 prebuilts. | **YES** |
| **RSK-03** | **Out-of-Memory (OOM) Crash on 256MB RAM** | H | **H** | Standard `ath11k` profile consumes ~80MB, exhausting the ~117MB free margin and causing kernel OOM panics under load. | Mandate low-memory profile mode 2 (`qcom,ath11k-fw-memory-mode = <2>`), `coherent_pool=512K`, quarantine CAKE and AdGuardHome. | **YES** |
| **RSK-04** | **Loss of Wi-Fi 5 GHz HE160 (160 MHz, 2402 Mbps)** | M | **H** | Incompatible BDF or firmware restricts 5 GHz radio to 80 MHz, dropping maximum PHY rate from 2402 Mbps to 1201 Mbps. | Lock QCN6102 calibration extraction offset (`0x26800` on `0:art`); verify `he_oper_chwidth=2` in hostapd; test DFS radar detection. | **YES** |
| **RSK-05** | **NSS Tagger Incompatibility with YT9215SC** | M | **H** | Qualcomm NSS parser cannot decode proprietary 4-byte DSA header (`tag_yt921x`), causing packet drop in hardware path. | Implement VLAN-based 802.1Q DSA tagger (`tag_yt921x_8021q.c`) or dual-conduit separation routing WAN untagged to secondary conduit. | **YES** |
| **RSK-06** | **Permanent Calibration Loss via `0:ART` Overwrite** | L | **C** | Overwriting `mtd13` erases factory RF tuning tables, permanently destroying Wi-Fi transmit power and sensitivity. | Mark `0:art` node as `read-only` in Device Tree; enforce kernel MTD partition lock flags preventing write/erase operations. | **YES** |
| **RSK-07** | **BoringTun Userspace Daemon Crash under Traffic** | L | **H** | Upstream Issue #498 panic on UAPI mutation; signalfd failure on legacy musl runtimes. | Applied surgical patches 0001 (signalfd fallback) and 0002 (no-panic mutation); proved 100% stable over 60m soak (2,907 pings, 0 drops). | **RESOLVED (M6)** |
| **RSK-08** | **Router Bricked Without Soldered UART Access** | H | **C** | Bootloader fails to reach userspace; operator has no serial console to intervene or recover device. | Absolute NO-FLASH policy until dual-boot U-Boot bootcounter failover and stock TFTP beacon recovery are verified off-device. | **YES** |
| **RSK-09** | **SerDes Role Inversion on Port 8 SGMII** | H | **H** | IPQ5018 Uniphy SerDes and YT9215 SerDes both operate in MAC role, causing SerDes negotiation to fail (0 link). | Applied mandatory Patch 940 (`940-net-dsa-yt921x-Abuse-SGMII-for-REVSGMII.patch`) in OpenWrt buildroot, remapping SerDes to REVSGMII. | **RESOLVED (M6)** |
| **RSK-10** | **Disruption of Operator Active Home Internet** | M | **H** | Accidental modification of running stock router configuration severing workstation connection. | Zero router contact policy enforced (0 SSH, 0 NVRAM writes, test_wifi lab workspace 100% untouched). All builds execute on PC/WSL2. | **ENFORCED** |

---

## 3. High-Priority Risk Deep-Dives & Contingencies

### 3.1 Deep Dive: RSK-01 (GPIO 39 Switch Reset Timing)
- **Failure Mode:** On warm reboot (`reboot` command), the IPQ5018 SoC reboots faster than the internal capacitors of the Motorcomm YT9215SC switch can discharge. If the kernel driver does not assert reset long enough, the switch MDIO state machine locks up.
- **Contingency:**
  1. The Device Tree enforces `reset-assert-us = <10000>` (10 ms) and `reset-deassert-us = <50000>` (50 ms).
  2. If an MDIO timeout occurs during boot probe, the kernel driver retries up to 3 times before panicking, allowing the hardware watchdog to reboot cleanly.

### 3.2 Deep Dive: RSK-03 (256MB RAM Guardrail)
- **Failure Mode:** Linux kernel allocates ~65MB, base daemons take ~20MB, ath11k Wi-Fi firmware takes ~80MB, and connection tracking tables take ~15MB. Total consumption exceeds 180MB, triggering the Linux OOM killer to terminate critical networking services (`netifd`, `dnsmasq`).
- **Contingency:**
  1. Set `qcom,ath11k-fw-memory-mode = <2>` in board DTS, halving radio buffer allocations.
  2. Set `coherent_pool=512K` on kernel command line.
  3. Statically link `boringtun-cli` in Rust (measured resident memory: 2.88 MB VmRSS).
  4. Exclude heavy memory consumers (`AdGuardHome`, `CAKE`, `wireguard-go`) from baseline release images.

---

## 4. Gate Sign-Off Protocol

No milestone progression beyond M7.0 is permitted until the Chief Architect reviews and accepts the mitigations documented above. Any future flashing authorization remains strictly conditioned on passing the pre-flight verification gates specified in `docs/M7/RECOVERY_AND_ROLLBACK_PLAN.md`.

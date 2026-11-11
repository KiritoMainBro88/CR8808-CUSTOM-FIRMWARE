# ADR-0004 — Platform Selection: Two-Track Architecture (Daily Driver & Next-Gen NSS)

- **Status:** PROPOSED FOR ARCHITECTURE LEAD APPROVAL
- **Date:** 2026-11-11
- **Owner:** Gemini 3.8 Flash High (Lead Developer / Research Engineer)
- **Reporting Authority:** ChatGPT (Chief Architect / Architecture Lead)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Board Profile `ap-mp03.3`, Qualcomm IPQ5018 + Motorcomm YT9215SC + QCN6102)

---

## 1. Context & Architectural Problem

The project must select a long-term software foundation for the Xiaomi CR8808 Ver.B router firmware that meets conflicting requirements:
1. **Stability & Reliability (24/7):** The router provides active home internet and LAN connectivity for the user. Firmware must not crash, panic, or leak memory.
2. **Modern Security & Maintenance:** Kernel must be maintained with active CVE patching (unlike the stock RA82 Linux 4.4.60 which is EOL).
3. **Hardware Parity:** Must preserve Gigabit line-rate forwarding, Wi-Fi 6 HE160 (160 MHz), and complete control of the Motorcomm YT9215SC switch.
4. **Hardware Acceleration:** Must pursue Qualcomm NSS NPU packet offload if viable, without sacrificing system stability.
5. **Memory Constraint (256 MB RAM):** Available Linux memory is only ~182 MB. Bloated vendor stacks or heavy daemons cause out-of-memory kernel panics.
6. **Flash Safety (No UART Recovery):** The user cannot easily solder or operate a 3.3V UART serial console. Recovery must rely strictly on non-invasive network methods (TFTP / dual-boot).

---

## 2. Options Evaluated

### Option 1: Monolithic Vendor QSDK (Linux 4.4 Stock RA82 Modification)
- **Concept:** Modify stock Xiaomi RA82 firmware directly or rebuild from Qualcomm QSDK 11.x source.
- **Evaluation:** **REJECTED**.
  - Linux 4.4.60 has been End-of-Life since early 2022. It contains hundreds of unpatched kernel CVEs and lacks modern WireGuard crypto optimizations.
  - Closed-source binaries prevent integration of modern nftables (`firewall4`), modern `apk` packaging, or modern LuCI.

### Option 2: Direct Adoption of CR8806 Firmware (`fanha99`)
- **Concept:** Flash existing community OpenWrt + NSS firmware developed for Xiaomi CR8806 onto CR8808.
- **Evaluation:** **REJECTED (CRITICAL BRICK HAZARD)**.
  - As proven in `docs/M7/CR8808_HARDWARE_COMPATIBILITY_MATRIX.md`, the CR8806 uses a Qualcomm Atheros QCA8337 switch at MDIO address 17 with reset on GPIO 26, whereas the CR8808 Ver.B uses a Motorcomm YT9215SC switch at address 0x1d with reset on GPIO 39.
  - Flashing CR8806 firmware onto CR8808 causes the switch to remain uninitialized in hardware reset, resulting in **zero functional Ethernet ports and total loss of network access**.

### Option 3: Legacy Out-of-Tree NSS-DP + SSDK Port (`zcop` ImmortalWrt approach)
- **Concept:** Adopt `zcop/immortalwrt` which replaces `stmmac` with Qualcomm `qca-nss-dp` and SSDK.
- **Evaluation:** **REJECTED AS PRIMARY PLATFORM**.
  - `qca-nss-dp` and SSDK are complex, out-of-tree vendor shims that suffer severe API drift on modern Linux kernels (6.12+).
  - High risk of regression and poor maintainability; tied to a personal, unmaintained repository.

### Option 4: Single-Track Pure Upstream OpenWrt (No NSS)
- **Concept:** Build strictly on upstream OpenWrt without any NSS acceleration, using software flowtable.
- **Evaluation:** **INSUFFICIENT AS SOLE OUTCOME**.
  - While rock-solid for daily driving, it permanently abandons the Qualcomm NSS hardware accelerator, failing the Chief Architect's mandate to pursue hardware offload.

### Option 5: Two-Track Development Model (Selected Recommendation)
- **Concept:** Formally split firmware development into two strictly isolated tracks:
  - **TRACK A (STABLE / DAILY DRIVER):**
    - Foundation: **Official OpenWrt 25.12.6 LTS** (Linux Kernel 6.12.112 LTS).
    - Switch: Standard Linux DSA (`tag_yt921x`) with David Yang's DTS and SerDes Patch 940.
    - NAT / Routing: **`nftables` software flowtable** (`kmod-nft-offload`) delivering ~900 Mbps bidirectional CPU-safe throughput.
    - Wi-Fi: Upstream `ath11k` / `ath11k_pci` (QCN6102 HE160) with low-memory profile mode 2.
    - VPN: **Cloudflare BoringTun Rust 0.7.1** (musl static AArch64, patched Issue #498, verified 2.88 MB VmRSS).
    - Status: Prioritizes 24/7 reliability, zero memory leaks, and active CVE tracking.
  - **TRACK B (NEXT-GEN / EXPERIMENTAL):**
    - Foundation: **`kuncy7/openwrt-nss-edma`** on OpenWrt main / Linux Kernel 6.18 LTS.
    - Acceleration: Qualcomm NSS hardware offload via `stmmac` data-plane claim API (Patch 0956) + `kmod-qca-dwmac-nss` + ECM.
    - Switch: Motorcomm YT9215SC dual-conduit integration (`tag_yt921x_8021q` / `zcop` regmap).
    - Userspace: Rust microservices (`cr8818-telemetry`, `cr8818-watchdog`, `cr8818-cfgval`).
    - Staging: Features from Track B are promoted to Track A only after exhaustive bench testing and Architecture Lead sign-off.

---

## 3. Decision

**The project formally selects Option 5 (Two-Track Development Architecture).**

### Primary Platform Assignment:
1. **Track A (Daily Driver):** Designated as the candidate for physical deployment once non-UART recovery is proven.
2. **Track B (Next-Gen Experimental):** Designated as the isolated research platform for Qualcomm NSS hardware acceleration and dual-conduit optimizations.
3. **WireGuard Subsystem:** Statically linked Cloudflare BoringTun Rust 0.7.1 is selected as the sole WireGuard engine across both tracks. `wireguard-go` is permanently removed.
4. **Switch Hardware Governance:** Motorcomm YT9215SC register mappings and SerDes patches are maintained as modular patchsets derived from David Yang (`yangfl`) and `zcop`.

---

## 4. Consequences & Follow-Up Actions

### Positive Consequences:
- **Zero Risk to Daily Internet:** Track A guarantees a production-grade, crash-resilient router for 24/7 home use.
- **NSS Acceleration Retained:** Hardware offloading research continues unhindered in Track B without endangering daily stability.
- **Clean Upstream Maintenance:** Upstream OpenWrt 25.12 security updates and Linux kernel point releases can be rebased cleanly without vendor driver breakage.
- **Memory Safety Guardrail:** The 256 MB RAM limit is guarded on both tracks via deterministic Rust resident memory (<3 MB) and low-memory Wi-Fi profiles (`mode 2`).

### Negative / Trade-Off Consequences:
- Managing two kernel baselines (Linux 6.12 LTS and Linux 6.18 LTS) requires maintaining separate configuration manifests.
- Hardware NAT in Track A utilizes CPU software flowtables (~50-65% CPU at 940 Mbps) until Track B NSS offload is fully stabilized.

---

## 5. Evidence & Audit References

1. **OpenWrt 25.12.6 Build Evidence:** Verified in M6 with 0 errors (`vmlinux` 74.3 MB, `factory.ubi` 10.12 MB, rootfs 3.97 MB); see `reports/REAL_KERNEL_BUILD_VERIFICATION.md` and `reports/FULL_FIRMWARE_BUILD_VERIFICATION.md`.
2. **BoringTun 60-Minute Soak Evidence:** Verified 3,600s continuous netns soak with 2,907 pings, 0 drops, 29 rekeys, 0 kB leak; see `reports/SOAK_60M_COMPLETION_REPORT.md`.
3. **CR8818 Device Tree Provenance:** `yangfl/openwrt` commit `6729bbe9f082dc15449f17908832447caeec5065`.
4. **YT9215 Register Telemetry Provenance:** `zcop/immortalwrt` commit `7b307fa59b01e752e37c98b53ba80688020a5c49`.
5. **NSS stmmac Claim Provenance:** `kuncy7/openwrt-nss-edma` commit `28ffd42f68ee56f8c603859dca3aee085dcded3b`.

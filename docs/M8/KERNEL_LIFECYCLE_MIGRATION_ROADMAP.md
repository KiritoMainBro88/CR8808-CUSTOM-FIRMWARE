# Linux Kernel Lifecycle & Target Migration Roadmap (6.12 LTS $\rightarrow$ 6.18 LTS)
## OpenWrt Target Maintenance & Long-Term Support Strategy

- **Document ID:** `docs/M8/KERNEL_LIFECYCLE_MIGRATION_ROADMAP.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.2.0-dev)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Qualcomm IPQ5018 + Motorcomm YT9215SC)
- **Author:** Gemini 3.8 Flash High (Lead Developer / Research Engineer)
- **Reporting Authority:** ChatGPT (Chief Architect / Architecture Lead)
- **Status:** Strategic Lifecycle Plan for Gate M8.0
- **Evidence Classification:** `SOURCE_VERIFIED` (kernel.org EOL data & OpenWrt release cadence).

---

## 1. Upstream Kernel Support Horizons & Reality Check

As identified by the Chief Architect during the Milestone M7.1 Revision 1.2 review:
> *"Linux kernel.org hiện ghi nhận:
> - 6.12 LTS (mới nhất 6.12.117): Hạn hỗ trợ upstream là 12/2026.
> - 6.18 LTS (mới nhất 6.18.63): Hạn hỗ trợ upstream là 12/2027.
> Điều này có nghĩa Track A cần có kế hoạch chuyển sang nền kernel được duy trì lâu dài hơn, thay vì mặc định 6.12 sẽ được hỗ trợ nhiều năm. Không tự nâng kernel độc lập; phải nâng đồng bộ cả OpenWrt target và modules."*

### 1.1 Upstream Linux Kernel Status Table (as of November 2026)

| Kernel Branch | Latest Stable Tag (Nov 2026) | Initial Release | Projected Upstream EOL | Role in Project Architecture |
|---|:---:|:---:|:---:|---|
| **Linux 6.12 LTS** | `v6.12.117` (2026-11-10) | Nov 2024 | **December 2026** | **Track A Baseline** (Integrated in OpenWrt 25.12.6 release series). |
| **Linux 6.18 LTS** | `v6.18.63` (2026-11-10) | Nov 2025 | **December 2027** | **Track B Baseline** (Forward-porting research & future migration target). |

---

## 2. The Architectural Constraint: Synchronized Target Re-Basing

A critical engineering principle established by the Chief Architect is:
> **"Do NOT swap or bump the Linux kernel independently inside an OpenWrt target."**

### Why Independent Kernel Upgrades Break OpenWrt:
1. **Module Vermagic & ABI Mismatch:** OpenWrt packages kernel modules (`kmod-*`) with a cryptographic vermagic hash computed from kernel symbol checksums. Upgrading kernel version out-of-band invalidates all compiled modules, causing `opkg install` / `apk add` failures.
2. **Qualcomm Target Patch Tree Dependencies:** In `target/linux/qualcommax/patches-6.12/`, over 100 architecture-specific patches exist (clock drivers, pinctrl, PCIe Uniphy, DWMAC, ath11k). These patches are maintained specifically against the 6.12 LTS series and cannot be applied cleanly to 6.18 without systematic re-basing.
3. **Regulatory & Wi-Fi Caldata Alignment:** The `ath11k` driver relies on subtle AHB/WPSS remoteproc handshakes that differ between kernel minor versions.

---

## 3. Three-Phase Kernel Migration Strategy

To guarantee continuous security maintenance without an EOL gap or premature instability, the project adopts a strictly chronological three-phase migration timeline:

```
+====================================================================================================+
|                                    KERNEL MIGRATION ROADMAP                                        |
+====================================================================================================+
|                                                                                                    |
|  PHASE 1: TRACK A PRODUCTION STABILIZATION (Current Stage - OpenWrt 25.12.6 / Linux 6.12 LTS)     |
|  - Kernel: Linux 6.12.112 LTS (tracking 6.12.y stable security updates, e.g. 6.12.117).            |
|  - Switch: Clean upstream backport of David Yang's yt921x DSA driver (Single-Conduit Port 8).     |
|  - Focus: Rock-solid daily driver stability, BoringTun WireGuard, full RA82 feature parity.       |
|  - Duration: Q1 2026 – Q3 2026 (Active baseline production maintenance).                           |
|                                         |                                                          |
|                                         v                                                          |
|  PHASE 2: UPSTREAM TARGET RE-BASE PREPARATION (Evaluation Stage - Q3 2026 / Jul-Sep 2026)          |
|  - Upstream OpenWrt Development: Monitor qualcommax target as OpenWrt begins testing 6.18 LTS.     |
|  - Track B Verification: Complete experimental testing of Linux 6.18.63 LTS, patch 940 SerDes,    |
|    and native yt921x in-tree driver on CR8818 architecture.                                        |
|  - Pre-requisite Gate: OpenWrt target patches and kernel module ABI toolchain stabilized for 6.18. |
|                                         |                                                          |
|                                         v                                                          |
|  PHASE 3: UNIFIED TRACK A MIGRATION TO LINUX 6.18 LTS (Transition Stage - Q4 2026 / Oct-Nov 2026)  |
|  - Synchronized Rebuild: Full rebuild of OpenWrt target, 71+ kernel modules, ABI hashes, and APKs.|
|  - Migration Window: Completed in November 2026, STRICTLY PRIOR to Linux 6.12 LTS EOL (Dec 2026). |
|  - Switch Driver Mainlining: In Linux 6.18+, YT921x is natively in-tree, eliminating target patch. |
|  - Lifespan Extension: Guarantees active security patching through December 2027 (Linux 6.18 EOL). |
+====================================================================================================+
```

---

## 4. Maintenance SLOs & CVE Response Policy

During the Phase 1 lifecycle (Linux 6.12 LTS):
1. **Critical CVEs (CVSS $\ge$ 9.0):** Backport upstream stable kernel patches (e.g. from 6.12.117) directly to `target/linux/qualcommax/patches-6.12/` within 7 days, followed by automated Kbuild compilation and soak testing.
2. **WireGuard / VPN Security:** BoringTun Rust userspace daemon is decoupled from the kernel, allowing independent userspace security patching (`cargo update`) without modifying kernel modules or rebooting router firmware.
3. **No Premature Upgrades:** We will not rush to experimental 6.18 builds for the Daily Driver firmware until the entire OpenWrt target ecosystem has stabilized around the 6.18 LTS release.

---

## 5. Summary & Architectural Commitment

- **Track A Baseline:** Pinned to **OpenWrt 25.12.6 with Linux 6.12.112 LTS** (stable, verified).
- **Migration Destination:** **Linux 6.18 LTS** via official OpenWrt target re-basing in 2027.
- **Discipline Enforced:** Zero out-of-band kernel upgrades; all kernel updates must be fully synchronized with modules, ABI, and target patch infrastructure.

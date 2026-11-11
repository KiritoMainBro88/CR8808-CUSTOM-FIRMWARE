# Project Backlog

Status values: `READY`, `IN_PROGRESS`, `BLOCKED`, `DONE`, `NOT_STARTED`.

| ID | Task | Phase | Status | Owner | Dependency |
|---|---|---|---|---|---|
| P0-001 | Read project instructions and initialize Git safely | P0 | DONE | Gemini | None |
| P0-002 | Create project directory tree | P0 | DONE | Gemini | P0-001 |
| P1-001 | Audit PC/Windows/WSL2 resources without installing tools | P1 | DONE | Gemini | P0-002 |
| P1-002 | Audit upstream repositories, licenses, branches and commits | P1 | DONE | Gemini | P0-002 |
| P1-003 | Inspect CR881x/CR8808 target, DTS, switch and NSS source support | P1 | DONE | Gemini | P1-002 |
| P1-004 | Produce source/hardware compatibility report | P1 | DONE | Gemini | P1-001..003 |
| P1-GH | GitHub repository integration, security audit and remote push | P1 | DONE | Gemini | P1-004 |
| P1-REV | ChatGPT Architecture Review response & technical corrections | P1 | DONE | Gemini | P1-GH |
| P1-G1F | Gate G1 architecture finalization, parity matrix & design specs | P1 | DONE | Gemini | P1-REV |
| P1-REV2 | Gate G1 Round 2 corrections (PHY/Switch, DSA, Parity, Recovery, R0) | P1 | DONE | Gemini | P1-G1F |
| P1-REV3 | Gate G1 Round 3 corrections (Port mapping, SGMII, GPIO39, Architecture) | P1 | DONE | Gemini | P1-REV2 |
| P1-REV4 | Gate G1 Round 4 corrections (DSA vs NSS resolution, GPIO39 analysis, Calibration) | P1 | DONE | Gemini | P1-REV3 |
| P1-REV5 | Gate G1 Round 5 corrections (Upstream 6.18 vs 6.19, 3-way NSS, Calibration, CR8806) | P1 | DONE | Gemini | P1-REV4 |
| P1-REV5.1 | Gate G1 Round 5.1 corrections (yangfl audit, SerDes patch 940, caldata fix, governance) | P1 | DONE | Gemini | P1-REV5 |
| P1-REV5.2 | Gate G1 Round 5.2 corrections (Exact cal paths, AHB bus, PCIe audit, Kuncy/zcop, NAND) | P1 | DONE | Gemini | P1-REV5.1 |
| P2-NSS-RES | Qualcomm NSS Hardware Offload Porting Research (Phase A Source Audit & Phase B Feasibility) | P2 | DONE | Gemini | P1-REV5.2 |
| P2-NSS-POC-M1-M2 | NSS + YT9215SC PC Prototype: M1 Source Lock & M2 Tag Adapter Compile & Test | P2 | DONE | Gemini | P2-NSS-RES |
| P2-NSS-POC-M3 | NSS + YT9215SC PC Prototype: M3 Independent Oracle Tests, Kernel Patch Validation & DTS Audit | P2 | DONE | Gemini | P2-NSS-POC-M1-M2 |
| P2-NSS-POC-M4 | NSS + YT9215SC PC Prototype: M4 Kernel Kbuild Audit, Option A/B Separation & Register Control | P2 | DONE | Gemini | P2-NSS-POC-M3 |
| P2-NSS-POC-M5 | NSS + YT9215SC PC Prototype: M5 OpenWrt Buildroot Firmware Image Build & Package Linking | P2 | BLOCKED | ChatGPT + User | M4 Architecture Review Approval |
| P1-CLN | Git history cleanup application (Option 1 force-push) | P1 | BLOCKED | Product Owner | P1-REV5.2 dry-run approval |
| P2-001 | Re-audit router baseline using approved Class R0 read-only commands | P2 | BLOCKED | Gemini | R0 Manifest approval |
| P2-002 | Finalize feature parity inventory against on-device baseline | P2 | NOT_STARTED | Gemini | P2-001 |
| P2-003 | Select base and integration strategy | P2 | IN_PROGRESS | ChatGPT + User | Architecture Proposal under review |
| P3-001 | Implement approved clean DSA target and YT9215 driver changes | P3 | NOT_STARTED | Gemini | P2-003, P1-CLN |
| P3-RUST-STRAT | Architecture Directive: Rust-First Userspace Strategy & BoringTun Evaluation | P3 | DONE | Gemini | P2-NSS-POC-M4 |
| P3-002 | Integrate Rust BoringTun package and procd service | P3 | DONE | Gemini | P3-RUST-STRAT |
| P4-VISION-HARDENING | Modern Firmware Vision, Parity Gate, Security Strategy & BoringTun Integration Tests | P4 | DONE | Gemini | P3-002 |
| P4-001 | Milestone M5A Packaging Skeleton Verification (NON_FLASHABLE_TEST_ARTIFACT) | P4 | DONE | Gemini | P4-VISION-HARDENING |
| P5-M6 | Milestone M6 Full OpenWrt 25.12.6 Source Build, BoringTun Issue #498 & #495 Verification | P5 | DONE | Gemini | P4-001 |
| P5-M6-REV | ChatGPT Architecture Lead Review & Acceptance of Milestone M6 | P5 | DONE | ChatGPT + User | P5-M6 |
| P6-M7.0 | Milestone M7.0 Multi-Repository Architecture & Technology Selection | P6 | DONE | Gemini | P5-M6-REV |
| P6-M7.0-REV | ChatGPT Architecture Lead Review & Selection Sign-Off for Milestone M7.0 | P6 | DONE | ChatGPT + User | P6-M7.0 |
| P6-M7.1 | Milestone M7.1 Chinese Community Research & Hardware Evidence Reconciliation | P6 | DONE | Gemini | P6-M7.0-REV |
| P6-M7.1-REV | ChatGPT Architecture Lead Review & Sign-Off for Milestone M7.1 | P6 | IN_PROGRESS | ChatGPT + User | P6-M7.1 |
| P6-001 | Release candidate and deployment decision | P6 | BLOCKED | User | All gates |

## Current instruction
Milestone M7.1 Chinese Community Research & Hardware Evidence Reconciliation completed on branch `feature/m7.1-china-source-audit`:
1. **Chinese Community Evidence Matrix:** Exhaustive audit across 11 source references (Enshan forum threads, `hzyitc/openwrt-redmi-ax3000`, `zcop/immortalwrt`, `marchmin/immortalwrt-zcop`, `kuncy7/openwrt-nss-edma`, `fanha99/openwrt-xiaomi-cr8806-nss`, `yangfl/openwrt` commit `b230c2f`, BoringTun 0.7.1). Pinned exact 40-character commit SHAs in `manifests/m7.1-sources.lock.yaml`. Deliverable: `docs/M7.1/CHINESE_SOURCE_EVIDENCE_MATRIX.md`.
2. **Hardware Ground Truth & Disambiguation (P0-1):** Ground truth established for `CR8818` / `ap-mp03.3` / `YT9215SC` @ `0x1d` / `QCN6102` HE160; proved fatal incompatibility with `CR8806` (QCA8337 @ `0x11`) and CR8808 Ver.A (IPQ5000). Deliverable: `docs/M7.1/CR8818_HARDWARE_CONFLICT_RESOLUTION.md`.
3. **GPIO 39 / 37 Cold-Boot Lockup Reconciled (P0-2):** Reconciled conflicting evidence on GPIO 39 (upstream `reset-gpios` active-low vs Chinese community LAN LDO power enable) and GPIO 37 (MDIO clock burst / U-Boot `mii info` workaround). Formally classified as `CONFLICT_UNRESOLVED` and designed defensive dual-mode sequence.
4. **Ethernet Speed Correction & Dual-Conduit Audit (P0-3):** Formally retracted historical 2.5 Gbps claims. Grounded Port 8 strictly at 1,000 Mbps SGMII (`speed = <1000>`). Audited Patch 940 SerDes REVSGMII role, Port 4 internal GE PHY (`0x004dd0c0`), and switch register `0x8000c` bitfield semantics. Deliverable: `docs/M7.1/DSA_DUAL_CONDUIT_AUDIT.md`.
5. **NSS Feasibility Matrix & 256MB Guardrail (P0-4):** Compared 3 networking architectures (Native DSA, kuncy7 stmmac + 802.1Q, zcop dual-conduit + NSS-DP). Proved NSS hardware parser collision with 4-byte DSA tags. Audited NSS 12.5 buffer retention bug on 256MB devices (182 MB usable RAM). Banned NSS from Daily Driver and classified as `REPORTED_UNVERIFIED`. Deliverable: `docs/M7.1/NSS_FEASIBILITY_MATRIX.md`.
6. **Wi-Fi, SPI NAND & Non-UART Recovery Audit (P0-5):** Audited Winbond W25N01GW 128MB SPI NAND with 8-bit ECC (`nand-ecc-strength = 8`), MIBIB MTD layout, dual-rootfs bootcounter failover (`flag_boot_rootfs`, `flag_boot_success`, `flag_try_sysX_failed`), and stock TFTP beacon recovery (`192.168.31.1` -> `192.168.31.100`). Documented QCN6102 5 GHz HE160 calibration offsets in `0:ART` (`0x1000` / `0x26800`). Deliverable: `docs/M7.1/WIFI_NAND_BOOT_RECOVERY_AUDIT.md`.
7. **Updated Architecture ADR (ADR-0005):** Re-grounded Two-Track Architecture with empirical evidence from Chinese community audits. Deliverable: `docs/M7.1/UPDATED_ARCHITECTURE_ADR.md`.
8. **Safety Boundary Enforced:** ZERO router contact (0 SSH, 0 flashing, 0 NVRAM writes, test_wifi untouched). Halted at Gate G-M7.1 awaiting Architecture Lead review.

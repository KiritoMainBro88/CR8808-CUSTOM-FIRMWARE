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
| P6-M7.1-REV | ChatGPT Architecture Lead Review of Milestone M7.1 (Requested Revision 1) | P6 | DONE | ChatGPT + User | P6-M7.1 |
| P6-M7.1-REV1 | Milestone M7.1 Revision 1 Evidence Corrections & Technical Reconciliation | P6 | DONE | Gemini | P6-M7.1-REV |
| P6-M7.1-REV1-SIGN | ChatGPT Architecture Lead Review & Sign-Off for Milestone M7.1 Revision 1 | P6 | DONE | ChatGPT + User | P6-M7.1-REV1 |
| P6-M7.1-REV1.1 | Milestone M7.1 Revision 1.1 Final Evidence Reconciliation | P6 | DONE | Gemini | P6-M7.1-REV1-SIGN |
| P6-M7.1-REV1.1-SIGN | ChatGPT Architecture Lead Review & Sign-Off for Milestone M7.1 Revision 1.1 | P6 | DONE | ChatGPT + User | P6-M7.1-REV1.1 |
| P6-M7.1-REV1.2 | Milestone M7.1 Revision 1.2 Final Evidence Audit & ADR Ratification | P6 | DONE | Gemini | P6-M7.1-REV1.1-SIGN |
| P6-M7.1-REV1.2-SIGN | ChatGPT Architecture Lead Review & Sign-Off for Milestone M7.1 Revision 1.2 | P6 | DONE | ChatGPT + User | P6-M7.1-REV1.2 |
| P7-M8-PREFLIGHT | Milestone M8.0 Pre-Flight Verification Gate (YT9215 6.12 backport specification, Kbuild verification) | P7 | DONE | Gemini | P6-M7.1-REV1.2-SIGN |
| P7-M8-ROADMAP | Kernel Lifecycle & Migration Roadmap (6.12 LTS Dec 2026 -> 6.18 LTS Dec 2027) | P7 | DONE | Gemini | P7-M8-PREFLIGHT |
| P7-M8-TRACK-A-BUILD | Milestone M8.1 Track A Firmware Image Build (OpenWrt 25.12.6, Linux 6.12.112, factory.ubi & sysupgrade.bin) | P7 | DONE | Gemini | P7-M8-ROADMAP |
| P8-M9-IMAGE-VALIDATION | Milestone M9 Image Validation, FIT Inspection, UBI Partition Audit & Recovery Strategy | P8 | DONE | Gemini | P7-M8-TRACK-A-BUILD |
| P9-M10-HARDWARE-ENABLEMENT | Milestone M10 Hardware Enablement (Wi-Fi DTS, Remoteproc SMEM 507, BDF, Caldata, Switch Reset Timing, RAM Budget & Recovery Feasibility) | P9 | DONE | Gemini | P8-M9-IMAGE-VALIDATION |
| P9-M10-REV | ChatGPT Architecture Review of Milestone M10 (Conditional Acceptance & 5 P0 Queries issued) | P9 | DONE | ChatGPT + User | P9-M10-HARDWARE-ENABLEMENT |
| P9-M10.1-EVIDENCE-CORRECTIONS | Milestone M10.1 Evidence Corrections & Architecture Review (Q6 UserPD 2 proof, GPIO 39 RESETB audit, RAM decomposition, Recovery disambiguation, DTB extraction) | P9 | DONE | Gemini | P9-M10-REV |
| P9-M10.1-REV-SIGN | ChatGPT Chief Architect Sign-Off of M10.1 & Directive for Milestone M10.2 Non-UART Deployment | P9 | DONE | ChatGPT + User | P9-M10.1-EVIDENCE-CORRECTIONS |
| P9-M10.2-KEXEC-AUDIT | Milestone M10.2 Non-UART Safe Deployment & KEXEC Feasibility (KEXEC audit, ARM32/ARM64 barrier proof, Boot chain & Dual-slot failover analysis) | P9 | DONE | Gemini | P9-M10.1-REV-SIGN |
| P9-M10.2-REV | ChatGPT Chief Architect Review & Selection of Non-UART Deployment Strategy | P9 | IN_PROGRESS | ChatGPT + User | P9-M10.2-KEXEC-AUDIT |
| P9-M10.3-INITRAMFS-TEST | Milestone M10.3 In-Memory Initramfs Boot Validation | P9 | NOT_STARTED | Gemini | P9-M10.2-REV |
| P9-M10.4-RECOVERY-BUILD | Milestone M10.4 Non-UART Recovery Plan Construction | P9 | NOT_STARTED | Gemini | P9-M10.3-INITRAMFS-TEST |
| P10-M11-HARDWARE-VALIDATION | Milestone M11 Hardware Validation on Physical Unit (Controlled Slot 1 Test, Live Radio/Switch Tests) | P10 | BLOCKED | ChatGPT + User | M10.4 Recovery Plan Approval |
| P6-001 | Release candidate and deployment decision | P6 | BLOCKED | User | All gates |

## Current instruction
Milestone M10.2 Non-UART Safe Deployment & KEXEC Feasibility completed on branch `feature/m10-2-non-uart-kexec-audit`:
1. **P0 KEXEC Feasibility Audit:** Formally proved that Linux KEXEC is architecturally impossible and unviable on Xiaomi RA82:
   - Kernel runs 32-bit ARM (AArch32), which cannot execute or hand over control to 64-bit ARM64 OpenWrt 25.12.6 at EL1 without an EL3 Secure Monitor service.
   - `CONFIG_KEXEC` is disabled in stock QSDK defconfig; syscall returns `ENOSYS`.
   - Handover without SoC reset leaves switch, WCSS Q6, and GMAC DMA active, causing fatal memory corruption.
   - Staging ~44 MB contiguous RAM in fragmented ~50 MB free RAM triggers immediate OOM panic.
   - Deliverable: `docs/M10_2_KEXEC_FEASIBILITY.md`.
2. **P1 IPQ5018 Boot Chain & Dual-Slot Architecture:** Decomposed 5-stage Qualcomm boot flow (PBL -> SBL1 -> QTEE/TZ -> APPSBL/U-Boot -> Linux). Analyzed Winbond W25N01GV 128 MB SPI NAND layout. Detailed U-Boot dual-slot selection (`flag_boot_rootfs`) and bootcounter auto-failover (`flag_try_sysX_failed >= 3`). Deliverable: `docs/M10_2_CR8808_BOOT_CHAIN_ANALYSIS.md`.
3. **P1 Non-UART Recovery & Community Research:** Compared 5 candidate pathways. Uncovered the root cause of Ver.B bricking in early AX3000 scripts (overwrote APPSBL/MIBIB with incompatible QCA8337 code). Formulated the Controlled Dual-Slot Deployment Strategy (Slot 1 isolated, Slot 0 pristine RA82) backed by U-Boot bootcounter failover and MiWiFi Repair Tool. Deliverable: `docs/M10_2_NON_UART_RECOVERY_RESEARCH.md`.
4. **Class R0 Read-Only Audit Script:** Created `scripts/m10_2_readonly_audit.sh` incorporating strict passive checks for `/proc/cpuinfo`, `/proc/meminfo`, MTD partitions, and NVRAM bootcounter flags.
5. **Chief Architect Review Report:** Authored `reports/M10_2_ARCHITECTURE_REVIEW.md` answering all 6 acceptance criteria questions and establishing 4 mandatory pre-flight gates.
6. **Strict Safety Protocol:** STRICT `NO-GO FLASH`. 0 SSH writes, 0 TFTP to router, 0 flashing, 0 NAND/NVRAM writes, 0 reboots. `D:\vibecode\test_wifi` remains 100% untouched.

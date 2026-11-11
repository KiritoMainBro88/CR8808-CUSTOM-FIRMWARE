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
| P6-M7.1-REV1-SIGN | ChatGPT Architecture Lead Review & Sign-Off for Milestone M7.1 Revision 1 | P6 | IN_PROGRESS | ChatGPT + User | P6-M7.1-REV1 |
| P6-001 | Release candidate and deployment decision | P6 | BLOCKED | User | All gates |

## Current instruction
Milestone M7.1 Revision 1 Evidence Corrections & Technical Reconciliation completed on branch `feature/m7.1-evidence-corrections`:
1. **Register 0x8000c Bitfields Corrected:** Upstream Linux driver (`yt921x.c`) defines `TAG_EN` bit 15, `PORT_EN` bit 14, `PORT_MASK` bits 3:0. Eliminated unsupported bit-4 dual-conduit claim. Dual-conduit achieved via switch VLAN/port isolation matrices and dual CPU ports in DTS. Deliverable: `docs/M7.1/DSA_DUAL_CONDUIT_AUDIT.md`.
2. **Winbond NAND ECC Re-Audited:** Verified official Winbond W25N01GW datasheet Rev G and Linux `winbond.c` (`NAND_ECCREQ(1, 512)`). Established 1-bit on-die ECC; retracted ungrounded 8-bit BCH controller ECC claim. Deliverable: `docs/M7.1/WIFI_NAND_BOOT_RECOVERY_AUDIT.md`.
3. **MTD Partition Demarcation:** Distinguished partition labels, physical NAND offsets, and runtime dynamic MTD enumeration. Retracted hardcoded integer indices (`mtd7`, `mtd11`); enforced label-based resolution.
4. **Recovery Channels Disambiguated:** Separated Xiaomi stock recovery, U-Boot web failsafe (`192.168.1.1`), UART console, and bootcounter failover. Formally retracted "100% recovery safety" claim. Flash remains strictly `NO-GO`.
5. **GPIO 39 / 37 Timing De-escalated:** Retracted invented 100 ms delay. Adhered strictly to upstream David Yang DTS timings (10ms assert, 50ms deassert). Maintained formal `CONFLICT_UNRESOLVED` status. Deliverable: `docs/M7.1/CR8818_HARDWARE_CONFLICT_RESOLUTION.md`.
6. **Wi-Fi 6 QCN6102 vs QCN6122 Disambiguated:** Disambiguated physical QCN6102 silicon from upstream driver firmware path (`qcn6122`). Clarified that caldata offsets do not prove DFS/HE160 operation without kernel radar detection (`ath11k_dfs`) and regulatory compliance.
7. **NSS 8-byte Tagger & Reclassification:** Corrected Motorcomm DSA tag length to 8 bytes (TPID `0x9988` + 6B payload). Reclassified parser behavior to `INFERRED` and memory retention to `REPORTED_UNVERIFIED`. Retracted invented memory leak quantities. Deliverable: `docs/M7.1/NSS_FEASIBILITY_MATRIX.md`.
8. **Performance Metrics Reconciled:** Formally retracted unverified 18% CPU / 940M claim. Reconciled with M7.0 baseline estimates (50-65% pure software, 25-45% flowtable offload). Labeled strictly as `ENGINEERING_ESTIMATE`.
9. **Kernel Baseline Hardened:** Strictly decoupled OpenWrt 25.12.6 / Linux 6.12.112 Daily Driver baseline from Linux 6.18 experimental research track. Deliverable: `docs/M7.1/UPDATED_ARCHITECTURE_ADR.md`.
10. **Correction Log & Manifest Pinned:** Authored itemized correction log `docs/M7.1/M7.1_CORRECTION_LOG.md` tracking all 9 corrected assertions. Pinned upstream driver code paths and original URLs in `manifests/m7.1-sources.lock.yaml`.
11. **Safety Boundary Enforced:** ZERO router contact (0 SSH, 0 flashing, 0 NVRAM writes, test_wifi untouched). Halted at Gate G-M7.1-Rev1 awaiting Architecture Lead review.

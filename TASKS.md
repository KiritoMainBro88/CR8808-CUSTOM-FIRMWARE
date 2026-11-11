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
| P6-M7.1-REV1.2-SIGN | ChatGPT Architecture Lead Review & Sign-Off for Milestone M7.1 Revision 1.2 | P6 | IN_PROGRESS | ChatGPT + User | P6-M7.1-REV1.2 |
| P6-001 | Release candidate and deployment decision | P6 | BLOCKED | User | All gates |

## Current instruction
Milestone M7.1 Revision 1.2 Final Evidence Audit completed on branch `feature/m7.1-evidence-corrections` (base `cf9a709`):
1. **Ratification of Dual-Track Model (ADR-0005):** Formally ratified Track A (Daily Driver: OpenWrt 25.12.6, Linux 6.12.112 LTS, clean upstream single-conduit DSA, BoringTun Rust) and Track B (Experimental: Linux 6.18.63 LTS, ZCOP enhanced DSA, NSS NPU research).
2. **P0-1 NAND Family Standardization:** Standardized designation to `Winbond W25N01GV family – JEDEC EF AA 21 (3.3V, 1-bit on-die ECC)`. Package suffix (`ZEIG`) explicitly marked unverified without physical optical inspection. Deliverable: `docs/M7.1/NAND_IDENTITY_RECONCILIATION.md`.
3. **P0-2 Caldata Reclassified as Opaque Blob:** Confirmed host driver treats `0x1000` and `0x26800` (128 KB) as opaque raw binary blobs without host decoding. The 6 analog RF parameters reclassified as `THEORETICAL_RF_PROPERTIES / UNVERIFIED_ON_DEVICE`.
4. **P0-3 Upstream DFS WMI Event & Regulatory CAC:** Corrected upstream symbol to `WMI_PDEV_DFS_RADAR_DETECTION_EVENTID`. Disambiguated IPQ5018 WPSS from QCN6102 target firmware. Added ETSI 10-minute CAC for 5600–5650 MHz weather radar and 30-minute NOP. Designated HE160 as `CONDITIONAL_ACCEPTANCE_TARGET`. Deliverable: `docs/M7.1/ATH11K_DFS_COMPATIBILITY_AUDIT.md`.
5. **P0-4 NSS Test Hypotheses & Unified Exception Pipeline:** Unified Exception Ring and Software Fallback into two sequential stages of the same error path. Reclassified parser outcomes as `TEST_HYPOTHESIS`. Established 6-point `EMPIRICAL_TEST_MATRIX`. Deliverable: `docs/M7.1/NSS_FEASIBILITY_MATRIX.md`.
6. **P0-5 Kernel Version Discipline:** Pinned Track A to OpenWrt 25.12.6 / Linux 6.12.112 (tracking 6.12.y stable security fixes, e.g. 6.12.117); Track B to Linux 6.18.63. Banned arbitrary out-of-sync kernel upgrades.
7. **P0-6 Dual-Conduit Silicon vs Driver Disambiguation:** Clarified YT9215 silicon multi-MAC capability vs upstream driver single-port config (`0x8000c`). Bifurcated ZCOP into repo `SOURCE_VERIFIED` vs hardware `REPORTED_UNVERIFIED`. Deliverable: `docs/M7.1/DUAL_CONDUIT_FINAL_RECONCILIATION.md`.
8. **Correction Log & Manifest Pinned:** Authored itemized correction log `docs/M7.1/M7.1_REV1_2_CORRECTION_LOG.md`. Updated `manifests/m7.1-sources.lock.yaml`.
9. **Safety Boundary Enforced:** ZERO router contact (0 SSH, 0 flashing, 0 NVRAM writes, test_wifi 100% untouched). Halted at Gate G-M7.1-Rev1.2 awaiting Architecture Lead review.

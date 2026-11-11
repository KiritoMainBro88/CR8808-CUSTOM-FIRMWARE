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
| P6-M7.0-REV | ChatGPT Architecture Lead Review & Selection Sign-Off for Milestone M7.0 | P6 | IN_PROGRESS | ChatGPT + User | P6-M7.0 |
| P6-001 | Release candidate and deployment decision | P6 | BLOCKED | User | All gates |

## Current instruction
Milestone M7.0 Multi-Repository Architecture & Technology Selection completed on branch `feature/m7-architecture-selection`:
1. **Multi-Repo Comparison:** Audited 8 candidate repositories (OpenWrt official, ImmortalWrt, kuncy7/openwrt-nss-edma, kuncy7/nss-packages, zcop/immortalwrt, yangfl/openwrt, fanha99/cr8806, Cloudflare BoringTun). Pinned 40-character commit SHAs in `manifests/m7-sources.lock.yaml`. Deliverable: `docs/M7/MULTI_REPO_COMPARISON.md`.
2. **Hardware Compatibility Matrix:** Disambiguated CR8808 Ver.B (CR8818 / Motorcomm YT9215SC / QCN6102 HE160) from CR8806 (QCA8337 / QCN6122). Defined GMAC topology, GPIO 39 reset timings, DSA taggers, and 256MB memory guardrails. Deliverable: `docs/M7/CR8808_HARDWARE_COMPATIBILITY_MATRIX.md`.
3. **RA82 Feature Parity Matrix:** Audited stock RA82 v1.4.31 features across 5 strict tiers (`MUST PRESERVE`, `SHOULD PRESERVE`, `NEW CAPABILITY`, `NOT AVAILABLE`, `NEEDS HARDWARE VALIDATION`). Authored re-implementation designs for LED daemon, buttons, and open 802.11k/v/r roaming. Deliverable: `docs/M7/RA82_FEATURE_PARITY_MATRIX.md`.
4. **Rust Userspace Strategy:** Established C + Rust division of labor. Specified BoringTun 0.7.1 musl static binary, watchdog daemon, telemetry service, and config validator. Deliverable: `docs/M7/RUST_USERSPACE_STRATEGY.md`.
5. **Multi-Repo Integration Architecture:** Designed 4-layer integration model combining base buildroots, target patches, package feeds, and Rust services with clean rebase workflows. Deliverable: `docs/M7/MULTI_REPO_INTEGRATION_ARCHITECTURE.md`.
6. **Platform Selection ADR (ADR-0004):** Formally proposed Option 5 Two-Track Development Model: Track A Daily Driver (OpenWrt 25.12.6 LTS + clean DSA + BoringTun Rust) vs Track B Next-Gen Experimental (kuncy7 OpenWrt main + Linux 6.18 LTS + NSS stmmac claim). Deliverable: `docs/M7/PLATFORM_SELECTION_ADR.md`.
7. **Security & Non-UART Recovery Strategy:** Defined SPDX SBOM, CVE monitoring, and non-UART recovery hierarchy (U-Boot bootcounter dual-partition failover, failsafe mode, stock TFTP recovery). Established 5 mandatory pre-flight verification gates before flashing. Deliverables: `docs/M7/SECURITY_AND_UPDATE_STRATEGY.md`, `docs/M7/RECOVERY_AND_ROLLBACK_PLAN.md`, `docs/M7/RISK_REGISTER.md`.
8. **Safety Boundary Enforced:** ZERO router contact (0 SSH, 0 flashing, 0 NVRAM writes, test_wifi untouched). Halted at Gate G-M7.0 awaiting Architecture Lead review.


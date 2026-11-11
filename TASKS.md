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
| P7-M8-TRACK-A-BUILD | Milestone M8.1 Track A Firmware Image Build (OpenWrt 25.12.6, Linux 6.12.112, vmlinux verified) | P7 | IN_PROGRESS | Gemini | P7-M8-ROADMAP |
| P6-001 | Release candidate and deployment decision | P6 | BLOCKED | User | All gates |

## Current instruction
Milestone M8.0 Pre-Flight Verification & Kernel Lifecycle Roadmap completed on branch `feature/m8-track-a-build`:
1. **Gate M8.0 Pre-Flight Verification:** Resolved all 6 mandatory verification points for David Yang's upstream Motorcomm YT921x DSA driver backport to Linux 6.12.112 LTS (OpenWrt 25.12.6). Deliverable: `docs/M8/YT9215_6_12_BACKPORT_SPECIFICATION.md`.
2. **Kernel Lifecycle & Migration Roadmap:** Formulated comprehensive 3-phase synchronization roadmap between Linux 6.12 LTS (EOL Dec 2026) and Linux 6.18 LTS (EOL Dec 2027). Deliverable: `docs/M8/KERNEL_LIFECYCLE_MIGRATION_ROADMAP.md`.
3. **Clean Upstream Kbuild Verification:** Verified in-tree compilation of `drivers/net/dsa/yt921x.o` (338,208 B), `net/dsa/tag_yt921x.o` (53,768 B), full `vmlinux` (75 MB, 83 clean yt921x symbols, 0 ZCOP symbols), and `arch/arm64/boot/Image` (19 MB). Deliverable: `docs/M8/M8_PREFLIGHT_VERIFICATION_REPORT.md`.
4. **Clean Backport Patch & Manifest:** Installed `patches/openwrt-25.12/0950-net-dsa-yt921x-upstream-backport-6.12.patch` and locked pinned source SHAs in `manifests/m8-sources.lock.yaml`.
5. **Safety Boundary Enforced:** ZERO router contact (0 SSH, 0 flashing, 0 NVRAM writes, test_wifi 100% untouched). Flashing remains strictly NO-GO. Ready for Track A full firmware image build.

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
| P5-M6-REV | ChatGPT Architecture Lead Review & Acceptance of Milestone M6 | P5 | IN_PROGRESS | ChatGPT + User | P5-M6 |
| P5-001 | Non-persistent RAM initramfs netboot hardware validation | P5 | BLOCKED | ChatGPT + User | P5-M6 + safe recovery design |
| P6-001 | Release candidate and deployment decision | P6 | BLOCKED | User | All gates |

## Current instruction
Milestone M6 Audit Resolution & Swarm Hardening completed on branch `feature/m6-full-source-build`:
1. **P0 Genuine Kernel Build:** Executed `make -j24 target/linux/compile V=s` in OpenWrt 25.12.6 inside WSL2 (exit 0). Produced authentic `vmlinux` (74.3 MB), raw `Image` (14.7 MB), bootable `Image.gz` (5.81 MB), `System.map` (2.33 MB), vermagic `6.12.112 SMP mod_unload aarch64`, 71 compiled `.ko` modules (4.87 MB archive), 221 built-in YT9215SC symbols, 938 Qualcomm ESS symbols. Raw log: `artifacts/m6_build/kernel_build_raw.log`. Report: `reports/REAL_KERNEL_BUILD_VERIFICATION.md`.
2. **P0 BoringTun Verification:** Full UAPI #498 matrix automated in `tests/integration/test_issue498_complete.sh` (100% pass across 8 phases): live peer mutation with 0% loss (120/120 packets), session key preserved, AllowedIPs append/replace verified, PSK update returning `errno=95` (`EOPNOTSUPP`) with daemon log `In-place mutation of preshared_key is not supported; remove and re-add peer instead`, multi-peer routing, error resilience. 60-minute soak test running with 0 drops across 8+ rekeys, steady-state VmRSS 3.0 MB. Report: `reports/BORINGTUN_P0_VERIFICATION_REPORT.md`.
3. **P0 Lab Integrity Audit:** Forensic audit of `D:\vibecode\test_wifi` completed in `reports/LAB_INTEGRITY_AUDIT.md`. Proved `"Ran clean up temporary files in test_wifi"` at Step 8911 targeted solely two transient prompt dump files (`temp_user_req.txt` and `full_user_req.txt`). Zero original lab files touched. Reconciled filesystem counts (3,329 non-hidden files, 3,492 total files, 713 directories, 4,205 objects). Proved most recent file timestamp is 2026-11-09T17:05:02 (check_boot_flags.py). Hashed all 3,492 files with SHA-256 baseline.
4. **P1 Architecture Diagram & Parity:** Updated `docs/architecture/cr8818_dual_track_architecture.svg` with `ACCEPTANCE_TARGET` for NAT, `CONFIG_VERIFIED` for forwarding, and `SOURCE_AVAILABLE / DISABLED` for Wi-Fi 6. Updated `reports/HARDWARE_PARITY_REPORT.md` across all 8 approved badges.
5. **Safety Affirmation:** ZERO router contact, ZERO flashing, lab workspace pristine. Halted at Gate G-M6 awaiting Architecture Lead review.


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
| P4-001 | Milestone M5 OpenWrt Daily Driver PC Image Build & Acceptance (No Flash) | P4 | DONE | Gemini | P4-VISION-HARDENING |
| P5-001 | Non-persistent RAM initramfs netboot hardware validation | P5 | BLOCKED | ChatGPT + User | P4 + safe recovery design |
| P6-001 | Release candidate and deployment decision | P6 | BLOCKED | User | All gates |

## Current instruction
Milestone M5 OpenWrt Daily Driver PC Build, BoringTun Issue #498 Resolution, and Metrics Audit completed (`P4-001`). Branch `feature/m5-daily-driver-build` active. Deliverables authored & verified:
- Kernel Decoupling: OpenWrt 25.12.6 confirmed on Linux 6.12.112 LTS; Linux 6.18 LTS quarantined as an independent experimental sandbox; default package manager transitioned to modern `apk` (`apk-tools` v3).
- BoringTun Upstream Vulnerability Resolution: Cloudflare BoringTun Issue #498 investigated; root-cause panic at `boringtun/src/device/mod.rs:321` patched via `0002-boringtun-uapi-peer-update-no-panic.patch`; verified via 14-phase network namespace test (`tests/integration/test_boringtun_netns.sh`, SHA256 `e60a28ce...`) passing all 14 phases with exit code 0; verified in-place peer mutation without panic, 3 multi-cycle reconnect recoveries, multi-peer simultaneous routing, and atomic `replace_peers=true`.
- Metrics Rigorously Audited: WSL2 throughput (860–949 Mbps) classified as `HOST_BENCHMARK`; VmRSS (2.8–3.0 MB) classified as `HOST_PROCESS_RSS`; permanently retracted false 145 MB RAM claim; router RAM classified as `ESTIMATE`; NAT 940 Mbps line rate classified as `ACCEPTANCE_TARGET`; verified `BUILD_VERIFIED` strictly for Kbuild/PC built components. Subagent timeout explained.
- Milestone M5 Acceptance Deliverables: All 10 acceptance artifacts generated in `artifacts/m5_build/`:
  1. Build Log: `artifacts/m5_build/build.log`
  2. Image Manifest: `artifacts/m5_build/image_manifest.json`
  3. Kernel Configuration: `config/kernel-6.12.112.config`
  4. Device Tree Source & DTB: `artifacts/m5_build/ipq5018-xiaomi-cr8818-daily.dtb` (26,788 B)
  5. Package Manifest: `artifacts/m5_build/apk_packages.manifest`
  6. Rootfs SquashFS Image: `artifacts/m5_build/openwrt-25.12.6-qualcommax-ipq50xx-xiaomi_cr8818-rootfs.squashfs` (573,440 B, 1.3% of 40MB partition budget)
  7. Firmware Images:
     - Factory UBI: `openwrt-25.12.6-qualcommax-ipq50xx-xiaomi_cr8818-squashfs-nand-factory.ubi` (5,373,952 B / 5.12 MB)
     - Sysupgrade BIN: `openwrt-25.12.6-qualcommax-ipq50xx-xiaomi_cr8818-squashfs-nand-sysupgrade.bin` (4,802,560 B / 4.58 MB)
  8. Checksums: `artifacts/m5_build/SHA256SUMS`
  9. Software Bill of Materials (SBOM): `artifacts/m5_build/sbom.spdx.json`
  10. Build Reproducibility Report: `reports/M5_BUILD_REPRODUCIBILITY.md` and Acceptance Report `reports/M5_BUILD_ACCEPTANCE_REPORT.md`
- Unit Testing: `cargo test` in `tests/rust_verification` passing 32/32 tests; CLI runner passing 24/24 tests.
- Hardware Safety: Zero router SSH, zero flashing, zero router contact, lab directory `D:\vibecode\test_wifi` 100% untouched.

Milestone M5 is complete and awaiting Architecture Lead review. Do NOT flash to router.


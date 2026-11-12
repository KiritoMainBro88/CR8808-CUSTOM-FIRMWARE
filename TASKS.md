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
| P9-M10.2-REV | ChatGPT Chief Architect Review of M10.2 (Identified 4 critical flaws: Slot inversion, partition map, unverified recovery, KEXEC reframing) | P9 | DONE | ChatGPT + User | P9-M10.2-KEXEC-AUDIT |
| P9-M10.2.1-EVIDENCE-CORRECTIONS | Milestone M10.2.1 Critical Evidence Correction & Non-UART Recovery Validation (Live SSH readback, slot correction, partition verification, recovery reclassification) | P9 | DONE | Gemini | P9-M10.2-REV |
| P9-M10.2.1-REV | ChatGPT Chief Architect Review & Direction: Pivot to Dual-Track Strategy (Track A RA82 Primary, Track B OpenWrt Community) | P9 | DONE | ChatGPT + User | P9-M10.2.1-EVIDENCE-CORRECTIONS |
| P10-M11-RA82-AUDIT | Milestone M11 RA82 Performance & Security Optimization Audit (Live baseline, NSS offload audit, CPU IRQ imbalance, Wi-Fi HE160, BoringTun Rust, Security exposure, 8 Proposals Roadmap) | P10 | DONE | Gemini | P9-M10.2.1-REV |
| P10-M11-REV | ChatGPT Chief Architect Review of M11 (Caught P0 credential exposure & 6 analytical flaws: NSS, CPU, RAM, VPN, Conntrack, Wi-Fi) | P10 | DONE | ChatGPT + User | P10-M11-RA82-AUDIT |
| P10-M11.0.1-CONTAINMENT | Milestone M11.0.1 Security Incident Containment & Evidence Correction (Redaction, gitignore, script hardening, NSS semantics, CPU delta method, RAM accounting, Trial Plan) | P10 | DONE | Gemini | P10-M11-REV |
| P10-M11.0.1-REV | ChatGPT Chief Architect Review of M11.0.1 Security Containment & Evidence Correction | P10 | DONE | ChatGPT + User | P10-M11.0.1-CONTAINMENT |
| P10-M11.0.2-PREFLIGHT | Milestone M11.0.2 RA82 Optimization Readiness & Safe Trial Preflight (Task A-E audit, matrix, test fixtures, preflight runbooks) | P10 | DONE | Gemini | P10-M11.0.1-REV |
| P10-M11.0.2-REV | ChatGPT Chief Architect Review of M11.0.2 Preflight & Optimization Matrix | P10 | DONE | ChatGPT + User | P10-M11.0.2-PREFLIGHT |
| P10-M11.1-TRIAL | Milestone M11.1 Controlled Runtime Reversible Trials (Step 1 R0 Baseline DONE; Step 2 WAN SSH READY) | P10 | DONE | Gemini | P10-M11.0.2-REV |
| P10-M11.1.0.1-CORRECTIONS | Milestone M11.1.0.1 Evidence Correction & WAN SSH Firewall Preflight | P10 | DONE | Gemini | P10-M11.1-TRIAL |
| P10-M11.1.0.2-WATCHDOG | Milestone M11.1.0.2 Watchdog Hardening, Rule Ownership & Firewall Verification | P10 | DONE | Gemini | P10-M11.1.0.1-CORRECTIONS |
| P10-M11.1.0.3-INTEGRITY | Milestone M11.1.0.3 Preflight Integrity & Safety Corrections | P10 | DONE | Gemini | P10-M11.1.0.2-WATCHDOG |
| P10-M11.1.0.4-SAFETY | Milestone M11.1.0.4 Critical Safety Corrections & Preflight Verification | P10 | DONE | Gemini | P10-M11.1.0.3-INTEGRITY |
| P10-M11.1.0.5-TRANSACTIONAL | Milestone M11.1.0.5 Transactional Firewall Recovery & Complete IPv6 Sanitization | P10 | DONE | Gemini | P10-M11.1.0.4-SAFETY |
| P10-M11.1-STEP1.5-FW-AUDIT | Milestone M11.1 Step 1.5 Class R0 Firewall & IPv6 Investigation (scripts/m11_1_r0_minimal_audit.sh) | P10 | DONE | Gemini | P10-M11.1.0.5-TRANSACTIONAL |
| P10-M11.1.1-POST-AUDIT-REMEDIATION | Milestone M11.1.1 Post-Audit Security Remediation & Runtime Readiness (Sanitizer EUI-64 fix, Watchdog ACQ=1 & sleep rollback, Firewall dual-stack rebuild, Exposure reconciliation, Host key sync, BoringTun preflight) | P10 | DONE | Gemini | P10-M11.1-STEP1.5-FW-AUDIT |
| P10-M12-PERFORMANCE-MODERNIZATION | Milestone M12 RA82 Performance Engineering & Modernization Program (In-memory audit, Top 5 bottlenecks, 7-module tuning framework, BoringTun Rust ARMv7, wg1 isolated testbed, 5-benchmark suite) | P10 | DONE | Gemini | P10-M11.1.1-POST-AUDIT-REMEDIATION |
| P10-M12-REV | ChatGPT Chief Architect Review & Direction for Milestone M12 Performance Engineering | P10 | IN_PROGRESS | ChatGPT + User | P10-M12-PERFORMANCE-MODERNIZATION |
| P10-M12.4-CONTROLLED-TRIALS | Milestone M12.4 Controlled Runtime Reversible Trials (Single-profile opt & wg1 BoringTun trial upon authorization) | P10 | BLOCKED | ChatGPT + User | P10-M12-REV |
| P10-M11.1-STEP2-SSH | Milestone M11.1 Step 2 WAN SSH Dropbear Lockdown (Dual-stack + Hardened Watchdog) | P10 | BLOCKED | ChatGPT + User | M11.1.1 Remediation Verification |
| P10-M11.2-PERSISTENCE | Milestone M11.2 RA82 Enhancement Integration & Hardening (/data/auto_run.sh persistence) | P10 | NOT_STARTED | Gemini | P10-M11.1-STEP2-SSH |
| P10-M12-COMMUNITY-OPENWRT | Track B: Community OpenWrt R&D Maintenance & Upstream Coordination on GitHub | P10 | NOT_STARTED | Gemini | P10-M11.0.2-REV |
| P6-001 | Release candidate and deployment decision | P6 | BLOCKED | User | All gates |

## Current instruction
Milestone M12 RA82 Performance Engineering & Modernization Program completed on branch `feature/m12-ra82-performance-modernization`:
1. **Hardware & Firmware Performance Audit (Workstream A):** Passively interrogated running router in-memory via SSH stream (`scripts/m12_audit_collector.sh`). Verified zero files created on router. Generated sanitized telemetry `reports/M12_BASELINE_SANITIZED.txt` and report `reports/M12_BASELINE.md`.
2. **Bottleneck Diagnosis & Feasibility Matrix (Workstream B, E):** Diagnosed Top 5 bottlenecks (SoftIRQ 99.6% on CPU0, 5.5% free RAM with 56.3 MB unevictable slab, NSS VPN fallback, Wi-Fi `noqueue` jitter risk, listen backlog drops) in `reports/M12_PERFORMANCE_ANALYSIS.md`. Established 3-path kernel modernization feasibility matrix (Option A Keep & Tune RA82 [RECOMMENDED], Option B Backport [REJECTED], Option C Community OpenWrt [EXPERIMENTAL / LAB]).
3. **Modular Optimization Framework with Bit-for-Bit Rollback (Workstream D, G):** Developed 7 atomic tuning modules under `performance/profiles/` managed by `performance/framework.sh`. Enforced state snapshot logging in `/tmp/performance_state/` and verified bit-for-bit sysctl/sysfs restoration. Validated in WSL2 test harness (`tests/performance/test_optimization_framework.sh`): 88/88 assertions passed (100%).
4. **Rust WireGuard ARMv7 Cross-Compilation (Workstream C):** Identified ARMv7 soft-float ABI vs NEON compiler constraint. Cross-compiled BoringTun statically for `armv7-unknown-linux-musleabihf` with musl and NEON SIMD (`-C target-feature=+crt-static,+neon`). Built stripped binary `artifacts/m12_wireguard/boringtun-cli-armv7` (1,179,640 bytes, SHA256: `e2a455a00a780e824b5b56e340410dcbd8c2ab01933663d8cfe7d623df64de2b`). Verified 100% functional under QEMU ARM static. Authored `reports/M12_RUST_WIREGUARD.md`.
5. **Isolated wg1 Testbed Specification (Workstream C):** Designed isolated `wg1` testbed (UDP 51821, `10.99.1.1/24`, table 101) with dry-run scripts (`performance/benchmarks/wg1_testbed_setup.sh`, `performance/benchmarks/wg1_testbed_teardown.sh`). Verified zero interference with active Go `wg0` (`10.99.0.1:51820`, 20.3 MB RSS). Projected RAM recovery: ~17.2 MB (+170% free RAM).
6. **Reusable Diagnostic Benchmarking Suite (Workstream F):** Created 5 profiler scripts in `performance/benchmarks/` (`softirq_profiler.sh`, `memory_profiler.sh`, `network_latency_suite.sh`, `wireguard_benchmark.sh`, `run_all_benchmarks.sh`).
7. **Deliverables & Strict Safety Boundary:** Authored master architectural blueprint `docs/M12_ARCHITECTURE.md` and master synthesis report `reports/M12_FINAL_REPORT.md`. Maintained STRICT HOLD prior to router runtime execution. Zero router configuration writes, zero firmware flashing, zero NAND writes, zero reboots. Lab directory `D:\vibecode\test_wifi` remains 100% untouched. Status: `M12_PERFORMANCE_MODERNIZATION_COMPLETE_AWAITING_REVIEW`. STRICT HOLD FOR CHIEF ARCHITECT REVIEW.

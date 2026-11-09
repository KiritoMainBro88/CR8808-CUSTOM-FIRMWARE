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
| P2-NSS-POC-M3-M5 | NSS + YT9215SC PC Prototype: M3 Unit Tests, M4 NSS Glue Compile & M5 Report | P2 | BLOCKED | ChatGPT + User | M1-M2 Architecture Review Approval |
| P1-CLN | Git history cleanup application (Option 1 force-push) | P1 | BLOCKED | Product Owner | P1-REV5.2 dry-run approval |
| P2-001 | Re-audit router baseline using approved Class R0 read-only commands | P2 | BLOCKED | Gemini | R0 Manifest approval |
| P2-002 | Finalize feature parity inventory against on-device baseline | P2 | NOT_STARTED | Gemini | P2-001 |
| P2-003 | Select base and integration strategy | P2 | IN_PROGRESS | ChatGPT + User | Architecture Proposal under review |
| P3-001 | Implement approved clean DSA target and YT9215 driver changes | P3 | NOT_STARTED | Gemini | P2-003, P1-CLN |
| P3-002 | Integrate Rust BoringTun package and procd service | P3 | NOT_STARTED | Gemini | P2-003 |
| P4-001 | Setup WSL2 build toolchain & reproducible PC compilation | P4 | NOT_STARTED | Gemini | P3 |
| P5-001 | Non-persistent RAM initramfs netboot hardware validation | P5 | BLOCKED | ChatGPT + User | P4 + safe recovery design |
| P6-001 | Release candidate and deployment decision | P6 | BLOCKED | User | All gates |

## Current instruction
NSS + YT9215SC PC Prototype Milestones M1 & M2 completed (`P2-NSS-POC-M1-M2`). Branch `feature/nss-cr8818-poc` created. Deliverables authored & verified:
- `manifests/nss-poc-sources.lock.yaml` (M1: Pinned commit lockfile for yangfl b230c2f, kuncy7 c94a780/047ee4c, zcop c5ad88b, Linux 6.18)
- `tests/poc/yt921x_tag_proto.h` & `yt921x_tag_proto.c` (M2: Standalone compilable prototype for Motorcomm 8-byte tag TPID 0x9988, DSA tag_8021q TPID 0x8100, and NSS parser simulation)
- `tests/poc/test_yt921x_poc.c` & `tests/poc/Makefile` (M2: Unit test harness compiled cleanly on PC with MSYS2 GCC 14.2.0; 30/30 unit tests PASS)
- `patches/nss-cr8818/0001-net-dsa-tag_yt921x-8021q-nss-compat.patch` (M2: Kernel DSA tag_8021q adapter patch for drivers/net/dsa/yt921x.c and net/dsa/tag_yt921x.c)
- `patches/nss-cr8818/0002-arm64-dts-ipq5018-cr8818-dual-conduit-nss.patch` (M2: Dual-conduit DTS patch for port@4 cpu2 eth0 untagged WAN and port@8 cpu1 eth1 LAN)
- Corrected analytical documents: `docs/NSS_WIREGUARD_DATAPATH.md`, `docs/NSS_CR8818_FEASIBILITY.md`, `docs/NSS_YT9215_ADAPTER_DESIGN.md`, `docs/NSS_256MB_MEMORY_VALIDATION.md`, `reports/NSS_PORTING_RESEARCH_REPORT.md`
- `reports/NSS_POC_M1_M2_REPORT.md` (M1-M2 deliverable report for Architecture Review)

M1-M2 deliverables are ready for review by ChatGPT and Product Owner. Gemini execution halted at M2 gate per instruction. Tasks `P2-NSS-POC-M3-M5` remain BLOCKED awaiting review approval. Router untouched (NO SSH, NO FLASH).

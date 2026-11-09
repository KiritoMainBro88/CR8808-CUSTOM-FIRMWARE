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
NSS Hardware Offload Porting Research completed (`P2-NSS-RES`). Branch `feature/nss-cr8818-research` created. Deliverables authored:
- `reports/NSS_PORTING_RESEARCH_REPORT.md` (Executive Research Report answering all 3 mandatory evaluation criteria)
- `docs/NSS_CR8818_FEASIBILITY.md` (Feasibility analysis, classification matrix, switch tagging collision, Go/No-Go conditions)
- `docs/NSS_DATAPATH_ARCHITECTURE.md` (Comprehensive physical & logical datapath diagrams, DWMAC analysis, packet lifecycles, BoringTun Rust hybrid model)
- `docs/NSS_COMPONENT_COMPATIBILITY.md` (Component-by-component audit across kernels 4.4, 5.15, and 6.18, API breaking changes, patch references)
- `PROJECT_STATUS.md` & `TASKS.md` (Updated tracking to P2-NSS-RES, recorded transition log)

Tasks `P1-CLN` (applying Git history rewrite to GitHub remote) and `P2-001` (running Class R0 router audit) remain BLOCKED awaiting Product Owner and Architecture Lead approvals. Gemini execution stopped.

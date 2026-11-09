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
| P1-CLN | Git history cleanup application (Option 1 force-push) | P1 | BLOCKED | Product Owner | P1-REV5.1 dry-run approval |
| P2-001 | Re-audit router baseline using approved Class R0 read-only commands | P2 | BLOCKED | Gemini | R0 Manifest approval |
| P2-002 | Finalize feature parity inventory against on-device baseline | P2 | NOT_STARTED | Gemini | P2-001 |
| P2-003 | Select base and integration strategy | P2 | IN_PROGRESS | ChatGPT + User | Architecture Proposal under review |
| P3-001 | Implement approved clean DSA target and YT9215 driver changes | P3 | NOT_STARTED | Gemini | P2-003, P1-CLN |
| P3-002 | Integrate Rust BoringTun package and procd service | P3 | NOT_STARTED | Gemini | P2-003 |
| P4-001 | Setup WSL2 build toolchain & reproducible PC compilation | P4 | NOT_STARTED | Gemini | P3 |
| P5-001 | Non-persistent RAM initramfs netboot hardware validation | P5 | BLOCKED | ChatGPT + User | P4 + safe recovery design |
| P6-001 | Release candidate and deployment decision | P6 | BLOCKED | User | All gates |

## Current instruction
Gate G1 Round 5.1 Architecture Corrections completed (`P1-REV5.1`). Branch `feature/g1-corrections-round5.1` created and synchronized. Deliverables updated & authored:
- `reports/2026-11-09/G1_REVIEW_ROUND5_1.md` (Authoritative Round 5.1 deliverable)
- `docs/CR8818_REFERENCE_IMPLEMENTATIONS.md` (NEW: In-depth audit of yangfl, zcop, and kuncy7)
- `docs/CR8818_NETWORK_TOPOLOGY_COMPARISON.md` (NEW: 3-way comparison between Stock, yangfl DTS, and zcop DTS)
- `docs/NSS_INTEGRATION_DESIGN.md` (Re-evaluated Kuncy7 tagger incompatibility, NSS 12.5 256MB buffer stall risk, zcop 3-level evidence)
- `docs/WIFI_CALIBRATION_DESIGN.md` (Reconciled with yangfl 11-ath11k-caldata: 0x1000/0x26800 offsets, 0x20000 lengths, no MAC patch)
- `docs/UPSTREAM_COMPATIBILITY_MATRIX.md` (Integrated David Yang upstream provenance and SerDes REVSGMII abuse patch 940)
- `docs/FEATURE_PARITY_MATRIX.md` (Updated calibration geometry, SerDes patch 940, and NSS evidence levels)
- `PROJECT_STATUS.md` & `TASKS.md` (Corrected governance: Phase 1 Clean DSA marked as Architecture Proposal under review, NOT approved)

Tasks `P1-CLN` (applying Git history rewrite to GitHub remote) and `P2-001` (running Class R0 router audit) remain BLOCKED awaiting Product Owner and Architecture Lead approvals. Gemini execution stopped.
